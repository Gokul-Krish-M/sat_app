from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import bcrypt
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.db import get_db
from app.models import Device, Role, User

_bearer = HTTPBearer(auto_error=False)


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def verify_password(password: str, hashed: str | None) -> bool:
    if not hashed:
        return False
    return bcrypt.checkpw(password.encode(), hashed.encode())


def create_token(user_id: int, device_pk: int) -> str:
    s = get_settings()
    payload = {
        "sub": str(user_id),
        "dev": device_pk,
        "exp": datetime.now(UTC) + timedelta(hours=s.jwt_expire_hours),
    }
    return jwt.encode(payload, s.jwt_secret, algorithm="HS256")


@dataclass
class Session_:
    user: User
    device: Device


def current_session(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: Session = Depends(get_db),
) -> Session_:
    unauthorized = HTTPException(status.HTTP_401_UNAUTHORIZED, "Not logged in")
    if creds is None:
        raise unauthorized
    try:
        payload = jwt.decode(creds.credentials, get_settings().jwt_secret, algorithms=["HS256"])
    except jwt.PyJWTError:
        raise unauthorized
    user = db.get(User, int(payload["sub"]))
    device = db.get(Device, payload.get("dev"))
    # Device reset by admin, or reassigned -> token is no longer valid.
    if not user or not can_log_in(user) or not device or device.owner_user_id != user.id:
        raise unauthorized
    return Session_(user=user, device=device)


def can_log_in(user: User) -> bool:
    """Staff marked 'no phone' are blocked from logging in; they use a shared phone."""
    return user.active and (user.has_phone or user.role == Role.ADMIN)


def require_admin(sess: Session_ = Depends(current_session)) -> Session_:
    if sess.user.role != Role.ADMIN:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Admin only")
    return sess
