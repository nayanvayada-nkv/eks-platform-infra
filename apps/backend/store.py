"""Data access: Aurora PostgreSQL (source of truth) and Valkey (read cache)."""

import json
import os
import time

import psycopg
import redis

from aws_auth import TOKEN_TTL_SECONDS, aurora_token, elasticache_token

CA_BUNDLE = os.path.join(os.path.dirname(__file__), "certs", "rds-global-bundle.pem")
CACHE_KEY = "backend:items"  # the Valkey user may only touch keys under "backend:"
CACHE_SECONDS = 30


class ValkeyIamCredentials(redis.CredentialProvider):
    """Gives redis-py a fresh IAM token, re-signed before the 15-minute expiry."""

    def __init__(self, cache_name: str, user_id: str, region: str):
        self.cache_name, self.user_id, self.region = cache_name, user_id, region
        self._token, self._expires = "", 0.0

    def get_credentials(self):
        if time.time() > self._expires:
            self._token = elasticache_token(self.cache_name, self.user_id, self.region)
            self._expires = time.time() + TOKEN_TTL_SECONDS - 60
        return self.user_id, self._token


class AwsStore:
    def __init__(self, env=os.environ):
        self.region = env["AWS_REGION"]
        self.db_host, self.db_port = env["DB_HOST"], int(env.get("DB_PORT", "5432"))
        self.db_name, self.db_user = env["DB_NAME"], env["DB_USER"]
        self.cache = redis.Redis(
            host=env["CACHE_HOST"],
            port=int(env.get("CACHE_PORT", "6379")),
            ssl=True,  # serverless caches only accept TLS
            credential_provider=ValkeyIamCredentials(env["CACHE_NAME"], env["CACHE_USER"], self.region),
            socket_timeout=2,
            decode_responses=True,
        )

    def _db(self):
        return psycopg.connect(
            host=self.db_host,
            port=self.db_port,
            dbname=self.db_name,
            user=self.db_user,
            password=aurora_token(self.db_host, self.db_port, self.db_user, self.region),
            sslmode="verify-full",  # encrypted AND the server certificate is checked against the RDS CA
            sslrootcert=CA_BUNDLE,
            connect_timeout=10,  # Aurora may be resuming from 0 ACU
        )

    def list_items(self):
        cached = self.cache.get(CACHE_KEY)
        if cached is not None:
            return json.loads(cached), "cache"
        with self._db() as conn:
            rows = conn.execute("SELECT id, name FROM items ORDER BY id").fetchall()
        items = [{"id": r[0], "name": r[1]} for r in rows]
        self.cache.set(CACHE_KEY, json.dumps(items), ex=CACHE_SECONDS)
        return items, "database"

    def add_item(self, name: str):
        with self._db() as conn:
            row = conn.execute(
                "INSERT INTO items (name) VALUES (%s) RETURNING id, name", (name,)
            ).fetchone()
        self.cache.delete(CACHE_KEY)  # next read reloads from the database
        return {"id": row[0], "name": row[1]}

    def ping(self):
        with self._db() as conn:
            conn.execute("SELECT 1")
        self.cache.ping()
