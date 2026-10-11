"""30분이 지난 미결제 주문을 정리한다. 서버와 별도 터미널에서 실행한다."""

import argparse
import logging
import time

from pymysql.cursors import DictCursor

if __package__:
    from .database import connect
    from .features.order import cancel_expired_order
else:
    from database import connect
    from features.order import cancel_expired_order


def expire_pending_orders() -> int:
    db = connect()
    count = 0
    try:
        with db.cursor(DictCursor) as cursor:
            cursor.execute(
                """SELECT DISTINCT o.order_id FROM orders o
                   JOIN inventory_reservations r ON r.order_id = o.order_id
                   WHERE o.order_status = 'PENDING_PAYMENT'
                     AND r.reservation_status = 'RESERVED'
                     AND r.expires_at <= CURRENT_TIMESTAMP
                   ORDER BY o.order_id LIMIT 100"""
            )
            order_ids = [row["order_id"] for row in cursor.fetchall()]
        # 조회 트랜잭션을 끝내고 주문별로 잠금·만료 여부를 다시 검사한다.
        db.rollback()
        for order_id in order_ids:
            try:
                changed = cancel_expired_order(db, order_id)
                db.commit()
                count += int(changed)
            except Exception:
                db.rollback()
                logging.exception("미결제 주문 정리 실패: order_id=%s", order_id)
        return count
    finally:
        db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="만료된 결제 대기 주문 정리")
    parser.add_argument("--once", action="store_true", help="한 번 정리하고 종료")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    try:
        while True:
            try:
                logging.info("만료 주문 정리 완료: %s건", expire_pending_orders())
            except Exception:
                logging.exception("만료 주문 정리 작업 실패")
                if args.once:
                    raise
            if args.once:
                break
            time.sleep(30)
    except KeyboardInterrupt:
        pass
