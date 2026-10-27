"""账号接口：注册 / 登录 / 登出 / 个人信息。

安全要点：
- 密码 scrypt 哈希存储，验证用常数时间比较
- 登录失败按 IP+用户名计数，5 次锁 15 分钟（防爆破）
- 用户名不存在与密码错误返回同一文案（防枚举），并抹平时间差
- token 只存 SHA-256 哈希，30 天过期，登出即删
- 注册按 IP 限流（10 次/小时），防开放注册被滥用
"""

from __future__ import annotations

import re
import time
from collections import defaultdict

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel, Field

from db import User, UserStore

USERNAME_RE = re.compile(r'^[\w-]{2,24}$', re.UNICODE)
MAX_FAILS = 5
LOCK_SECONDS = 15 * 60


class Credentials(BaseModel):
    username: str = Field(min_length=2, max_length=24)
    password: str = Field(min_length=8, max_length=128)


class LoginLimiter:
    """按 key 记事件时间，窗口内超限返回锁定剩余秒数。进程内存实现。"""

    def __init__(self, max_fails=MAX_FAILS, lock_seconds=LOCK_SECONDS, clock=time.time):
        self.max_fails = max_fails
        self.lock_seconds = lock_seconds
        self._clock = clock
        self._events: dict[str, list[float]] = defaultdict(list)

    def check_locked(self, key: str) -> int | None:
        """返回剩余锁定秒数；未锁定返回 None。"""
        now = self._clock()
        events = [t for t in self._events[key] if now - t < self.lock_seconds]
        self._events[key] = events
        if len(events) >= self.max_fails:
            return int(self.lock_seconds - (now - events[0]))
        return None

    def record(self, key: str) -> None:
        self._events[key].append(self._clock())

    def clear(self, key: str) -> None:
        self._events.pop(key, None)


def create_auth_router(store: UserStore,
                       token_ttl_days: int = 30,
                       login_limiter: LoginLimiter | None = None,
                       register_limiter: LoginLimiter | None = None) -> APIRouter:
    router = APIRouter(prefix='/api')
    login_limiter = login_limiter or LoginLimiter()
    register_limiter = register_limiter or LoginLimiter(max_fails=10, lock_seconds=3600)

    def _ip(request: Request) -> str:
        return request.client.host if request.client else '?'

    def _bearer(authorization: str) -> str:
        return authorization[7:].strip() if authorization.lower().startswith('bearer ') else ''

    def current_user(authorization: str = Header(default='')) -> User:
        user = store.user_for_token(_bearer(authorization))
        if user is None:
            raise HTTPException(401, '登录已过期或无效，请重新登录')
        return user

    @router.post('/register', status_code=201)
    def register(cred: Credentials, request: Request):
        ip = _ip(request)
        locked = register_limiter.check_locked(ip)
        if locked is not None:
            raise HTTPException(429, f'注册过于频繁，请 {locked} 秒后再试')
        register_limiter.record(ip)
        if not USERNAME_RE.match(cred.username):
            raise HTTPException(400, '用户名需为 2-24 位字母、数字、下划线或连字符')
        user = store.create_user(cred.username, cred.password)
        if user is None:
            raise HTTPException(409, '用户名已存在')
        token = store.issue_token(user.id, token_ttl_days)
        return {'token': token, 'user': user.public()}

    @router.post('/login')
    def login(cred: Credentials, request: Request):
        key = f'{_ip(request)}|{cred.username}'
        locked = login_limiter.check_locked(key)
        if locked is not None:
            raise HTTPException(429, f'尝试过于频繁，请 {locked} 秒后再试')
        user = store.verify_user(cred.username, cred.password)
        if user is None:
            login_limiter.record(key)
            raise HTTPException(401, '用户名或密码错误')
        login_limiter.clear(key)
        token = store.issue_token(user.id, token_ttl_days)
        return {'token': token, 'user': user.public()}

    @router.post('/logout')
    def logout(authorization: str = Header(default='')):
        token = _bearer(authorization)
        if token:
            store.revoke_token(token)
        return {'ok': True}

    @router.get('/me')
    def me(user: User = Depends(current_user)):
        return {'user': user.public()}

    return router
