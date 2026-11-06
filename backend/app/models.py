from datetime import UTC, datetime
from enum import StrEnum

from sqlalchemy import JSON, Boolean, DateTime, Double, Float, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base


def utcnow() -> datetime:
    # Stored as naive UTC; converted to the company timezone for display/reports.
    return datetime.now(UTC).replace(tzinfo=None)


class Role(StrEnum):
    ADMIN = "admin"
    EMPLOYEE = "employee"


class EventType(StrEnum):
    IN = "IN"
    OUT = "OUT"


class EventStatus(StrEnum):
    ACCEPTED = "accepted"
    REJECTED = "rejected"  # face did not match; kept for admin review


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    # Assigned by the server: EMP001, EMP002, ...
    emp_code: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(120))
    # 10-digit mobile; the login ID. Optional for staff without a phone.
    mobile: Mapped[str | None] = mapped_column(String(15), unique=True, nullable=True)
    role: Mapped[str] = mapped_column(String(16), default=Role.EMPLOYEE)
    # NULL for staff without a phone: they never log in, they use a shared phone.
    password_hash: Mapped[str | None] = mapped_column(String(100), nullable=True)
    has_phone: Mapped[bool] = mapped_column(Boolean, default=True)
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    consent_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    encodings: Mapped[list["FaceEncoding"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    devices: Mapped[list["Device"]] = relationship(back_populates="owner")


class Device(Base):
    __tablename__ = "devices"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    device_id: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    owner_user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    model: Mapped[str] = mapped_column(String(120), default="")
    # Shared phones may clock in staff who have no phone of their own.
    is_shared: Mapped[bool] = mapped_column(Boolean, default=False)
    registered_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    owner: Mapped[User] = relationship(back_populates="devices")


class FaceEncoding(Base):
    __tablename__ = "face_encodings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    # 128 floats from face_recognition.face_encodings()
    encoding: Mapped[list[float]] = mapped_column(JSON)
    photo_path: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    user: Mapped[User] = relationship(back_populates="encodings")


class AttendanceEvent(Base):
    __tablename__ = "attendance_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    # Who was logged in on the phone (differs from user_id on a shared phone).
    clocked_by_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    # Kept as a plain id (not FK) so resetting a device never deletes history.
    device_pk: Mapped[int | None] = mapped_column(Integer, nullable=True)
    device_owner_name: Mapped[str] = mapped_column(String(120), default="")
    type: Mapped[str] = mapped_column(String(3))
    status: Mapped[str] = mapped_column(String(16), default=EventStatus.ACCEPTED)
    ts: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)
    distance: Mapped[float | None] = mapped_column(Float, nullable=True)
    liveness: Mapped[str] = mapped_column(String(16), default="")  # "blink" / "smile"
    selfie_path: Mapped[str] = mapped_column(String(255), default="")
    # Phase 2 (geo-fencing): collected from day one.
    lat: Mapped[float | None] = mapped_column(Double, nullable=True)
    lng: Mapped[float | None] = mapped_column(Double, nullable=True)
    accuracy_m: Mapped[float | None] = mapped_column(Float, nullable=True)

    user: Mapped[User] = relationship(foreign_keys=[user_id])
    clocked_by: Mapped[User] = relationship(foreign_keys=[clocked_by_id])
