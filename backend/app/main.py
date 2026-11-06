from fastapi import FastAPI

from app.api import admin, attendance, auth, reports

app = FastAPI(title="Attendance API", version="1.0.0")

app.include_router(auth.router)
app.include_router(attendance.router)
app.include_router(admin.router)
app.include_router(reports.router)


@app.get("/health", tags=["meta"])
def health() -> dict:
    return {"ok": True}
