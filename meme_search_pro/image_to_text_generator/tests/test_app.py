import pytest
from fastapi.testclient import TestClient

from app import app, init_db, check_queue, init_model

client = TestClient(app)

def test_init_db():
    init_db()
    assert check_queue() == {"queue_length": 0}

def test_init_model():
    init_model()
    assert check_queue() == {"queue_length": 0}
