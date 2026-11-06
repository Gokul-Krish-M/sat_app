"""Set (or change) a user's mobile number, e.g. for an admin created before mobile login.

Usage:  python -m scripts.set_mobile ADMIN01 9876543210
"""

import sys

from fastapi import HTTPException
from sqlalchemy import select

from app.db import SessionLocal
from app.models import User
from app.services.employees import ensure_mobile_free, normalize_mobile


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    emp_code = sys.argv[1]
    with SessionLocal() as db:
        user = db.scalar(select(User).where(User.emp_code == emp_code))
        if not user:
            sys.exit(f"No user with employee number {emp_code}")
        try:
            mobile = normalize_mobile(sys.argv[2])
            ensure_mobile_free(db, mobile, user.id)
        except HTTPException as e:
            sys.exit(e.detail)
        user.mobile = mobile
        db.commit()
        print(f"{user.name} ({emp_code}) now logs in with {mobile}.")


if __name__ == "__main__":
    main()
