import os


# system constants
DOCKER_HOST_INTERNAL = os.environ.get("DOCKER_HOST_INTERNAL", "host.docker.internal")
APP_PORT = os.environ.get("APP_PORT", "3000")
APP_URL = f"http://{DOCKER_HOST_INTERNAL}:{APP_PORT}/image_cores/"
JOB_DB = "/app/db/job_queue.db"

# model constants
default_model = "moondream2"
available_models = ["test", default_model]
