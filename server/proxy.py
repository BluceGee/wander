"""LLM 薄代理路由（可选模块）：APP → 本服务 → LLM 网关（Anthropic 兼容）。

职责（对应调研里的「薄代理」）：
- 鉴权：客户端带 app token（x-api-key），代理替换为上游真实 Key（Key 不进手机）
- 限流：每 token 每分钟 N 次 + 每天 M 次（日预算熔断），超限 429
- 透传：请求/响应原样转发，支持 stream=true 的 SSE
- 日志：只记元信息（状态码/耗时/字节数），绝不记正文与密钥
"""

from __future__ import annotations

import hashlib
import json
import logging
import time
from collections import deque

import httpx
from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse, Response, StreamingResponse

from settings import Settings

log = logging.getLogger('xnl-proxy')


def _err(status: int, message: str, err_type: str, **extra) -> JSONResponse:
    """Anthropic 错误形状：{"type": "error", "error": {...}}。"""
    error = {'type': err_type, 'message': message}
    error.update(extra)
    return JSONResponse({'type': 'error', 'error': error}, status_code=status)


def _messages_path(base: str) -> str:
    """上游 Messages 端点路径：upstream_base 带不带 /v1 都兼容。"""
    return '/messages' if base.rstrip('/').endswith('/v1') else '/v1/messages'


class RateLimiter:
    """每身份的分钟滑窗 + 日计数。进程内存实现（单进程足够）。"""

    def __init__(self, per_min: int, per_day: int, clock=time.time):
        self.per_min = per_min
        self.per_day = per_day
        self._clock = clock
        self._windows: dict[str, deque] = {}
        self._days: dict[str, tuple[str, int]] = {}

    def check(self, ident: str) -> str | None:
        now = self._clock()
        win = self._windows.setdefault(ident, deque())
        while win and now - win[0] > 60:
            win.popleft()
        if len(win) >= self.per_min:
            return 'rate_limit'
        day = time.strftime('%Y-%m-%d', time.localtime(now))
        last_day, count = self._days.get(ident, ('', 0))
        if last_day != day:
            count = 0
        if count >= self.per_day:
            return 'daily_quota'
        win.append(now)
        self._days[ident] = (day, count + 1)
        return None


def _token_ident(token: str) -> str:
    return 't:' + hashlib.sha256(token.encode()).hexdigest()[:12]


def create_proxy_router(st: Settings, limiter: RateLimiter | None = None) -> APIRouter:
    router = APIRouter()
    limiter = limiter or RateLimiter(st.rate_limit_per_min, st.daily_req_limit)

    @router.post('/v1/messages')
    async def messages(request: Request):
        t0 = time.time()
        client_ip = request.client.host if request.client else '?'

        # ---- 鉴权（Anthropic 风格 x-api-key）----
        token = request.headers.get('x-api-key', '').strip()
        if st.app_tokens:
            if token not in st.app_tokens:
                log.info('auth_fail ip=%s', client_ip)
                return _err(401, 'app token 缺失或无效', 'auth_error')
            ident = _token_ident(token)
        else:
            ident = 'ip:' + client_ip

        # ---- 限流 / 日预算 ----
        reason = limiter.check(ident)
        if reason is not None:
            log.info('limited ident=%s reason=%s', ident, reason)
            msg = ('请求过于频繁，稍后再试' if reason == 'rate_limit'
                   else '今日额度已用完，明天恢复')
            return _err(429, msg, reason, retry_after=60)

        # ---- 解析请求体（只用于判流式 / 模型限制，正文原样转发）----
        body = await request.body()
        stream = False
        model = None
        try:
            parsed = json.loads(body)
            stream = bool(parsed.get('stream'))
            model = parsed.get('model')
        except (ValueError, AttributeError):
            parsed = None
        if st.allowed_models and model not in st.allowed_models:
            return _err(403, f'模型 {model!r} 不在允许列表内', 'model_not_allowed')

        # ---- 转发上游（Anthropic Messages 协议）----
        upstream_auth = st.upstream_key or token
        headers = {
            'x-api-key': upstream_auth,
            'Content-Type': 'application/json',
        }
        for h in ('anthropic-version', 'anthropic-beta'):
            if h in request.headers:
                headers[h] = request.headers[h]
        client: httpx.AsyncClient = request.app.state.client
        try:
            upstream = await client.send(
                client.build_request(
                    'POST', _messages_path(st.upstream_base),
                    content=body, headers=headers,
                ),
                stream=True,
            )
        except httpx.HTTPError as e:
            log.warning('upstream_error ident=%s err=%s', ident, type(e).__name__)
            return _err(502, f'上游接口不可达：{type(e).__name__}', 'upstream_unreachable')

        duration_ms = int((time.time() - t0) * 1000)

        if stream:
            async def gen():
                try:
                    # aiter_bytes：解压后透传（不转发 content-encoding 头，避免错配）
                    async for chunk in upstream.aiter_bytes():
                        yield chunk
                finally:
                    await upstream.aclose()

            log.info('done ident=%s status=%s stream=1 %dms',
                     ident, upstream.status_code, duration_ms)
            return StreamingResponse(
                gen(),
                status_code=upstream.status_code,
                media_type=upstream.headers.get('content-type', 'text/event-stream'),
            )

        content = await upstream.aread()
        log.info('done ident=%s status=%s %dms bytes=%d',
                 ident, upstream.status_code, duration_ms, len(content))
        return Response(
            content,
            status_code=upstream.status_code,
            media_type=upstream.headers.get('content-type', 'application/json'),
        )

    return router
