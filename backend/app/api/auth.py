from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import device_out, user_out
from app.core.security import (
    Session_,
    can_log_in,
    create_token,
    current_session,
    verify_password,
)
from app.db import get_db
from app.models import Device, Role, User
from app.schemas import LoginIn, LoginOut
from app.services import media
from app.services.employees import normalize_mobile

router = APIRouter(tags=["auth"])


@router.post("/auth/login", response_model=LoginOut)
def login(body: LoginIn, db: Session = Depends(get_db)) -> LoginOut:
    try:
        mobile = normalize_mobile(body.mobile)
    except HTTPException:
        mobile = None
    user = db.scalar(select(User).where(User.mobile == mobile)) if mobile else None
    if not user or not user.active or not verify_password(body.password, user.password_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Wrong mobile number or password")
    if not can_log_in(user):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "Login is blocked for this account (no own phone). Use a shared phone or ask the admin.",
        )

    device = db.scalar(select(Device).where(Device.device_id == body.device_id))
    if device and device.owner_user_id != user.id:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            f"This phone is registered to {device.owner.name}. Ask the admin to reset it.",
        )
    if not device:
        # Employees get exactly one phone; admins may use several (e.g. phone + tablet).
        if user.role != Role.ADMIN and user.devices:
            raise HTTPException(
                status.HTTP_403_FORBIDDEN,
                "You already have a registered phone. Ask the admin to reset it.",
            )
        device = Device(device_id=body.device_id, owner_user_id=user.id, model=body.device_model)
        db.add(device)
        db.commit()
        db.refresh(device)

    return LoginOut(
        token=create_token(user.id, device.id), user=user_out(user), device=device_out(device)
    )


@router.get("/auth/me", response_model=LoginOut)
def me(sess: Session_ = Depends(current_session)) -> LoginOut:
    return LoginOut(
        token="", user=user_out(sess.user), device=device_out(sess.device)
    )


@router.get("/users/{user_id}/photo", response_class=FileResponse)
def user_photo(
    user_id: int, sess: Session_ = Depends(current_session), db: Session = Depends(get_db)
):
    """Enrollment photo. Visible to admins, to the user, and on shared phones for no-phone staff."""
    target = db.get(User, user_id)
    if not target or not target.encodings:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No photo")
    allowed = (
        sess.user.role == Role.ADMIN
        or sess.user.id == target.id
        or (sess.device.is_shared and not target.has_phone)
    )
    if not allowed:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Not allowed")
    path = media.resolve(target.encodings[0].photo_path)
    if not path:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No photo")
    return FileResponse(path, media_type="image/jpeg")
