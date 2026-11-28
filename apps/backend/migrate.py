"""Database setup, run by the db-migrate Job on every deploy (idempotent).

Runs under its own service account, whose IAM role may read the Aurora admin secret.
It creates the "app" role (IAM login only, no password) and grants it the least it needs.
"""

import json
import os

import boto3
import psycopg
from psycopg import sql

CA_BUNDLE = os.path.join(os.path.dirname(__file__), "certs", "rds-global-bundle.pem")


def admin_credentials(secret_arn: str, region: str) -> dict:
    secrets = boto3.client("secretsmanager", region_name=region)
    return json.loads(secrets.get_secret_value(SecretId=secret_arn)["SecretString"])


def statements(app_user: str, db_name: str):
    user, db = sql.Identifier(app_user), sql.Identifier(db_name)
    return base_statements(app_user, user, db) + rag_statements(user)


def base_statements(app_user, user, db):
    return [
        sql.SQL(
            "DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = {name}) "
            "THEN CREATE ROLE {user} LOGIN; END IF; END $$"
        ).format(name=sql.Literal(app_user), user=user),
        sql.SQL("GRANT rds_iam TO {user}").format(user=user),  # login with IAM tokens only
        sql.SQL(
            "CREATE TABLE IF NOT EXISTS items ("
            " id bigserial PRIMARY KEY,"
            " name text NOT NULL CHECK (length(name) BETWEEN 1 AND 200),"
            " created_at timestamptz NOT NULL DEFAULT now())"
        ),
        sql.SQL("REVOKE ALL ON SCHEMA public FROM PUBLIC"),
        sql.SQL("GRANT CONNECT ON DATABASE {db} TO {user}").format(db=db, user=user),
        sql.SQL("GRANT USAGE ON SCHEMA public TO {user}").format(user=user),
        # Read and add items; no UPDATE, DELETE or DDL for the API.
        sql.SQL("GRANT SELECT, INSERT ON items TO {user}").format(user=user),
        sql.SQL("GRANT USAGE ON SEQUENCE items_id_seq TO {user}").format(user=user),
    ]


def rag_statements(user):
    """Phase 9: pgvector + tenants with row-level security (tenant isolation in the database)."""
    return [
        sql.SQL("CREATE EXTENSION IF NOT EXISTS vector"),
        sql.SQL(
            "CREATE TABLE IF NOT EXISTS tenants ("
            " id text PRIMARY KEY CHECK (id ~ '^[a-z0-9-]{3,40}$'),"
            " name text NOT NULL,"
            " api_key_sha256 text UNIQUE,"  # only the hash; the key itself is given to the customer once
            " enabled boolean NOT NULL DEFAULT true,"
            " created_at timestamptz NOT NULL DEFAULT now())"
        ),
        sql.SQL(
            "CREATE TABLE IF NOT EXISTS documents ("
            " id bigserial PRIMARY KEY,"
            " tenant_id text NOT NULL REFERENCES tenants(id),"
            " title text NOT NULL,"
            " chunk_index integer NOT NULL,"
            " content text NOT NULL,"
            " embedding vector(1024) NOT NULL,"
            " created_at timestamptz NOT NULL DEFAULT now())"
        ),
        # HNSW: approximate nearest-neighbour index, cosine distance (Titan vectors are normalised).
        sql.SQL("CREATE INDEX IF NOT EXISTS documents_embedding_hnsw ON documents USING hnsw (embedding vector_cosine_ops)"),
        sql.SQL("CREATE INDEX IF NOT EXISTS documents_tenant ON documents (tenant_id)"),
        # Row-level security: every query on documents only sees rows of the tenant set in
        # app.tenant_id for that transaction. FORCE applies it to the table owner too.
        sql.SQL("ALTER TABLE documents ENABLE ROW LEVEL SECURITY"),
        sql.SQL("ALTER TABLE documents FORCE ROW LEVEL SECURITY"),
        sql.SQL("DROP POLICY IF EXISTS tenant_isolation ON documents"),
        sql.SQL(
            "CREATE POLICY tenant_isolation ON documents"
            " USING (tenant_id = current_setting('app.tenant_id', true))"
            " WITH CHECK (tenant_id = current_setting('app.tenant_id', true))"
        ),
        sql.SQL("GRANT SELECT, INSERT ON documents TO {user}").format(user=user),
        sql.SQL("GRANT USAGE ON SEQUENCE documents_id_seq TO {user}").format(user=user),
        # The API may look tenants up by key hash, never change them (onboarding is GitOps).
        sql.SQL("GRANT SELECT (id, api_key_sha256, enabled) ON tenants TO {user}").format(user=user),
    ]


def tenant_sync_statements(tenants: list[dict]):
    """Onboarding / offboarding from Git (gitops/workloads/backend/tenants): listed tenants
    are upserted, tenants no longer listed are disabled (their data stays, their key stops working)."""
    stmts = []
    for t in tenants:
        stmts.append(
            (
                "INSERT INTO tenants (id, name, api_key_sha256, enabled) VALUES (%s, %s, %s, true)"
                " ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name,"
                " api_key_sha256 = EXCLUDED.api_key_sha256, enabled = true",
                (t["id"], t["name"], t["apiKeySha256"]),
            )
        )
    ids = [t["id"] for t in tenants]
    stmts.append(("UPDATE tenants SET enabled = false WHERE NOT (id = ANY(%s))", (ids,)))
    return stmts


def validate_tenants(raw: str) -> list[dict]:
    tenants = json.loads(raw or "[]")
    for t in tenants:
        if not all(isinstance(t.get(k), str) for k in ("id", "name", "apiKeySha256")):
            raise ValueError(f"tenant entry needs id, name, apiKeySha256: {t}")
        if len(t["apiKeySha256"]) != 64 or any(ch not in "0123456789abcdef" for ch in t["apiKeySha256"]):
            raise ValueError(f"apiKeySha256 must be 64 lowercase hex characters: {t['id']}")
    return tenants


def main():
    env = os.environ
    creds = admin_credentials(env["DB_ADMIN_SECRET"], env["AWS_REGION"])
    with psycopg.connect(
        host=env["DB_HOST"],
        port=int(env.get("DB_PORT", "5432")),
        dbname=env["DB_NAME"],
        user=creds["username"],
        password=creds["password"],
        sslmode="verify-full",
        sslrootcert=CA_BUNDLE,
        connect_timeout=30,  # first connection may wake Aurora from 0 ACU
    ) as conn:
        for stmt in statements(env["DB_USER"], env["DB_NAME"]):
            conn.execute(stmt)
        tenants = validate_tenants(env.get("TENANTS_JSON", "[]"))
        for query, params in tenant_sync_statements(tenants):
            conn.execute(query, params)
    print(f"migration done; role {env['DB_USER']} uses IAM authentication; {len(tenants)} tenant(s) active")


if __name__ == "__main__":
    main()
