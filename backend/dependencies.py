"""기능별 API에서 공유하는 DB 연결 의존성.

직원 인증·권한 의존성은 담당 B의 공통 기능에 맞춰 연결한다.
"""

from collections.abc import Iterator

from pymysql.connections import Connection

if __package__:
    from .database import connect
else:
    from database import connect


def get_db() -> Iterator[Connection]:
    """요청마다 연결을 열고 종료한다. 성공 시 commit은 업무 함수가 담당한다.

입고·재고·이력 등 함께 저장할 데이터는 같은 연결을 사용하며,
최상위 업무 함수가 전체 처리에 성공한 뒤 한 번만 commit한다.
"""
    connection = connect()
    try:
        yield connection
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()
