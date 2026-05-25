import pytest
import sqlite3
import tempfile
import os
from fastapi.testclient import TestClient
from unittest.mock import Mock, patch, MagicMock

# Import the FastAPI app
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "app"))

from app import app
from job_queue import init_db


@pytest.fixture
def test_db():
    """Create a temporary database for testing"""
    # Create temporary database file
    db_fd, db_path = tempfile.mkstemp(suffix=".db")

    # Initialize the database
    init_db(db_path)

    yield db_path

    # Cleanup
    os.close(db_fd)
    os.unlink(db_path)


@pytest.fixture
def client(test_db, monkeypatch):
    """Create a test client with mocked dependencies"""
    # Mock the JOB_DB and APP_URL constants
    monkeypatch.setattr('app.JOB_DB', test_db)
    monkeypatch.setattr('app.APP_URL', 'http://localhost:3000/')

    # Create test client
    return TestClient(app)


def job_payload(image_core_id: int, image_path: str = "/path/to/image.jpg", model: str = "test"):
    return {
        "image_core_id": image_core_id,
        "image_path": image_path,
        "model": model,
        "attempt_id": image_core_id + 1000,
        "callback_token": f"signed-token-{image_core_id}",
    }


class TestHomeEndpoint:
    """Test suite for GET / endpoint"""

    def test_home_returns_hello_world(self, client):
        """Test home endpoint returns correct response"""
        response = client.get("/")

        assert response.status_code == 200
        assert response.json() == {"status": "HELLO WORLD"}


class TestAddJobEndpoint:
    """Test suite for POST /add_job endpoint"""

    @patch('app.status_sender')
    def test_add_job_success(self, mock_status_sender, client, test_db):
        """Test successful job addition"""
        # Setup
        job_data = job_payload(1)

        # Execute
        response = client.post("/add_job", json=job_data)

        # Assert response
        assert response.status_code == 200
        assert response.json() == {"status": "Job added to queue"}

        # Assert status_sender called
        mock_status_sender.assert_called_once_with(
            {"image_core_id": 1, "status": 1, "attempt_id": 1001, "callback_token": "signed-token-1"},
            "http://localhost:3000/"
        )

        # Verify job in database
        conn = sqlite3.connect(test_db)
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM jobs WHERE image_core_id = ?", (1,))
        job = cursor.fetchone()
        conn.close()

        assert job is not None
        assert job[1] == 1  # image_core_id
        assert job[2] == "/path/to/image.jpg"  # image_path
        assert job[3] == "test"  # model

    @patch('app.status_sender')
    def test_add_job_multiple_jobs(self, mock_status_sender, client, test_db):
        """Test adding multiple jobs in sequence"""
        # Add first job
        response1 = client.post("/add_job", json=job_payload(1, "/image1.jpg"))
        assert response1.status_code == 200

        # Add second job
        response2 = client.post("/add_job", json=job_payload(2, "/image2.jpg", "Florence-2-base"))
        assert response2.status_code == 200

        # Verify both jobs in database
        conn = sqlite3.connect(test_db)
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM jobs")
        count = cursor.fetchone()[0]
        conn.close()

        assert count == 2

    @patch('app.status_sender')
    def test_add_job_invalid_model(self, mock_status_sender, client):
        """Test add_job with invalid model name"""
        # Invalid model value (not in available_models list)
        response = client.post("/add_job", json={
            "image_core_id": 1,
            "image_path": "/image.jpg",
            "model": "invalid-model-name",
            "attempt_id": 1001,
            "callback_token": "signed-token-1"
        })

        # FastAPI will return 422 for validation error
        assert response.status_code == 422

    @patch('app.status_sender')
    def test_add_job_requires_attempt_callback_fields(self, mock_status_sender, client):
        response = client.post("/add_job", json={
            "image_core_id": 1,
            "image_path": "/image.jpg",
            "model": "test"
        })

        assert response.status_code == 422
        mock_status_sender.assert_not_called()

    @patch('app.status_sender')
    def test_add_job_batch_from_path_discovery(self, mock_status_sender, client, test_db):
        """Test adding batch of jobs simulating path discovery with multiple images (Scenario A)"""
        # Simulate path with 5 images - all jobs added in quick succession
        batch_jobs = [
            job_payload(i, f"/memes/example_path/image_{i}.jpg")
            for i in range(1, 6)
        ]

        # Add all jobs (simulating ImagePath.list_files_in_directory creating ImageCores)
        responses = []
        for job in batch_jobs:
            response = client.post("/add_job", json=job)
            responses.append(response)

        # Verify all jobs accepted
        for response in responses:
            assert response.status_code == 200, f"Expected 200, got {response.status_code}"

        # Verify all jobs in queue
        conn = sqlite3.connect(test_db)
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM jobs")
        count = cursor.fetchone()[0]

        # Verify correct image paths stored
        cursor.execute("SELECT image_path FROM jobs ORDER BY id")
        paths = [row[0] for row in cursor.fetchall()]
        conn.close()

        assert count == 5, f"Expected 5 jobs in queue, got {count}"
        assert len(paths) == 5, f"Expected 5 paths, got {len(paths)}"

        # Verify paths are correct
        for i, path in enumerate(paths, start=1):
            assert path == f"/memes/example_path/image_{i}.jpg", \
                f"Expected path to match image_{i}.jpg"

    @patch('app.status_sender')
    def test_add_job_batch_with_different_models(self, mock_status_sender, client, test_db):
        """Test batch jobs can use different models (user preference per image)"""
        batch_jobs = [
            job_payload(1, "/image1.jpg"),
            job_payload(2, "/image2.jpg", "Florence-2-base"),
            job_payload(3, "/image3.jpg", "Florence-2-large"),
        ]

        for job in batch_jobs:
            response = client.post("/add_job", json=job)
            assert response.status_code == 200

        # Verify models stored correctly
        conn = sqlite3.connect(test_db)
        cursor = conn.cursor()
        cursor.execute("SELECT model FROM jobs ORDER BY id")
        models = [row[0] for row in cursor.fetchall()]
        conn.close()

        assert models == ["test", "Florence-2-base", "Florence-2-large"]

    @patch('app.status_sender')
    def test_check_queue_shows_batch_size(self, mock_status_sender, client):
        """Test check_queue correctly reports batch job count"""
        # Add batch of 10 jobs
        for i in range(1, 11):
            client.post("/add_job", json=job_payload(i, f"/batch/image_{i}.jpg"))

        # Check queue
        response = client.get("/check_queue")
        assert response.status_code == 200
        assert response.json() == {"queue_length": 10}


class TestCheckQueueEndpoint:
    """Test suite for GET /check_queue endpoint"""

    def test_check_queue_empty(self, client):
        """Test check_queue with empty queue"""
        response = client.get("/check_queue")

        assert response.status_code == 200
        assert response.json() == {"queue_length": 0}

    @patch('app.status_sender')
    def test_check_queue_with_jobs(self, mock_status_sender, client, test_db):
        """Test check_queue with jobs in queue"""
        # Add jobs
        client.post("/add_job", json=job_payload(1, "/image1.jpg"))
        client.post("/add_job", json=job_payload(2, "/image2.jpg"))

        # Check queue
        response = client.get("/check_queue")

        assert response.status_code == 200
        assert response.json() == {"queue_length": 2}


class TestRemoveJobEndpoint:
    """Test suite for DELETE /remove_job/{image_core_id} endpoint"""

    @patch('app.status_sender')
    def test_remove_job_success(self, mock_status_sender, client, test_db):
        """Test successful job removal"""
        # Add job first
        client.post("/add_job", json=job_payload(42, "/image.jpg"))
        mock_status_sender.reset_mock()

        # Remove job
        response = client.delete("/remove_job/42")

        # Assert response
        assert response.status_code == 200
        assert response.json() == {"status": "Job removed from queue"}

        # Assert status_sender called with status=0 (not_started)
        mock_status_sender.assert_called_once_with(
            {"image_core_id": 42, "status": 0, "attempt_id": 1042, "callback_token": "signed-token-42"},
            "http://localhost:3000/"
        )

        # Verify job removed from database
        conn = sqlite3.connect(test_db)
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM jobs WHERE image_core_id = ?", (42,))
        job = cursor.fetchone()
        conn.close()

        assert job is None

    @patch('app.status_sender')
    def test_remove_job_not_found(self, mock_status_sender, client, test_db):
        """Test removing non-existent job"""
        # Try to remove job that doesn't exist
        response = client.delete("/remove_job/999")

        # Should still return success (graceful handling)
        assert response.status_code == 200
        assert response.json() == {"status": "Job removed from queue"}

        mock_status_sender.assert_not_called()

    @patch('app.status_sender')
    def test_remove_job_multiple_times(self, mock_status_sender, client, test_db):
        """Test removing same job multiple times"""
        # Add job
        client.post("/add_job", json=job_payload(10, "/image.jpg"))
        mock_status_sender.reset_mock()

        # Remove job first time (exists)
        response1 = client.delete("/remove_job/10")
        assert response1.status_code == 200
        call_args_1 = mock_status_sender.call_args[0][0]
        assert call_args_1["status"] == 0  # not_started

        mock_status_sender.reset_mock()

        # Remove job second time (doesn't exist)
        response2 = client.delete("/remove_job/10")
        assert response2.status_code == 200
        mock_status_sender.assert_not_called()
