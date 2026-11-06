"""Face encoding / matching using the `face_recognition` (dlib) library."""

import io

import numpy as np
from PIL import Image, ImageOps


class FaceError(ValueError):
    """Image is unusable: no face, or more than one face."""


def load_image(data: bytes, max_side: int = 1024) -> np.ndarray:
    try:
        img = Image.open(io.BytesIO(data))
        img = ImageOps.exif_transpose(img)  # phone photos are often rotated via EXIF
    except Exception as e:  # noqa: BLE001
        raise FaceError("Not a valid image") from e
    img = img.convert("RGB")
    img.thumbnail((max_side, max_side))  # speeds up detection a lot
    return np.asarray(img)


def encode(data: bytes) -> list[float]:
    """Return the 128-d encoding of the single face in the image."""
    import face_recognition  # imported lazily: loading dlib models takes ~1s

    image = load_image(data)
    boxes = face_recognition.face_locations(image, number_of_times_to_upsample=1, model="hog")
    if not boxes:
        raise FaceError("No face found")
    if len(boxes) > 1:
        raise FaceError("More than one face found")
    enc = face_recognition.face_encodings(image, known_face_locations=boxes, num_jitters=1)
    return enc[0].tolist()


def best_distance(known: list[list[float]], candidate: list[float]) -> float:
    """Smallest Euclidean distance between the candidate and the enrolled encodings."""
    if not known:
        return float("inf")
    k = np.asarray(known, dtype=np.float64)
    c = np.asarray(candidate, dtype=np.float64)
    return float(np.min(np.linalg.norm(k - c, axis=1)))
