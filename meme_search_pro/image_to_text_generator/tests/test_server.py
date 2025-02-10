import subprocess
import time
import requests

APP_START_CMD = ["python", "app/app.py", "testing"]  # Pass "testing" as an argument
SERVER_URL = "http://127.0.0.1:8000"  # Adjust if your app runs on a different port


def wait_for_server(url, timeout=10):
    """Wait for the server to start by making requests."""
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            response = requests.get(url)
            if response.status_code == 200:
                return True
        except requests.ConnectionError:
            time.sleep(0.5)
    return False


def test_app_starts():
    """Test if the FastAPI app starts up and is accessible."""
    process = subprocess.Popen(APP_START_CMD, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    try:
        assert wait_for_server(SERVER_URL), "Server did not start in time"
    finally:
        process.terminate()  # Stop the process after test
        process.wait()  # Ensure process cleanup
