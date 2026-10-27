"""LLM 薄代理路由测试（可选模块）。"""

import json

import httpx
import pytest
from fastapi.testclient import TestClient

from main import create_app
from proxy import RateLimiter
from settings import Settings


def _upstream_echo(request: httpx.Request) -> httpx.Response:
    """假上游：回显收到的 Authorization，并返回 OpenAI 形状响应。"""
    return httpx.Response(
        200,
        json={
            'choices': [{
                'finish_reason': 'stop',
                'message': {'role': 'assistant', 'content': '你好'},
            }],
            'usage': {'prompt_tokens': 3, 'completion_tokens': 2},
            'echo_auth': request.headers.get('authorization', ''),
        },
    )


@pytest.fixture()
def captured():
    return {}


@pytest.fixture()
def client(captured):
    def handler(request: httpx.Request) -> httpx.Response:
        captured['auth'] = request.headers.get('authorization', '')
        captured['body'] = request.content
        return _upstream_echo(request)

    st = Settings(
        db_path=':memory:',
        upstream_base='https://upstream.test/v1',
        upstream_key='sk-upstream',
        app_tokens=['app-token-1'],
    )
    app = create_app(
        settings=st,
        transport=httpx.MockTransport(handler),
    )
    with TestClient(app) as c:
        yield c


def _post(client, token='app-token-1', **body):
    headers = {'Authorization': f'Bearer {token}'} if token else {}
    return client.post('/v1/chat/completions',
                       json={'model': 'm', 'messages': [], **body},
                       headers=headers)


def test_health_shows_proxy(client):
    body = client.get('/health').json()
    assert body['proxy'] is True and body['proxy_mode'] == 'token'


def test_auth_required(client):
    r = _post(client, token=None)
    assert r.status_code == 401
    r = _post(client, token='wrong-token')
    assert r.status_code == 401


def test_upstream_key_replaces_client_token(client, captured):
    r = _post(client, token='app-token-1')
    assert r.status_code == 200
    assert captured['auth'] == 'Bearer sk-upstream'
    assert r.json()['choices'][0]['message']['content'] == '你好'


def test_body_forwarded_verbatim(client, captured):
    _post(client, messages=[{'role': 'user', 'content': 'hi'}])
    assert json.loads(captured['body'])['messages'][0]['content'] == 'hi'


def test_rate_limit_and_daily_quota():
    clock = {'now': 1000.0}
    limiter = RateLimiter(per_min=2, per_day=3, clock=lambda: clock['now'])
    assert limiter.check('a') is None
    assert limiter.check('a') is None
    assert limiter.check('a') == 'rate_limit'  # 分钟窗口满
    clock['now'] = 1061.0  # 滑窗过去
    assert limiter.check('a') is None  # 第 3 次放行，日计数满 3
    assert limiter.check('a') == 'daily_quota'  # 日额度熔断
    assert limiter.check('b') is None  # 互不影响


def test_model_not_allowed():
    st = Settings(
        db_path=':memory:',
        upstream_base='https://upstream.test/v1',
        upstream_key='sk-upstream',
        app_tokens=['app-token-1'],
        allowed_models=['good-model'],
    )
    app = create_app(settings=st, transport=httpx.MockTransport(_upstream_echo))
    with TestClient(app) as c:
        r = _post(c, model='bad-model')
        assert r.status_code == 403
        r = _post(c, model='good-model')
        assert r.status_code == 200


def test_upstream_error_passthrough():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(429, json={'error': {'message': 'rate limited'}})

    st = Settings(
        db_path=':memory:',
        upstream_base='https://upstream.test/v1',
        upstream_key='sk-upstream',
        app_tokens=['app-token-1'],
    )
    app = create_app(settings=st, transport=httpx.MockTransport(handler))
    with TestClient(app) as c:
        r = _post(c)
        assert r.status_code == 429
        assert r.json()['error']['message'] == 'rate limited'


def test_stream_passthrough():
    class _AsyncChunks(httpx.AsyncByteStream):
        def __init__(self, chunks):
            self._chunks = chunks

        async def __aiter__(self):
            for chunk in self._chunks:
                yield chunk

        async def aclose(self):
            pass

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={'content-type': 'text/event-stream'},
            stream=_AsyncChunks([
                b'data: {"choices":[{"delta":{"content":"hi"}}]}\n\n',
                b'data: [DONE]\n\n',
            ]),
        )

    st = Settings(
        db_path=':memory:',
        upstream_base='https://upstream.test/v1',
        upstream_key='sk-upstream',
        app_tokens=['app-token-1'],
    )
    app = create_app(settings=st, transport=httpx.MockTransport(handler))
    with TestClient(app) as c:
        r = _post(c, stream=True)
        assert r.status_code == 200
        assert b'[DONE]' in r.content


def test_open_mode_requires_allow_open():
    st = Settings(db_path=':memory:', upstream_base='https://upstream.test/v1')
    app = create_app(settings=st, transport=httpx.MockTransport(_upstream_echo))
    with pytest.raises(Exception):
        with TestClient(app) as c:  # validate() 在 lifespan 启动时抛错
            _post(c, token=None)
