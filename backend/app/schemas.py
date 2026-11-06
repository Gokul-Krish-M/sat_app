from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field


class LoginIn(BaseModel):
    mobile: str
    password: str
    device_id: str = Field(min_length=4, max_length=128)
    device_model: str = ""


class DeviceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    # The raw device id / OS string stay server-side; they are never shown to anyone.
    id: int
    is_shared: bool
    owner_user_id: int
    owner_name: str = ""
    owner_emp_code: str = ""
    owner_is_admin: bool = False
    registered_at: datetime


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    emp_code: str
    name: str
    mobile: str | None
    role: str
    has_phone: bool
    active: bool
    enrolled: bool = False
    has_password: bool = False


class LoginOut(BaseModel):
    token: str
    user: UserOut
    device: DeviceOut


class EmployeeCreate(BaseModel):
    # emp_code is not accepted: the server assigns EMP001, EMP002, ...
    name: str = Field(min_length=1, max_length=120)
    # Required when has_phone is true (it is the login ID).
    mobile: str | None = None
    has_phone: bool = True
    # Required when has_phone is true.
    password: str | None = Field(default=None, min_length=6)
    role: str = "employee"


class EmployeeUpdate(BaseModel):
    name: str | None = None
    mobile: str | None = None
    has_phone: bool | None = None
    password: str | None = Field(default=None, min_length=6)
    active: bool | None = None


class DeviceUpdate(BaseModel):
    is_shared: bool


class ClockResult(BaseModel):
    accepted: bool
    type: str | None = None  # IN / OUT when accepted
    ts: datetime | None = None  # local time
    employee_name: str
    message: str


class EventOut(BaseModel):
    id: int
    type: str
    status: str
    ts: datetime  # local time
    distance: float | None
    liveness: str
    device_owner_name: str
    clocked_by_name: str
    selfie_url: str | None


class DayRowOut(BaseModel):
    user_id: int
    emp_code: str
    name: str
    has_phone: bool
    in_time: datetime | None
    out_time: datetime | None
    hours: float | None
    status: str
    in_device_owner: str
    out_device_owner: str
    in_via_other_phone: bool
    out_via_other_phone: bool
    photo_url: str | None


class DaySummaryOut(BaseModel):
    date: date
    present: int
    absent: int
    still_in: int
    rows: list[DayRowOut]
