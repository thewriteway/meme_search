import time
import sqlite3
import threading
import logging
from image_to_text_generator import image_to_text
from senders import description_sender
from senders import status_sender

# initialize logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")

# lock
lock = threading.Lock()


def proccess_job(input_job_details: dict) -> dict:
    # simulate job processing
    # time.sleep(5)

    # # Specify the file path
    # from pathlib import Path
    # file_path = Path(input_job_details["image_path"])

    # # Get the size of the file in bytes
    # file_size = file_path.stat().st_size
    # logging.info(f"SIZE OF TEST FILE --> {file_size}")
    # description = "this is a test"

    # process image
    description = image_to_text(input_job_details["image_path"], input_job_details["model"])

    # create return payload
    output_job_details = {
        "image_core_id": input_job_details["image_core_id"],
        "description": description,
    }
    return output_job_details


def process_jobs(JOB_DB):
    while True:
        with lock:
            conn = sqlite3.connect(JOB_DB)
            cursor = conn.cursor()

            cursor.execute("SELECT * FROM jobs ORDER BY id LIMIT 1")
            job = cursor.fetchone()

            if job:
                # unpack job
                job_id, image_core_id, image_path, model = job

                # pack up data for processing / status update
                input_job_details = {
                    "image_core_id": image_core_id,
                    "image_path": "/public/memes/" + image_path,
                    "model": model,
                }
                status_job_details = {"image_core_id": image_core_id, "status": 2}

                # send status update (image out of queue and in process)
                status_sender(status_job_details)

                # report that processing has begun
                logging.info("Processing job: %s", input_job_details)

                # process job
                output_job_details = proccess_job(input_job_details)

                # send results to main app
                description_sender(output_job_details)

                # send status update (image processing complete)
                status_job_details["status"] = 3
                status_sender(status_job_details)

                # log completion
                logging.info("Finished processing job: %s", input_job_details)

                # Remove the processed job from the queue
                cursor.execute("DELETE FROM jobs WHERE id = ?", (job_id,))
                conn.commit()
            else:
                # If there are no jobs, wait for a while before checking again
                logging.info("No jobs in queue. Waiting...")
                time.sleep(5)
