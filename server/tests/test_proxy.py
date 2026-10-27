"""LLM 薄代理路由测试（可选模块）。"""

import json

import httpx
import pytest
from fastapi.testclient import TestClient

from main import create_app
from proxy import RateLimiter
from settings import Settings


def _upstream_echo(request: httpx.Request) -> httpx.Response:
    """假上游：回显收到的 x-api-key，并返回 Anthropic Messages 形状响应。"""
    return httpx.Response(
        200,
        json={
            'content': [{'type': 'text', 'text': '你好'}],
            'stop_reason': 'end_turn',
            'usage': {'input_tokens': 3, 'output_tokens': 2},
            'echo_key': request.headers.get('x-api-key', ''),
        },
    )


@pytest.fixture()
def captured():
    return {}


@pytest.fixture()
def client(captured):
    def handler(request: httpx.Request) -> httpx.Response:
        captured['auth'] = request.headers.get('x-api-key', '')
        captured['version'] = request.headers.get('anthropic-version', '')
        captured['path'] = request.url.path
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
    headers = {'x-api-key': token} if token else {}
    return client.post('/v1/messages',
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
    assert captured['auth'] == 'sk-upstream'
    assert captured['path'].endswith('/v1/messages')
    assert r.json()['content'][0]['text'] == '你好'


def test_anthropic_version_passthrough(client, captured):
    r = client.post('/v1/messages',
                    json={'model': 'm', 'messages': []},
                    headers={'x-api-key': 'app-token-1',
                             'anthropic-version': '2023-06-01'})
    assert r.status_code == 200
    assert captured['version'] == '2023-06-01'


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
        return httpx.Response(
            429,
            json={'type': 'error',
                  'error': {'type': 'rate_limit', 'message': 'rate limited'}},
        )

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
                b'event: content_block_delta\n'
                b'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"hi"}}\n\n',
                b'event: message_stop\n'
                b'data: {"type":"message_stop"}\n\n',
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
        assert b'message_stop' in r.content


def test_open_mode_requires_allow_open():
    st = Settings(db_path=':memory:', upstream_base='https://upstream.test/v1')
    app = create_app(settings=st, transport=httpx.MockTransport(_upstream_echo))
    with pytest.raises(Exception):
        with TestClient(app) as c:  # validate() 在 lifespan 启动时抛错
            _post(c, token=None)
