"""XNL 后端服务入口：账号服务（始终启用）+ LLM 薄代理（配置了就启用）。

运行：
    uvicorn main:create_app --factory --host 127.0.0.1 --port 8080
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI

from auth import create_auth_router
from db import UserStore
from proxy import create_proxy_router
from settings import Settings

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s',
)
log = logging.getLogger('xnl-app')


def create_app(settings: Settings | None = None,
               transport: httpx.AsyncBaseTransport | None = None,
               user_store: UserStore | None = None) -> FastAPI:
    st = settings or Settings.from_env()
    store = user_store or UserStore(st.db_path)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        try:
            st.validate()
        except ValueError as e:
            log.error('配置错误：%s', e)
            raise
        app.state.client = httpx.AsyncClient(
            base_url=st.upstream_base or 'http://unused',
            timeout=httpx.Timeout(st.upstream_timeout_s),
            transport=transport,
        )
        log.info('账号服务就绪 db=%s', st.db_path)
        if st.proxy_enabled:
            log.info('LLM 薄代理已启用 mode=%s upstream=%s',
                     st.proxy_mode, st.upstream_base)
        yield
        await app.state.client.aclose()

    app = FastAPI(title='XNL 后端', docs_url=None, redoc_url=None, lifespan=lifespan)

    app.include_router(create_auth_router(store, token_ttl_days=st.token_ttl_days))
    if st.proxy_enabled:
        app.include_router(create_proxy_router(st))

    @app.get('/health')
    async def health() -> dict:
        return {
            'ok': True,
            'auth': True,
            'proxy': st.proxy_enabled,
            'proxy_mode': st.proxy_mode if st.proxy_enabled else None,
        }

    return app
