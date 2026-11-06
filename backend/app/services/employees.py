"""Employee numbering and mobile-number rules."""

import re

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import User

EMP_PREFIX = "EMP"


def next_emp_code(db: Session) -> str:
    """EMP001, EMP002, ... (keeps counting past EMP999). Codes are never reused."""
    codes = db.scalars(select(User.emp_code).where(User.emp_code.like(f"{EMP_PREFIX}%")))
    nums = [int(c[len(EMP_PREFIX):]) for c in codes if c[len(EMP_PREFIX):].isdigit()]
    return f"{EMP_PREFIX}{max(nums, default=0) + 1:03d}"


def normalize_mobile(raw: str | None) -> str | None:
    """'+91 98765-43210' / '098765 43210' / '9876543210' -> '9876543210'."""
    if raw is None or not raw.strip():
        return None
    digits = re.sub(r"\D", "", raw)
    if len(digits) == 12 and digits.startswith("91"):
        digits = digits[2:]
    elif len(digits) == 11 and digits.startswith("0"):
        digits = digits[1:]
    if len(digits) != 10:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, "Mobile number must have 10 digits"
        )
    return digits


def ensure_mobile_free(db: Session, mobile: str | None, user_id: int | None = None) -> None:
    if mobile is None:
        return
    other = db.scalar(select(User).where(User.mobile == mobile))
    if other and other.id != user_id:
        raise HTTPException(
            status.HTTP_409_CONFLICT, f"Mobile number already used by {other.name}"
        )
