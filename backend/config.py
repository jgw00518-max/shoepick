from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """실행 위치와 관계없이 백엔드의 환경설정을 읽는다."""

    model_config = SettingsConfigDict(
        env_file=Path(__file__).parent / '.env', extra='ignore'
    )
    api_prefix: str = '/api/v1'
    # 공용 DB 주소는 .env에서 지정하여 잘못된 로컬 DB 접속을 방지한다.
    db_host: str = ''
    db_port: int = 3306
    db_name: str = 'shupick_v2'
    db_user: str = ''
    db_password: str = ''
    firebase_project_id: str = ''
    firebase_credentials_path: str = ''


@lru_cache
def get_settings() -> Settings:
    return Settings()
