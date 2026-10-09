from fastapi import APIRouter

from backend.responses import success

router = APIRouter(tags=['health'])


@router.get('/health')
def health():
    """서버 실행 여부만 확인한다. DB/Firebase 연결 성공을 의미하지 않는다."""
    return success({'status': 'ok'})
