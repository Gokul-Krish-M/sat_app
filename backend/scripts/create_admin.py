"""Create an admin account. The employee number (EMP001, ...) is assigned automatically.

Usage:  python -m scripts.create_admin 9876543210 "Admin Name"
(prompts for the password; the admin logs in with the mobile number)
"""

import getpass
import sys

from fastapi import HTTPException

from app.core.security import hash_password
from app.db import SessionLocal
from app.models import Role, User
from app.services.employees import ensure_mobile_free, next_emp_code, normalize_mobile


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    name = sys.argv[2]
    with SessionLocal() as db:
        try:
            mobile = normalize_mobile(sys.argv[1])
            ensure_mobile_free(db, mobile)
        except HTTPException as e:
            sys.exit(e.detail)
        password = getpass.getpass("Password (min 6 chars): ")
        if len(password) < 6:
            sys.exit("Password too short")
        user = User(emp_code=next_emp_code(db), name=name, mobile=mobile, role=Role.ADMIN,
                    password_hash=hash_password(password), has_phone=True)
        db.add(user)
        db.commit()
        print(f"Admin {user.emp_code} ({name}) created. Log in with {mobile}.")


if __name__ == "__main__":
    main()
