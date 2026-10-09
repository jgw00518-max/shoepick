from contextlib import contextmanager

import pymysql

from backend.config import get_settings


def get_db():
    """요청마다 연결을 제공하고 반드시 닫는다. 저장은 명시적 트랜잭션으로 수행한다."""
    settings = get_settings()
    if not settings.db_host or not settings.db_user:
        raise RuntimeError('DB configuration is missing')
    connection = pymysql.connect(
        host=settings.db_host, port=settings.db_port, user=settings.db_user,
        password=settings.db_password, database=settings.db_name,
        charset='utf8mb4', cursorclass=pymysql.cursors.DictCursor,
        autocommit=False, connect_timeout=5, read_timeout=10, write_timeout=10,
    )
    try:
        yield connection
    finally:
        try:
            connection.rollback()
        finally:
            connection.close()


@contextmanager
def transaction(connection):
    """업무 전체에 한 번 사용하며 중첩하지 않는다. 실패하면 함께 되돌린다."""
    try:
        yield connection
        connection.commit()
    except Exception:
        connection.rollback()
        raise
