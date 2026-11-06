# Face Attendance

Flutter app + FastAPI backend. Admin enrolls each employee's face; employees
clock in/out on their own phone with a blink-or-smile check. Staff without a
phone clock in on one of the 2–3 phones the admin marks as **shared**.

```
backend/   FastAPI + MySQL + face_recognition (dlib)
mobile/    Flutter app (Android / iOS)
```

## Backend

### 1. MySQL database (once)
```sql
CREATE DATABASE attendance CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'attendance'@'localhost' IDENTIFIED BY 'choose-a-password';
GRANT ALL PRIVILEGES ON attendance.* TO 'attendance'@'localhost';
```
Run as MySQL root: `sudo mysql`.

### 2. Python environment (no Docker)
```bash
cd backend
python3 -m venv .venv
.venv/bin/pip install dlib-bin==20.0.1.post1 face_recognition_models==0.3.0
.venv/bin/pip install face_recognition==1.3.0 --no-deps   # avoids compiling dlib
.venv/bin/pip install -r requirements.txt -r requirements-dev.txt
```
If `dlib-bin` has no wheel for your Python version, run
`sudo apt install build-essential cmake libopenblas-dev liblapack-dev` and then
`pip install dlib`. That compiles dlib and takes 5–10 minutes.

### 3. Configure, migrate, create the first admin
```bash
cp .env.example .env        # set DATABASE_URL password and a long random JWT_SECRET
.venv/bin/alembic upgrade head
.venv/bin/python -m scripts.create_admin 9876543210 "Your Name"   # mobile = login ID
# Admin created before mobile login? Give it a number:
.venv/bin/python -m scripts.set_mobile ADMIN01 9876543210
```

### 4. Run
```bash
.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
```
API docs: http://localhost:8000/docs

For production, put it behind nginx with HTTPS and run it with
`--workers 2`. Back up the MySQL database and the `media/` folder. The `media/`
folder holds the face and selfie photos and must stay private.

### Tests
```bash
.venv/bin/python -m pytest
# Tune the match threshold with real photos (<person>_<n>.jpg):
FACE_TEST_DIR=/path/to/photos .venv/bin/python -m pytest tests/test_engine.py -s
```

### Settings (`.env`)
| Key | Default | Meaning |
|---|---|---|
| `FACE_TOLERANCE` | `0.5` | Max face distance to accept. Lower = stricter. |
| `TIMEZONE` | `Asia/Kolkata` | Day boundaries for "today" / reports |
| `MEDIA_DIR` | `media` | Where photos are stored |

## Mobile app
```bash
cd mobile
flutter run --dart-define=API_URL=http://<server-ip>:8000
flutter build apk --release --dart-define=API_URL=https://attendance.example.com
```
* Debug builds allow `http://`. Release builds need `https://`.
* iOS: ML Kit needs a real device. Set `platform :ios, '15.5'` in
  `ios/Podfile` after the first `pod install`.

## How it works
* **Employees.** The admin enters a name, a mobile number, whether they have a phone, and a password.
  The employee number (EMP001, EMP002, …) is assigned by the server. Employees log in with
  their mobile number and password. Staff without a phone need no mobile number or password.
* **Login binds the phone.** Each phone generates its own ID on first launch. The first employee
  who logs in on it owns that phone. If they change phones, the admin taps
  **Phones → Reset**.
* **Clock-in.** The app shows a random blink or smile icon, and ML Kit checks for that action on the phone.
  The photo is taken automatically once it does. The server matches the photo against that employee's
  3 enrollment photos only (1:1). The first accepted event of the day is IN, and after that it
  alternates OUT/IN. Rejected attempts are saved with the selfie for the admin to review.
* **Shared phones.** Admin → Phones → switch **Shared** on. That phone then shows
  **Clock in someone else**, which lists only staff marked "no phone". The face is still
  matched against the selected person. The dashboard and CSV show which phone
  was used, for example "via Asha's phone".
* **Admin.** Attendance tab: Today / Yesterday / any date, and ⬇ to export a CSV for a date range.
  Employees tab: add, enroll a face, edit, or remove. Removing someone deletes their face data and
  keeps their attendance history.
* **Location.** Latitude, longitude and accuracy are saved with every clock-in when the phone allows it.
  Phase 2 geo-fencing will check them on the server (MySQL `ST_Distance_Sphere`).
