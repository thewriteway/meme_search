import sqlite3
import threading
import requests
from fastapi import FastAPI, HTTPException, Request
from pydantic import ValidationError
from data_models import JobModel
from constants import APP_URL
from constants import JOB_DB
from job_queue import init_db
import jobs as jobs_module
from jobs import process_jobs
from log_config import logging


# log APP_URL and JOB_DB
logging.info(f"the app url for return signals from the image to text generator is defined as: {APP_URL}")
logging.info(f"the local job db for the image to text service is defined as: {JOB_DB}")

# initialize FastAPI app
app = FastAPI()


def ensure_attempt_columns(conn):
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(jobs)")
    column_names = {row[1] for row in cursor.fetchall()}
    if "attempt_id" not in column_names:
        cursor.execute("ALTER TABLE jobs ADD COLUMN attempt_id INTEGER")
    if "callback_token" not in column_names:
        cursor.execute("ALTER TABLE jobs ADD COLUMN callback_token TEXT")
    conn.commit()


def attempt_details_for_image(image_core_id):
    conn = sqlite3.connect(JOB_DB)
    try:
        ensure_attempt_columns(conn)
        cursor = conn.cursor()
        cursor.execute(
            "SELECT attempt_id, callback_token FROM jobs WHERE image_core_id = ? ORDER BY id LIMIT 1",
            (image_core_id,),
        )
        row = cursor.fetchone()
        if row is None:
            return None, None
        return row[0], row[1]
    finally:
        conn.close()


def add_attempt_fields(payload, attempt_id=None, callback_token=None):
    enriched = dict(payload)
    if attempt_id is None or callback_token is None:
        attempt_id, callback_token = attempt_details_for_image(payload["image_core_id"])
    if attempt_id is not None and callback_token:
        enriched["attempt_id"] = attempt_id
        enriched["callback_token"] = callback_token
    return enriched


def post_callback(path, payload, app_url):
    response = requests.post(app_url + path, json={"data": payload}, timeout=30)
    return response.status_code >= 200 and response.status_code < 300, response.status_code


def status_sender(status_job_details: dict, app_url: str) -> None:
    try:
        payload = add_attempt_fields(status_job_details)
        success, status_code = post_callback("status_receiver", payload, app_url)
        if success:
            logging.info("SUCCESS: status_sender successfully delivered")
        else:
            logging.info("FAILURE: status_sender failed to deliver with response code %s", status_code)
    except Exception as e:
        logging.error(f"FAILURE: status_sender failed with exception {e}")


def description_sender(output_job_details: dict, app_url: str) -> None:
    try:
        payload = add_attempt_fields(output_job_details)
        success, status_code = post_callback("description_receiver", payload, app_url)
        if success:
            logging.info("SUCCESS: description_sender successfully delivered")
        else:
            logging.info("FAILURE: description_sender failed to deliver with response code %s", status_code)
    except Exception as e:
        logging.error(f"FAILURE: description_sender failed with exception {e}")


def failure_sender(image_core_id: int, error_message: str, app_url: str) -> None:
    attempt_id, callback_token = attempt_details_for_image(image_core_id)
    status_sender(
        add_attempt_fields(
            {"image_core_id": image_core_id, "status": 5, "error_message": error_message},
            attempt_id,
            callback_token,
        ),
        app_url,
    )
    description_sender(
        add_attempt_fields(
            {"image_core_id": image_core_id, "description": f"Error: {error_message}"},
            attempt_id,
            callback_token,
        ),
        app_url,
    )


jobs_module.status_sender = status_sender
jobs_module.description_sender = description_sender
jobs_module.failure_sender = failure_sender

@app.get("/")
def home():
    logging.info("HELLO WORLD")
    return {"status": "HELLO WORLD"}


@app.post("/add_job")
async def add_job(request: Request):
    raw_job = await request.json()
    try:
        job = JobModel(**raw_job)
    except ValidationError as error:
        raise HTTPException(status_code=422, detail=error.errors(include_context=False)) from error

    attempt_id = job.attempt_id
    callback_token = job.callback_token

    conn = sqlite3.connect(JOB_DB)
    ensure_attempt_columns(conn)
    cursor = conn.cursor()

    cursor.execute(
        "INSERT INTO jobs (image_core_id, image_path, model, attempt_id, callback_token) VALUES (?, ?, ?, ?, ?)",
        (job.image_core_id, job.image_path, job.model, attempt_id, callback_token),
    )
    conn.commit()
    conn.close()

    logging.info("Job added to queue: %s", job)

    # update status
    status_job_details = add_attempt_fields(
        {"image_core_id": job.image_core_id, "status": 1},
        attempt_id,
        callback_token,
    )

    # send status update (image out of queue and in process)
    status_sender(status_job_details, APP_URL)

    return {"status": "Job added to queue"}


@app.get("/check_queue")
def check_queue():
    conn = sqlite3.connect(JOB_DB)
    cursor = conn.cursor()

    cursor.execute("SELECT COUNT(*) FROM jobs")
    count = cursor.fetchone()[0]

    conn.close()

    logging.info("Queue length: %s", count)

    return {"queue_length": count}


@app.delete("/remove_job/{image_core_id}")
def remove_job(image_core_id: int):
    conn = sqlite3.connect(JOB_DB)
    ensure_attempt_columns(conn)
    cursor = conn.cursor()

    # Check if the job exists
    cursor.execute("SELECT attempt_id, callback_token FROM jobs WHERE image_core_id = ?", (image_core_id,))
    job = cursor.fetchone()

    if job is None:
        conn.close()
        logging.warning("Attempted to remove a job that does not exist: %s", image_core_id)

        return {"status": "Job removed from queue"}

    # Remove the job from the database
    attempt_id, callback_token = job
    cursor.execute("DELETE FROM jobs WHERE image_core_id = ?", (image_core_id,))
    conn.commit()
    conn.close()

    logging.info("Job removed from queue: %s", image_core_id)

    # run status update
    status_job_details = add_attempt_fields(
        {"image_core_id": image_core_id, "status": 0},
        attempt_id,
        callback_token,
    )
    status_sender(status_job_details, APP_URL)

    return {"status": "Job removed from queue"}


if __name__ == "__main__":
    # look for 'testing' command line argument if passed
    import sys
    if len(sys.argv) > 1:
        # collect first arg
        arg = sys.argv[1]
        if arg == "testing":
            # get current working directory
            import os
            dir = os.getcwd()

            # update JOB_DB for testing
            JOB_DB = dir + "/tests/db/job_queue.db"

            # log updated JOB_DB
            logging.info(f"INFO: TESTING with updated job db located at: {JOB_DB}")

            # delete the db file if it exists
            if os.path.exists(JOB_DB):
                os.remove(JOB_DB)

            # reset APP_URL for testing
            APP_URL = "http://localhost:3000/"

    # Initialize the database
    init_db(JOB_DB)
    conn = sqlite3.connect(JOB_DB)
    ensure_attempt_columns(conn)
    conn.close()

    # initialize model (optional)
    # init_model()

    # Start the job processing thread - pass JOB_DB
    threading.Thread(target=process_jobs, args=(JOB_DB, APP_URL,), daemon=True).start()
    # threading.Thread(target=process_jobs, daemon=True).start()

    # Run the FastAPI app
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
