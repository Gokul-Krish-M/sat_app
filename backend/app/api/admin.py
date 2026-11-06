from datetime import date

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import device_out, photo_url, user_out
from app.core.security import Session_, hash_password, require_admin
from app.db import get_db
from app.face import engine
from app.models import AttendanceEvent, Device, FaceEncoding, Role, User, utcnow
from app.schemas import (
    DayRowOut,
    DaySummaryOut,
    DeviceOut,
    DeviceUpdate,
    EmployeeCreate,
    EmployeeUpdate,
    EventOut,
    UserOut,
)
from app.services import media
from app.services.employees import ensure_mobile_free, next_emp_code, normalize_mobile
from app.services.attendance import day_bounds_utc, local_today, summarize_day, to_local

router = APIRouter(prefix="/admin", tags=["admin"], dependencies=[Depends(require_admin)])

MIN_ENROLL_PHOTOS = 3
MAX_ENROLL_PHOTOS = 5


# ---------- employees ----------


@router.get("/employees", response_model=list[UserOut])
def list_employees(db: Session = Depends(get_db)):
    return [user_out(u) for u in db.scalars(select(User).order_by(User.name))]


@router.post("/employees", response_model=UserOut, status_code=201)
def create_employee(body: EmployeeCreate, db: Session = Depends(get_db)):
    if body.role not in (Role.ADMIN, Role.EMPLOYEE):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Invalid role")
    has_phone = body.has_phone or body.role == Role.ADMIN
    mobile = normalize_mobile(body.mobile)
    if has_phone and not mobile:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, "Mobile number is required for staff with a phone"
        )
    if has_phone and not body.password:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, "Password is required for staff with a phone"
        )
    ensure_mobile_free(db, mobile)
    user = User(
        emp_code=next_emp_code(db),
        name=body.name.strip(),
        mobile=mobile,
        role=body.role,
        has_phone=has_phone,
        password_hash=hash_password(body.password) if has_phone and body.password else None,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user_out(user)


@router.patch("/employees/{user_id}", response_model=UserOut)
def update_employee(user_id: int, body: EmployeeUpdate, db: Session = Depends(get_db)):
    user = _get_user(db, user_id)
    if body.name is not None:
        user.name = body.name.strip()
    if "mobile" in body.model_fields_set:
        mobile = normalize_mobile(body.mobile)
        ensure_mobile_free(db, mobile, user.id)
        user.mobile = mobile
    if body.has_phone is not None and user.role != Role.ADMIN:
        # Turning it off only blocks login (see security.can_log_in); the password and
        # registered phone are kept, so turning it back on restores the old login.
        user.has_phone = body.has_phone
    if body.password:
        user.password_hash = hash_password(body.password)
    if body.active is not None:
        user.active = body.active
    if user.has_phone and not user.mobile:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, "Mobile number is required for staff with a phone"
        )
    if user.has_phone and not user.password_hash:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, "Set a password for staff with a phone"
        )
    db.commit()
    db.refresh(user)
    return user_out(user)


@router.delete("/employees/{user_id}", status_code=204)
def remove_employee(user_id: int, db: Session = Depends(get_db)):
    """Employee left: deactivate, and delete their face data and photos (privacy).
    Attendance history is kept for payroll records."""
    user = _get_user(db, user_id)
    user.active = False
    user.encodings.clear()
    for d in list(user.devices):
        db.delete(d)
    db.commit()
    media.delete_user_files(user.id)
    db.query(AttendanceEvent).filter(AttendanceEvent.user_id == user.id).update(
        {AttendanceEvent.selfie_path: ""}
    )
    db.commit()


@router.post("/employees/{user_id}/enroll", response_model=UserOut)
def enroll(
    user_id: int,
    photos: list[UploadFile] = File(...),
    db: Session = Depends(get_db),
):
    """Replace the employee's face data with 3-5 new photos."""
    user = _get_user(db, user_id)
    if user.role == Role.ADMIN:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Admins are not enrolled")
    if not MIN_ENROLL_PHOTOS <= len(photos) <= MAX_ENROLL_PHOTOS:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            f"Send {MIN_ENROLL_PHOTOS}-{MAX_ENROLL_PHOTOS} photos",
        )
    encoded: list[tuple[bytes, list[float]]] = []
    for i, p in enumerate(photos, start=1):
        data = p.file.read()
        try:
            encoded.append((data, engine.encode(data)))
        except engine.FaceError as e:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, f"Photo {i}: {e}")

    for old in list(user.encodings):
        media.delete_file(old.photo_path)
    user.encodings.clear()
    for data, enc in encoded:
        user.encodings.append(
            FaceEncoding(encoding=enc, photo_path=media.save("faces", user.id, data))
        )
    user.consent_at = utcnow()
    db.commit()
    db.refresh(user)
    return user_out(user)


# ---------- devices ----------


@router.get("/devices", response_model=list[DeviceOut])
def list_devices(db: Session = Depends(get_db)):
    return [device_out(d) for d in db.scalars(select(Device).order_by(Device.registered_at))]


@router.patch("/devices/{device_pk}", response_model=DeviceOut)
def update_device(device_pk: int, body: DeviceUpdate, db: Session = Depends(get_db)):
    device = db.get(Device, device_pk)
    if not device:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Device not found")
    device.is_shared = body.is_shared
    db.commit()
    db.refresh(device)
    return device_out(device)


@router.delete("/devices/{device_pk}", status_code=204)
def reset_device(device_pk: int, sess: Session_ = Depends(require_admin), db: Session = Depends(get_db)):
    """Unregister a phone (employee changed phones). Its owner must log in again."""
    device = db.get(Device, device_pk)
    if not device:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Device not found")
    if device.id == sess.device.id:
        raise HTTPException(status.HTTP_409_CONFLICT, "You cannot reset the phone you are using")
    db.delete(device)
    db.commit()


# ---------- attendance views ----------


@router.get("/attendance", response_model=DaySummaryOut)
def day_summary(day: date | None = None, db: Session = Depends(get_db)):
    """Who came on a given day (default: today). Pass ?day=YYYY-MM-DD."""
    day = day or local_today()
    rows = summarize_day(db, day)
    users = {u.id: u for u in db.scalars(select(User).where(User.id.in_([r.user_id for r in rows])))}
    out = [
        DayRowOut(**{k: getattr(r, k) for k in DayRowOut.model_fields if k != "photo_url"},
                  photo_url=photo_url(users[r.user_id]))
        for r in rows
    ]
    return DaySummaryOut(
        date=day,
        present=sum(r.status != "absent" for r in rows),
        absent=sum(r.status == "absent" for r in rows),
        still_in=sum(r.status == "still_in" for r in rows),
        rows=out,
    )


@router.get("/attendance/{user_id}/events", response_model=list[EventOut])
def user_events(user_id: int, day: date | None = None, db: Session = Depends(get_db)):
    """All attempts (accepted and rejected) for one employee on a day, with selfies."""
    _get_user(db, user_id)
    start, end = day_bounds_utc(day or local_today())
    events = db.scalars(
        select(AttendanceEvent)
        .where(
            AttendanceEvent.user_id == user_id,
            AttendanceEvent.ts >= start,
            AttendanceEvent.ts < end,
        )
        .order_by(AttendanceEvent.ts)
    )
    return [
        EventOut(
            id=e.id,
            type=e.type,
            status=e.status,
            ts=to_local(e.ts),
            distance=e.distance,
            liveness=e.liveness,
            device_owner_name=e.device_owner_name,
            clocked_by_name=e.clocked_by.name,
            selfie_url=f"/admin/events/{e.id}/selfie" if e.selfie_path else None,
        )
        for e in events
    ]


@router.get("/events/{event_id}/selfie", response_class=FileResponse)
def event_selfie(event_id: int, db: Session = Depends(get_db)):
    event = db.get(AttendanceEvent, event_id)
    path = media.resolve(event.selfie_path) if event and event.selfie_path else None
    if not path:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No selfie")
    return FileResponse(path, media_type="image/jpeg")


def _get_user(db: Session, user_id: int) -> User:
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Employee not found")
    return user
