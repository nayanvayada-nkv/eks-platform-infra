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
    print(f"migration done; role {env['DB_USER']} uses IAM authentication")


if __name__ == "__main__":
    main()
