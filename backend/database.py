import os
from pathlib import Path

import pymysql
from dotenv import load_dotenv

load_dotenv(Path(__file__).with_name(".env"))


def connect():
    """로컬 환경 설정으로 MySQL 연결을 생성한다."""
    return pymysql.connect(
        host=os.getenv("DB_HOST", "127.0.0.1"),
        user=os.getenv("DB_USER", "root"),
        password=os.environ["DB_PASSWORD"],
        database=os.getenv("DB_NAME", "shupick_v2"),
        charset=os.getenv("DB_CHARSET", "utf8"),
        port=int(os.getenv("DB_PORT", "3306")),
    )
