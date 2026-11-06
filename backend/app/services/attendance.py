"""Day boundaries in the company timezone and the per-employee daily summary."""

from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models import AttendanceEvent, EventStatus, EventType, Role, User


def to_local(ts: datetime) -> datetime:
    return ts.replace(tzinfo=UTC).astimezone(get_settings().tz)


def day_bounds_utc(day: date) -> tuple[datetime, datetime]:
    tz = get_settings().tz
    start = datetime.combine(day, time.min, tzinfo=tz).astimezone(UTC).replace(tzinfo=None)
    end = datetime.combine(day + timedelta(days=1), time.min, tzinfo=tz)
    return start, end.astimezone(UTC).replace(tzinfo=None)


def local_today() -> date:
    return datetime.now(get_settings().tz).date()


def accepted_events(db: Session, user_id: int, day: date) -> list[AttendanceEvent]:
    start, end = day_bounds_utc(day)
    return list(
        db.scalars(
            select(AttendanceEvent)
            .where(
                AttendanceEvent.user_id == user_id,
                AttendanceEvent.status == EventStatus.ACCEPTED,
                AttendanceEvent.ts >= start,
                AttendanceEvent.ts < end,
            )
            .order_by(AttendanceEvent.ts)
        )
    )


def next_event_type(db: Session, user_id: int) -> EventType:
    """Alternate IN/OUT within the local day; the first event of a day is IN."""
    events = accepted_events(db, user_id, local_today())
    if events and events[-1].type == EventType.IN:
        return EventType.OUT
    return EventType.IN


@dataclass
class DayRow:
    day: date
    user_id: int
    emp_code: str
    name: str
    has_phone: bool
    in_time: datetime | None  # local time
    out_time: datetime | None
    hours: float | None
    status: str  # present / absent / still_in
    in_device_owner: str
    out_device_owner: str
    in_via_other_phone: bool
    out_via_other_phone: bool


def summarize_day(db: Session, day: date) -> list[DayRow]:
    users = list(
        db.scalars(
            select(User)
            .where(User.active.is_(True), User.role == Role.EMPLOYEE)
            .order_by(User.name)
        )
    )
    start, end = day_bounds_utc(day)
    events = db.scalars(
        select(AttendanceEvent)
        .where(
            AttendanceEvent.status == EventStatus.ACCEPTED,
            AttendanceEvent.ts >= start,
            AttendanceEvent.ts < end,
        )
        .order_by(AttendanceEvent.ts)
    ).all()
    by_user: dict[int, list[AttendanceEvent]] = {}
    for e in events:
        by_user.setdefault(e.user_id, []).append(e)

    rows = []
    for u in users:
        evs = by_user.get(u.id, [])
        first_in = next((e for e in evs if e.type == EventType.IN), None)
        outs = [e for e in evs if e.type == EventType.OUT]
        last_out = outs[-1] if outs else None
        if not first_in:
            status = "absent"
        elif evs[-1].type == EventType.IN:
            status = "still_in"
        else:
            status = "present"
        hours = None
        if first_in and last_out and status == "present":
            hours = round(_worked_seconds(evs) / 3600, 2)
        rows.append(
            DayRow(
                day=day,
                user_id=u.id,
                emp_code=u.emp_code,
                name=u.name,
                has_phone=u.has_phone,
                in_time=to_local(first_in.ts) if first_in else None,
                out_time=to_local(last_out.ts) if last_out and status == "present" else None,
                hours=hours,
                status=status,
                in_device_owner=first_in.device_owner_name if first_in else "",
                out_device_owner=last_out.device_owner_name if last_out else "",
                in_via_other_phone=bool(first_in and first_in.clocked_by_id != u.id),
                out_via_other_phone=bool(last_out and last_out.clocked_by_id != u.id),
            )
        )
    return rows


def _worked_seconds(evs: list[AttendanceEvent]) -> float:
    """Sum of IN->OUT pairs, so a lunch break clocked out/in is not counted."""
    total, opened = 0.0, None
    for e in evs:
        if e.type == EventType.IN:
            opened = e.ts
        elif opened is not None:
            total += (e.ts - opened).total_seconds()
            opened = None
    return total
