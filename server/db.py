"""SQLite 存储：用户与会话 token。"""

from __future__ import annotations

import hashlib
import hmac
import secrets
import sqlite3
import time
from dataclasses import dataclass
from pathlib import Path

# scrypt 参数（16MB 内存，小 VPS 轻松承担）：格式里带参数便于将来升级
_SCRYPT_N = 2 ** 14
_SCRYPT_R = 8
_SCRYPT_P = 1
_DKLEN = 32

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS tokens (
    token_hash TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL,
    expires_at REAL NOT NULL
);
"""

def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    dk = hashlib.scrypt(
        password.encode('utf-8'), salt=salt,
        n=_SCRYPT_N, r=_SCRYPT_R, p=_SCRYPT_P, dklen=_DKLEN,
    )
    return f'scrypt${_SCRYPT_N}${_SCRYPT_R}${_SCRYPT_P}${salt.hex()}${dk.hex()}'


def verify_password(password: str, stored: str) -> bool:
    try:
        algo, n, r, p, salt_hex, dk_hex = stored.split('$')
        if algo != 'scrypt':
            return False
        dk = hashlib.scrypt(
            password.encode('utf-8'), salt=bytes.fromhex(salt_hex),
            n=int(n), r=int(r), p=int(p), dklen=len(bytes.fromhex(dk_hex)),
        )
        return hmac.compare_digest(dk.hex(), dk_hex)
    except (ValueError, TypeError):
        return False


@dataclass
class User:
    id: int
    username: str
    created_at: str

    def public(self) -> dict:
        return {'id': self.id, 'username': self.username, 'created_at': self.created_at}


class UserStore:
    def __init__(self, path: str):
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._conn.executescript(SCHEMA)
        self._conn.commit()
        # 用户不存在时也走一次 scrypt，抹平时间差（防用户名枚举）
        self._dummy_hash = hash_password('dummy-' + secrets.token_hex(16))

    # ---------- 用户 ----------

    def create_user(self, username: str, password: str) -> User | None:
        """成功返回 User；用户名已存在返回 None。"""
        now = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
        try:
            cur = self._conn.execute(
                'INSERT INTO users (username, password_hash, created_at) VALUES (?, ?, ?)',
                (username, hash_password(password), now),
            )
            self._conn.commit()
        except sqlite3.IntegrityError:
            return None
        return User(id=cur.lastrowid, username=username, created_at=now)

    def verify_user(self, username: str, password: str) -> User | None:
        row = self._conn.execute(
            'SELECT id, username, password_hash, created_at FROM users WHERE username = ?',
            (username,),
        ).fetchone()
        if row is None:
            verify_password(password, self._dummy_hash)  # 抹平时间差
            return None
        if not verify_password(password, row['password_hash']):
            return None
        return User(id=row['id'], username=row['username'], created_at=row['created_at'])

    def get_user(self, user_id: int) -> User | None:
        row = self._conn.execute(
            'SELECT id, username, created_at FROM users WHERE id = ?', (user_id,),
        ).fetchone()
        return User(id=row['id'], username=row['username'], created_at=row['created_at']) if row else None

    # ---------- 令牌 ----------

    def issue_token(self, user_id: int, ttl_days: int = 30) -> str:
        token = secrets.token_urlsafe(32)
        self._conn.execute(
            'INSERT INTO tokens (token_hash, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)',
            (hashlib.sha256(token.encode()).hexdigest(), user_id,
             time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
             time.time() + ttl_days * 86400),
        )
        self._conn.commit()
        return token

    def user_for_token(self, token: str) -> User | None:
        row = self._conn.execute(
            'SELECT user_id, expires_at FROM tokens WHERE token_hash = ?',
            (hashlib.sha256(token.encode()).hexdigest(),),
        ).fetchone()
        if row is None or row['expires_at'] < time.time():
            return None
        return self.get_user(row['user_id'])

    def revoke_token(self, token: str) -> None:
        self._conn.execute(
            'DELETE FROM tokens WHERE token_hash = ?',
            (hashlib.sha256(token.encode()).hexdigest(),),
        )
        self._conn.commit()

    def cleanup_expired(self) -> None:
        self._conn.execute('DELETE FROM tokens WHERE expires_at < ?', (time.time(),))
        self._conn.commit()
