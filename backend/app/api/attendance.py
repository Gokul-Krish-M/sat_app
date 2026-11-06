from datetime import timedelta

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import user_out
from app.core.config import get_settings
from app.core.security import Session_, current_session
from app.db import get_db
from app.face import engine
from app.models import AttendanceEvent, EventStatus, Role, User, utcnow
from app.schemas import ClockResult, EventOut, UserOut
from app.services import media
from app.services.attendance import (
    accepted_events,
    local_today,
    next_event_type,
    to_local,
)

router = APIRouter(prefix="/attendance", tags=["attendance"])

MAX_IMAGE_BYTES = 8 * 1024 * 1024


@router.get("/shared/staff", response_model=list[UserOut])
def shared_staff(sess: Session_ = Depends(current_session), db: Session = Depends(get_db)):
    """Staff without a phone, listed only on phones the admin marked as shared."""
    if not sess.device.is_shared:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "This phone is not a shared phone")
    users = db.scalars(
        select(User)
        .where(User.active.is_(True), User.has_phone.is_(False), User.role == Role.EMPLOYEE)
        .order_by(User.name)
    )
    return [user_out(u) for u in users]


@router.post("/clock", response_model=ClockResult)
def clock(
    image: UploadFile = File(...),
    for_user_id: int | None = Form(None),
    liveness: str = Form(""),
    lat: float | None = Form(None),
    lng: float | None = Form(None),
    accuracy_m: float | None = Form(None),
    sess: Session_ = Depends(current_session),
    db: Session = Depends(get_db),
) -> ClockResult:
    target = _resolve_target(db, sess, for_user_id)
    known = [e.encoding for e in target.encodings]
    if not known:
        raise HTTPException(status.HTTP_409_CONFLICT, f"{target.name} has no face enrolled yet")

    data = image.file.read(MAX_IMAGE_BYTES + 1)
    if len(data) > MAX_IMAGE_BYTES:
        raise HTTPException(status.HTTP_413_CONTENT_TOO_LARGE, "Image too large")

    s = get_settings()
    last = accepted_events(db, target.id, local_today())
    if last and utcnow() - last[-1].ts < timedelta(seconds=s.clock_cooldown_seconds):
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "Already recorded just now")

    try:
        candidate = engine.encode(data)
    except engine.FaceError as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(e))

    distance = engine.best_distance(known, candidate)
    accepted = distance <= s.face_tolerance
    event = AttendanceEvent(
        user_id=target.id,
        clocked_by_id=sess.user.id,
        device_pk=sess.device.id,
        device_owner_name=sess.device.owner.name,
        type=next_event_type(db, target.id),
        status=EventStatus.ACCEPTED if accepted else EventStatus.REJECTED,
        distance=round(distance, 4),
        liveness=liveness[:16],
        selfie_path=media.save("selfies", target.id, data),
        lat=lat,
        lng=lng,
        accuracy_m=accuracy_m,
    )
    db.add(event)
    db.commit()

    if not accepted:
        return ClockResult(
            accepted=False, employee_name=target.name, message="Face did not match"
        )
    return ClockResult(
        accepted=True,
        type=event.type,
        ts=to_local(event.ts),
        employee_name=target.name,
        message=f"{event.type} recorded",
    )


@router.get("/me/today", response_model=list[EventOut])
def my_today(sess: Session_ = Depends(current_session), db: Session = Depends(get_db)):
    return [
        EventOut(
            id=e.id,
            type=e.type,
            status=e.status,
            ts=to_local(e.ts),
            distance=None,
            liveness=e.liveness,
            device_owner_name=e.device_owner_name,
            clocked_by_name=e.clocked_by.name,
            selfie_url=None,
        )
        for e in accepted_events(db, sess.user.id, local_today())
    ]


def _resolve_target(db: Session, sess: Session_, for_user_id: int | None) -> User:
    if for_user_id is None or for_user_id == sess.user.id:
        if sess.user.role == Role.ADMIN:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Admins do not clock in")
        return sess.user
    if not sess.device.is_shared:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "This phone is not a shared phone")
    target = db.get(User, for_user_id)
    if not target or not target.active:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Employee not found")
    if target.has_phone:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, f"{target.name} must clock in on their own phone"
        )
    return target
