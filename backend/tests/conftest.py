import os
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp(prefix="attendance-test-"))
# Must be set before the app (and its DB engine) is imported.
os.environ["DATABASE_URL"] = f"sqlite:///{_tmp / 'test.db'}"
os.environ["MEDIA_DIR"] = str(_tmp / "media")
os.environ["JWT_SECRET"] = "test-secret-that-is-at-least-32-bytes-long"

import hashlib  # noqa: E402

import numpy as np  # noqa: E402
import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.core.security import hash_password  # noqa: E402
from app.db import Base, SessionLocal, engine  # noqa: E402
from app.face import engine as face_engine  # noqa: E402
from app.main import app  # noqa: E402
from app.models import Role, User  # noqa: E402


def fake_encode(data: bytes) -> list[float]:
    """b'face:<name>' -> a stable vector per person (distance between people ~1.4)."""
    if not data.startswith(b"face:"):
        raise face_engine.FaceError("No face found")
    seed = int(hashlib.sha256(data).hexdigest(), 16) % 2**32
    v = np.random.default_rng(seed).normal(size=128)
    return (v / np.linalg.norm(v)).tolist()


def face(name: str) -> tuple[str, bytes, str]:
    return ("f.jpg", f"face:{name}".encode(), "image/jpeg")


@pytest.fixture(autouse=True)
def _db():
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    with SessionLocal() as db:
        db.add(User(emp_code="ADMIN01", name="Admin", mobile="9999999999", role=Role.ADMIN,
                    password_hash=hash_password("admin123")))
        db.commit()
    yield


@pytest.fixture
def client(monkeypatch):
    # API tests use a fake encoder; tests/test_engine.py exercises real dlib.
    monkeypatch.setattr(face_engine, "encode", fake_encode)
    return TestClient(app)


def login(client, mobile, password, device_id):
    r = client.post("/auth/login", json={"mobile": mobile, "password": password,
                                         "device_id": device_id})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}, r.json()


@pytest.fixture
def admin(client):
    return login(client, "9999999999", "admin123", "admin-phone")[0]


def make_employee(client, admin, mobile, name, has_phone=True, enroll=True):
    """Create via the API (employee number is auto-assigned) and optionally enroll."""
    body = {"name": name, "has_phone": has_phone}
    if mobile:
        body["mobile"] = mobile
    if has_phone:
        body["password"] = "secret1"
    r = client.post("/admin/employees", json=body, headers=admin)
    assert r.status_code == 201, r.text
    uid = r.json()["id"]
    if enroll:
        r = client.post(f"/admin/employees/{uid}/enroll",
                        files=[("photos", face(name)) for _ in range(3)], headers=admin)
        assert r.status_code == 200, r.text
        assert r.json()["enrolled"] is True
    return uid
