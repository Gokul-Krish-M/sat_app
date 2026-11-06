"""Private photo storage on local disk. Paths stored in DB are relative to MEDIA_DIR."""

import shutil
import uuid
from datetime import datetime
from pathlib import Path

from app.core.config import get_settings


def _root() -> Path:
    return get_settings().media_dir.resolve()


def save(kind: str, user_id: int, data: bytes) -> str:
    rel = Path(kind) / str(user_id) / f"{datetime.now():%Y%m%d-%H%M%S}-{uuid.uuid4().hex[:8]}.jpg"
    path = _root() / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return rel.as_posix()


def resolve(rel: str) -> Path | None:
    """Absolute path for a stored file, or None if outside MEDIA_DIR / missing."""
    root = _root()
    path = (root / rel).resolve()
    if not path.is_relative_to(root) or not path.is_file():
        return None
    return path


def delete_user_files(user_id: int) -> None:
    for kind in ("faces", "selfies"):
        shutil.rmtree(_root() / kind / str(user_id), ignore_errors=True)


def delete_file(rel: str) -> None:
    p = resolve(rel)
    if p:
        p.unlink(missing_ok=True)
