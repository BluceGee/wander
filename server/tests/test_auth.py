"""账号接口测试。"""

import pytest
from fastapi.testclient import TestClient

from auth import LoginLimiter
from db import UserStore
from main import create_app
from settings import Settings


@pytest.fixture()
def client():
    st = Settings(db_path=':memory:')
    app = create_app(
        settings=st,
        user_store=UserStore(':memory:'),
    )
    with TestClient(app) as c:
        yield c


def _register(client, username='alice', password='password123'):
    return client.post('/api/register',
                       json={'username': username, 'password': password})


def test_register_login_me_logout(client):
    r = _register(client)
    assert r.status_code == 201
    token = r.json()['token']
    assert r.json()['user']['username'] == 'alice'

    r = client.get('/api/me', headers={'Authorization': f'Bearer {token}'})
    assert r.status_code == 200
    assert r.json()['user']['username'] == 'alice'

    r = client.post('/api/logout', headers={'Authorization': f'Bearer {token}'})
    assert r.status_code == 200

    r = client.get('/api/me', headers={'Authorization': f'Bearer {token}'})
    assert r.status_code == 401


def test_register_duplicate_and_validation(client):
    assert _register(client).status_code == 201
    assert _register(client).status_code == 409

    r = client.post('/api/register', json={'username': 'x', 'password': 'password123'})
    assert r.status_code == 422  # 用户名太短（pydantic 校验）

    r = client.post('/api/register', json={'username': 'bad name!', 'password': 'password123'})
    assert r.status_code == 400  # 非法字符

    r = client.post('/api/register', json={'username': 'bob', 'password': 'short'})
    assert r.status_code == 422  # 密码太短


def test_login_wrong_password_and_no_user(client):
    _register(client)
    r = client.post('/api/login', json={'username': 'alice', 'password': 'wrong-pass'})
    assert r.status_code == 401
    # 用户不存在与密码错误同文案（防枚举）
    r = client.post('/api/login', json={'username': 'nobody', 'password': 'wrong-pass'})
    assert r.status_code == 401
    assert r.json() == client.post(
        '/api/login', json={'username': 'alice', 'password': 'wrong-pass'}).json()


def test_login_lockout(client):
    _register(client, username='carol')
    for _ in range(5):
        r = client.post('/api/login', json={'username': 'carol', 'password': 'wrong-pass'})
        assert r.status_code == 401
    r = client.post('/api/login', json={'username': 'carol', 'password': 'password123'})
    assert r.status_code == 429
    assert '秒后再试' in r.json()['detail']


def test_me_requires_token(client):
    assert client.get('/api/me').status_code == 401
    assert client.get('/api/me', headers={'Authorization': 'Bearer nope'}).status_code == 401


def test_token_ttl_expiry():
    store = UserStore(':memory:')
    user = store.create_user('dave', 'password123')
    token = store.issue_token(user.id, ttl_days=0)  # 立即过期
    assert store.user_for_token(token) is None


def test_register_rate_limit():
    # 注册限流器单独验证：10 次/小时
    limiter = LoginLimiter(max_fails=3, lock_seconds=3600, clock=lambda: 1000.0)
    assert limiter.check_locked('ip1') is None
    for _ in range(3):
        limiter.record('ip1')
    assert limiter.check_locked('ip1') is not None
    assert limiter.check_locked('ip2') is None


def test_health(client):
    r = client.get('/health')
    assert r.status_code == 200
    body = r.json()
    assert body['ok'] is True and body['auth'] is True and body['proxy'] is False
