from datetime import timedelta

from app.db import SessionLocal
from app.models import AttendanceEvent
from tests.conftest import face, login, make_employee


def clock(client, headers, name, **form):
    return client.post("/attendance/clock", files={"image": face(name)},
                       data={"liveness": "blink", **form}, headers=headers)


def age_events(seconds=120):
    """Push existing events back in time so the double-tap cooldown doesn't block."""
    with SessionLocal() as db:
        for e in db.query(AttendanceEvent):
            e.ts -= timedelta(seconds=seconds)
        db.commit()


# ---------- auth & roles ----------


def test_employee_cannot_use_admin_endpoints(client, admin):
    make_employee(client, admin, "9000000001", "Asha")
    emp, _ = login(client, "9000000001", "secret1", "asha-phone")
    assert client.get("/admin/employees", headers=emp).status_code == 403
    assert client.post("/admin/employees/1/enroll", headers=emp,
                       files=[("photos", face("x"))] * 3).status_code == 403
    assert client.get("/admin/reports/attendance.csv?from=2026-01-01&to=2026-01-02",
                      headers=emp).status_code == 403


def test_phone_bound_to_one_employee(client, admin):
    make_employee(client, admin, "9000000001", "Asha")
    make_employee(client, admin, "9000000002", "Bala")
    login(client, "9000000001", "secret1", "asha-phone")
    # Another employee can't use Asha's phone
    r = client.post("/auth/login", json={"mobile": "9000000002", "password": "secret1",
                                         "device_id": "asha-phone"})
    assert r.status_code == 403 and "Asha" in r.json()["detail"]
    # Asha can't register a second phone
    r = client.post("/auth/login", json={"mobile": "9000000001", "password": "secret1",
                                         "device_id": "asha-phone-2"})
    assert r.status_code == 403


def test_device_reset_invalidates_token_and_allows_new_phone(client, admin):
    make_employee(client, admin, "9000000001", "Asha")
    emp, data = login(client, "9000000001", "secret1", "asha-phone")
    assert client.delete(f"/admin/devices/{data['device']['id']}", headers=admin).status_code == 204
    assert client.get("/auth/me", headers=emp).status_code == 401
    login(client, "9000000001", "secret1", "asha-new-phone")


def test_enroll_rejects_photo_without_face(client, admin):
    uid = make_employee(client, admin, "9000000001", "Asha", enroll=False)
    r = client.post(f"/admin/employees/{uid}/enroll", headers=admin,
                    files=[("photos", face("Asha")), ("photos", ("x.jpg", b"blank", "image/jpeg")),
                           ("photos", face("Asha"))])
    assert r.status_code == 422 and "Photo 2" in r.json()["detail"]


# ---------- clock in/out on own phone ----------


def test_clock_in_out_own_phone(client, admin):
    make_employee(client, admin, "9000000001", "Asha")
    emp, _ = login(client, "9000000001", "secret1", "asha-phone")

    r = clock(client, emp, "Asha", lat="12.97", lng="77.59", accuracy_m="10")
    assert r.status_code == 200 and r.json()["accepted"] and r.json()["type"] == "IN"

    # Double tap is blocked
    assert clock(client, emp, "Asha").status_code == 429

    age_events()
    r = clock(client, emp, "Asha")
    assert r.json()["accepted"] and r.json()["type"] == "OUT"

    with SessionLocal() as db:
        first = db.query(AttendanceEvent).order_by(AttendanceEvent.id).first()
        assert (first.lat, first.lng, first.accuracy_m) == (12.97, 77.59, 10.0)


def test_wrong_face_is_rejected_and_logged(client, admin):
    make_employee(client, admin, "9000000001", "Asha")
    emp, _ = login(client, "9000000001", "secret1", "asha-phone")
    r = clock(client, emp, "Someone Else")
    assert r.status_code == 200 and r.json()["accepted"] is False
    emps = client.get("/admin/employees", headers=admin).json()
    asha = next(u for u in emps if u["mobile"] == "9000000001")
    events = client.get(f"/admin/attendance/{asha['id']}/events", headers=admin).json()
    assert events[0]["status"] == "rejected" and events[0]["selfie_url"]
    assert client.get(events[0]["selfie_url"], headers=admin).status_code == 200


def test_no_face_in_photo(client, admin):
    make_employee(client, admin, "9000000001", "Asha")
    emp, _ = login(client, "9000000001", "secret1", "asha-phone")
    r = client.post("/attendance/clock", files={"image": ("x.jpg", b"blank", "image/jpeg")},
                    headers=emp)
    assert r.status_code == 422


# ---------- shared phones for staff without a phone ----------


def test_shared_phone_flow(client, admin):
    make_employee(client, admin, "9000000001", "Asha")
    nophone = make_employee(client, admin, None, "Chitra", has_phone=False)
    owner, data = login(client, "9000000001", "secret1", "asha-phone")

    # Not shared yet -> blocked
    assert client.get("/attendance/shared/staff", headers=owner).status_code == 403
    assert clock(client, owner, "Chitra", for_user_id=nophone).status_code == 403

    client.patch(f"/admin/devices/{data['device']['id']}", json={"is_shared": True}, headers=admin)
    staff = client.get("/attendance/shared/staff", headers=owner).json()
    assert [s["name"] for s in staff] == ["Chitra"]
    assert client.get(f"/users/{nophone}/photo", headers=owner).status_code == 200

    # The phone owner's face can't clock in for Chitra
    r = clock(client, owner, "Asha", for_user_id=nophone)
    assert r.json()["accepted"] is False

    r = clock(client, owner, "Chitra", for_user_id=nophone)
    assert r.json()["accepted"] and r.json()["employee_name"] == "Chitra"

    day = client.get("/admin/attendance", headers=admin).json()
    row = next(x for x in day["rows"] if x["name"] == "Chitra")
    assert row["status"] == "still_in"
    assert row["in_device_owner"] == "Asha" and row["in_via_other_phone"] is True


def test_shared_phone_cannot_clock_in_staff_with_phone(client, admin):
    make_employee(client, admin, "9000000001", "Asha")
    bala = make_employee(client, admin, "9000000002", "Bala")
    owner, data = login(client, "9000000001", "secret1", "asha-phone")
    client.patch(f"/admin/devices/{data['device']['id']}", json={"is_shared": True}, headers=admin)
    r = clock(client, owner, "Bala", for_user_id=bala)
    assert r.status_code == 403


# ---------- admin views & CSV ----------


def test_day_summary_and_csv(client, admin):
    make_employee(client, admin, "9000000001", "Asha")
    make_employee(client, admin, "9000000002", "Bala")
    emp, _ = login(client, "9000000001", "secret1", "asha-phone")
    clock(client, emp, "Asha")
    age_events(3 * 3600)  # IN three hours ago
    clock(client, emp, "Asha")  # OUT now

    day = client.get("/admin/attendance", headers=admin).json()
    assert (day["present"], day["absent"]) == (1, 1)
    asha = next(x for x in day["rows"] if x["name"] == "Asha")
    assert asha["status"] == "present" and 2.9 < asha["hours"] < 3.1

    d = day["date"]
    r = client.get(f"/admin/reports/attendance.csv?from={d}&to={d}", headers=admin)
    assert r.status_code == 200 and "attachment" in r.headers["content-disposition"]
    lines = r.content.decode("utf-8-sig").strip().splitlines()
    assert lines[0] == ("date,emp_code,name,in_time,out_time,hours,status,"
                        "in_device_owner,out_device_owner")
    assert len(lines) == 3
    assert any(line.startswith(f"{d},EMP001,Asha,") and ",present,Asha,Asha" in line for line in lines)
    assert any(",EMP002,Bala,,,,absent" in line for line in lines)


def test_remove_employee_deletes_face_data(client, admin):
    uid = make_employee(client, admin, "9000000001", "Asha")
    assert client.delete(f"/admin/employees/{uid}", headers=admin).status_code == 204
    emps = client.get("/admin/employees", headers=admin).json()
    asha = next(u for u in emps if u["id"] == uid)
    assert asha["active"] is False and asha["enrolled"] is False


# ---------- employee numbers & mobile login ----------


def test_employee_numbers_are_auto_assigned(client, admin):
    make_employee(client, admin, "9000000001", "Asha", enroll=False)
    make_employee(client, admin, None, "Chitra", has_phone=False, enroll=False)
    codes = {u["name"]: u["emp_code"] for u in client.get("/admin/employees", headers=admin).json()}
    assert codes["Asha"] == "EMP001" and codes["Chitra"] == "EMP002"
    # A client-supplied code is ignored
    r = client.post("/admin/employees", headers=admin, json={
        "emp_code": "HACK", "name": "Bala", "mobile": "9000000002", "password": "secret1"})
    assert r.status_code == 201 and r.json()["emp_code"] == "EMP003"


def test_mobile_rules(client, admin):
    def create(**body):
        return client.post("/admin/employees", headers=admin,
                           json={"name": "X", "password": "secret1", **body})

    assert create().status_code == 422  # has phone but no mobile
    assert create(mobile="12345").status_code == 422  # not 10 digits
    r = create(mobile="+91 90000-00001")
    assert r.status_code == 201 and r.json()["mobile"] == "9000000001"
    assert create(mobile="09000000001").status_code == 409  # same number, other format
    # No-phone staff need neither mobile nor password
    r = client.post("/admin/employees", headers=admin, json={"name": "Y", "has_phone": False})
    assert r.status_code == 201 and r.json()["mobile"] is None


def test_login_by_mobile_any_format(client, admin):
    make_employee(client, admin, "9000000001", "Asha", enroll=False)
    login(client, "+91 90000 00001", "secret1", "asha-phone")
    r = client.post("/auth/login", json={"mobile": "9000000001", "password": "wrong",
                                         "device_id": "asha-phone"})
    assert r.status_code == 401


def test_no_phone_blocks_login_without_resetting(client, admin):
    uid = make_employee(client, admin, "9000000001", "Asha")
    emp, data = login(client, "9000000001", "secret1", "asha-phone")

    r = client.patch(f"/admin/employees/{uid}", json={"has_phone": False}, headers=admin)
    assert r.status_code == 200 and r.json()["has_password"] is True
    # Existing session ends and new logins are refused...
    assert client.get("/auth/me", headers=emp).status_code == 401
    r = client.post("/auth/login", json={"mobile": "9000000001", "password": "secret1",
                                         "device_id": "asha-phone"})
    assert r.status_code == 403 and "blocked" in r.json()["detail"]
    # ...but the phone stays registered to her
    assert any(d["owner_user_id"] == uid for d in client.get("/admin/devices", headers=admin).json())

    # Turning it back on restores the old password and the same phone, no reset needed
    r = client.patch(f"/admin/employees/{uid}", json={"has_phone": True}, headers=admin)
    assert r.status_code == 200
    _, again = login(client, "9000000001", "secret1", "asha-phone")
    assert again["device"]["id"] == data["device"]["id"]
