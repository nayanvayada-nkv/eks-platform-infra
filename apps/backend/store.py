"""Data access: Aurora PostgreSQL (source of truth) and Valkey (read cache)."""

import hashlib
import json
import os
import time

import psycopg
import redis

from aws_auth import TOKEN_TTL_SECONDS, aurora_token, elasticache_token

CA_BUNDLE = os.path.join(os.path.dirname(__file__), "certs", "rds-global-bundle.pem")
CACHE_KEY = "backend:items"  # the Valkey user may only touch keys under "backend:"
CACHE_SECONDS = 30
ANSWER_CACHE_SECONDS = 600


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

    # ------------------------------------------------------------------ Phase 9: tenants + RAG

    def tenant_for_key(self, api_key: str):
        """Tenants are identified by API key; only its SHA-256 is stored (see migrate.py)."""
        digest = hashlib.sha256(api_key.encode()).hexdigest()
        with self._db() as conn:
            row = conn.execute(
                "SELECT id FROM tenants WHERE api_key_sha256 = %s AND enabled", (digest,)
            ).fetchone()
        return row[0] if row else None

    def _tenant_tx(self, conn, tenant_id: str):
        # Row-level security reads this setting; "true" = local to this transaction only,
        # so a pooled connection can never carry one tenant's id into another request.
        conn.execute("SELECT set_config('app.tenant_id', %s, true)", (tenant_id,))

    def add_chunks(self, tenant_id: str, title: str, chunks: list[tuple[str, str]]):
        """chunks: (content, pgvector literal). Returns the number stored."""
        with self._db() as conn, conn.transaction():
            self._tenant_tx(conn, tenant_id)
            with conn.cursor() as cur:
                cur.executemany(
                    "INSERT INTO documents (tenant_id, title, chunk_index, content, embedding)"
                    " VALUES (%s, %s, %s, %s, %s::vector)",
                    [(tenant_id, title, i, content, vec) for i, (content, vec) in enumerate(chunks)],
                )
        # Cached answers for this tenant may now be stale; they expire within ANSWER_CACHE_SECONDS
        # (Valkey ACL forbids KEYS/SCAN-style bulk deletes for the app user, on purpose).
        return len(chunks)

    def search(self, tenant_id: str, query_vector: str, k: int):
        with self._db() as conn, conn.transaction():
            self._tenant_tx(conn, tenant_id)
            # With a tenant filter (RLS) the HNSW index may return fewer than k rows;
            # iterative scans (pgvector 0.8+) keep searching until k matching rows are found.
            conn.execute("SET LOCAL hnsw.iterative_scan = relaxed_order")
            rows = conn.execute(
                "SELECT title, content, embedding <=> %s::vector AS distance"
                " FROM documents ORDER BY embedding <=> %s::vector LIMIT %s",
                (query_vector, query_vector, k),
            ).fetchall()
        return [{"title": r[0], "content": r[1], "distance": float(r[2])} for r in rows]

    @staticmethod
    def _answers_prefix(tenant_id: str) -> str:
        return f"backend:ask:{tenant_id}:"

    def cached_answer(self, tenant_id: str, question: str):
        key = self._answers_prefix(tenant_id) + hashlib.sha256(question.encode()).hexdigest()
        cached = self.cache.get(key)
        return json.loads(cached) if cached else None

    def cache_answer(self, tenant_id: str, question: str, answer: dict):
        key = self._answers_prefix(tenant_id) + hashlib.sha256(question.encode()).hexdigest()
        self.cache.set(key, json.dumps(answer), ex=ANSWER_CACHE_SECONDS)
