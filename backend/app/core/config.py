from functools import lru_cache
from pathlib import Path
from zoneinfo import ZoneInfo

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "mysql+pymysql://attendance:change-me@localhost:3306/attendance"
    jwt_secret: str = "dev-secret-change-me"
    jwt_expire_hours: int = 24 * 30
    media_dir: Path = Path("media")
    # face_recognition distance; lower = stricter. 0.6 is the library default.
    face_tolerance: float = 0.5
    timezone: str = "Asia/Kolkata"
    # Ignore a second clock attempt within this many seconds (double taps).
    clock_cooldown_seconds: int = 60

    @property
    def tz(self) -> ZoneInfo:
        return ZoneInfo(self.timezone)


@lru_cache
def get_settings() -> Settings:
    return Settings()
