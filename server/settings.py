"""XNL 后端配置：全部来自环境变量（systemd EnvironmentFile）。"""

from __future__ import annotations

import os
from dataclasses import dataclass, field


@dataclass
class Settings:
    # ---- 账号服务 ----
    db_path: str = '/var/lib/xnl-app/xnl.db'
    token_ttl_days: int = 30

    # ---- LLM 薄代理（可选；不配 UPSTREAM_BASE 就不启用）----
    # 上游 LLM 网关（Anthropic 兼容，如 Claude API；带不带 /v1 都行）
    upstream_base: str = ''
    # 上游真实 API Key。留空 = 把客户端的 Key 原样转发（透传模式）
    upstream_key: str = ''
    # 允许调用代理的 app token 列表
    app_tokens: list[str] = field(default_factory=list)
    # 显式允许无鉴权透传（仅内网/临时测试；不设此项且无 token 时拒绝启用代理）
    allow_open: bool = False
    rate_limit_per_min: int = 10
    daily_req_limit: int = 200
    upstream_timeout_s: float = 90.0
    allowed_models: list[str] = field(default_factory=list)

    @classmethod
    def from_env(cls, env: dict | None = None) -> 'Settings':
        e = env if env is not None else os.environ

        def _list(key: str) -> list[str]:
            return [x.strip() for x in e.get(key, '').split(',') if x.strip()]

        return cls(
            db_path=e.get('DB_PATH', '/var/lib/xnl-app/xnl.db'),
            token_ttl_days=int(e.get('TOKEN_TTL_DAYS', '30')),
            upstream_base=e.get('UPSTREAM_BASE', '').strip().rstrip('/'),
            upstream_key=e.get('UPSTREAM_KEY', '').strip(),
            app_tokens=_list('APP_TOKENS'),
            allow_open=e.get('ALLOW_OPEN', '').strip() == '1',
            rate_limit_per_min=int(e.get('RATE_LIMIT_PER_MIN', '10')),
            daily_req_limit=int(e.get('DAILY_REQ_LIMIT', '200')),
            upstream_timeout_s=float(e.get('UPSTREAM_TIMEOUT_S', '90')),
            allowed_models=_list('ALLOWED_MODELS'),
        )

    @property
    def proxy_enabled(self) -> bool:
        return bool(self.upstream_base)

    def validate(self) -> None:
        if self.token_ttl_days <= 0:
            raise ValueError('TOKEN_TTL_DAYS 必须为正整数')
        if not self.proxy_enabled:
            return
        if not self.app_tokens and not self.allow_open:
            raise ValueError(
                '已配置 UPSTREAM_BASE 但 APP_TOKENS 为空。请生成随机 token 填入，'
                '或临时设置 ALLOW_OPEN=1 开放透传（不建议对公网开放）'
            )
        if self.rate_limit_per_min <= 0 or self.daily_req_limit <= 0:
            raise ValueError('限流参数必须为正整数')

    @property
    def proxy_mode(self) -> str:
        if self.app_tokens:
            return 'token' if self.upstream_key else 'token+passthrough'
        return 'open'
