"""Tests against the real dlib engine.

Threshold tuning with real staff photos: put images in FACE_TEST_DIR as
<person>_<n>.jpg (e.g. asha_1.jpg, asha_2.jpg, bala_1.jpg) and run pytest -s.
"""

import io
import itertools
import os
from pathlib import Path

import pytest
from PIL import Image

from app.face import engine


def _jpeg(color=(200, 200, 200)) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (400, 400), color).save(buf, "JPEG")
    return buf.getvalue()


def test_blank_image_has_no_face():
    with pytest.raises(engine.FaceError, match="No face"):
        engine.encode(_jpeg())


def test_garbage_bytes_rejected():
    with pytest.raises(engine.FaceError, match="valid image"):
        engine.encode(b"not an image")


def test_best_distance():
    a, b = [0.0] * 128, [0.1] * 128
    assert engine.best_distance([a, b], b) == 0.0
    assert engine.best_distance([], a) == float("inf")


@pytest.mark.skipif(not os.environ.get("FACE_TEST_DIR"), reason="FACE_TEST_DIR not set")
def test_real_faces_threshold():
    from app.core.config import get_settings

    tol = get_settings().face_tolerance
    files = sorted(Path(os.environ["FACE_TEST_DIR"]).glob("*.jp*g"))
    encs = {f: engine.encode(f.read_bytes()) for f in files}
    person = lambda f: f.stem.rsplit("_", 1)[0]  # noqa: E731
    same, diff = [], []
    for f1, f2 in itertools.combinations(files, 2):
        d = engine.best_distance([encs[f1]], encs[f2])
        (same if person(f1) == person(f2) else diff).append((d, f1.name, f2.name))
    print(f"\nsame-person max distance: {max(same, default=None)}")
    print(f"different-person min distance: {min(diff, default=None)}")
    assert all(d <= tol for d, *_ in same), "same person rejected; raise FACE_TOLERANCE"
    assert all(d > tol for d, *_ in diff), "different people matched; lower FACE_TOLERANCE"
