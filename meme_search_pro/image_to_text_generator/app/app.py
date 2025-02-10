import sqlite3
import threading
import logging
from data_models import JobModel
from constants import APP_URL
from constants import JOB_DB
from job_queue import init_db
from senders import status_sender
from jobs import process_jobs

# initialize logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")

# log APP_URL and JOB_DB
logging.info(f"the app url for return signals from the image to text generator is defined as: {APP_URL}")
logging.info(f"the local job db for the image to text service is defined as: {JOB_DB}")


from fastapi import FastAPI

# initialize FastAPI app
app = FastAPI()

@app.post("/add_job")
def add_job(job: JobModel):
    conn = sqlite3.connect(JOB_DB)
    cursor = conn.cursor()

    cursor.execute(
        "INSERT INTO jobs (image_core_id, image_path, model) VALUES (?, ?, ?)",
        (job.image_core_id, job.image_path, job.model),
    )
    conn.commit()
    conn.close()

    logging.info("Job added to queue: %s", job)

    # update status
    status_job_details = {"image_core_id": job.image_core_id, "status": 1}

    # send status update (image out of queue and in process)
    status_sender(status_job_details)

    return {"status": "Job added to queue"}


@app.delete("/remove_job/{image_core_id}")
def remove_job(image_core_id: int):
    conn = sqlite3.connect(JOB_DB)
    cursor = conn.cursor()

    # Check if the job exists
    cursor.execute("SELECT * FROM jobs WHERE image_core_id = ?", (image_core_id,))
    job = cursor.fetchone()

    if job is None:
        conn.close()
        logging.warning("Attempted to remove a job that does not exist: %s", image_core_id)

        # send signal to update status
        status_job_details = {"image_core_id": image_core_id, "status": 3}

        # send status update (reset status)
        status_sender(status_job_details)

        return {"status": "Job removed from queue"}

    # Remove the job from the database
    cursor.execute("DELETE FROM jobs WHERE image_core_id = ?", (image_core_id,))
    conn.commit()
    conn.close()

    logging.info("Job removed from queue: %s", image_core_id)

    # run status update
    status_job_details = {"image_core_id": image_core_id, "status": 0}
    status_sender(status_job_details)

    return {"status": "Job removed from queue"}


@app.get("/")
def home():
    logging.info("HELLO WORLD")
    return {"status", "HELLO WORLD"}


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

    # Initialize the database
    init_db(JOB_DB)

    # initialize model (optional)
    # init_model()

    # Start the job processing thread - pass JOB_DB
    threading.Thread(target=process_jobs, args=(JOB_DB,), daemon=True).start()
    # threading.Thread(target=process_jobs, daemon=True).start()

    # Run the FastAPI app
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
