from datetime import UTC

from app.models import Device, Role, User
from app.schemas import DeviceOut, UserOut


def user_out(u: User) -> UserOut:
    out = UserOut.model_validate(u)
    out.enrolled = bool(u.encodings)
    out.has_password = bool(u.password_hash)
    return out


def device_out(d: Device) -> DeviceOut:
    out = DeviceOut.model_validate(d)
    out.owner_name = d.owner.name if d.owner else ""
    out.owner_emp_code = d.owner.emp_code if d.owner else ""
    out.owner_is_admin = bool(d.owner and d.owner.role == Role.ADMIN)
    out.registered_at = d.registered_at.replace(tzinfo=UTC)  # stored as naive UTC
    return out


def photo_url(u: User) -> str | None:
    return f"/users/{u.id}/photo" if u.encodings else None
