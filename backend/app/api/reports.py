import csv
import io
from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.core.security import require_admin
from app.db import get_db
from app.services.attendance import summarize_day

router = APIRouter(prefix="/admin/reports", tags=["reports"], dependencies=[Depends(require_admin)])

MAX_DAYS = 366
CSV_COLUMNS = [
    "date", "emp_code", "name", "in_time", "out_time", "hours", "status",
    "in_device_owner", "out_device_owner",
]


@router.get("/attendance.csv")
def attendance_csv(
    from_: date = Query(alias="from"),
    to: date = Query(),
    db: Session = Depends(get_db),
):
    if to < from_:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "'to' is before 'from'")
    if (to - from_).days >= MAX_DAYS:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, f"Max {MAX_DAYS} days")

    buf = io.StringIO()
    buf.write("﻿")  # BOM so Excel opens UTF-8 names correctly
    w = csv.writer(buf)
    w.writerow(CSV_COLUMNS)
    day = from_
    while day <= to:
        for r in summarize_day(db, day):
            w.writerow([
                r.day.isoformat(),
                r.emp_code,
                r.name,
                r.in_time.strftime("%H:%M") if r.in_time else "",
                r.out_time.strftime("%H:%M") if r.out_time else "",
                f"{r.hours:.2f}" if r.hours is not None else "",
                r.status,
                r.in_device_owner,
                r.out_device_owner,
            ])
        day += timedelta(days=1)

    filename = f"attendance_{from_.isoformat()}_to_{to.isoformat()}.csv"
    return StreamingResponse(
        iter([buf.getvalue()]),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
