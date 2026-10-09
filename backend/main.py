from fastapi import FastAPI

from backend.config import get_settings
from backend.responses import register_error_handlers
from backend.routes import health


def create_app() -> FastAPI:
    app = FastAPI(title='SHOEPICK API', version='0.1.0')
    register_error_handlers(app)
    app.include_router(health.router, prefix=get_settings().api_prefix)
    # 담당별 라우터는 합의된 경로로 이곳에 등록한다.
    return app


app = create_app()
