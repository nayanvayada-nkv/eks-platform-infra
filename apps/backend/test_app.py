from botocore.credentials import Credentials

import aws_auth
import migrate
from app import create_app


class FakeStore:
    def __init__(self, healthy=True):
        self.items, self.healthy, self.cached = [], healthy, False

    def list_items(self):
        source = "cache" if self.cached else "database"
        self.cached = True
        return list(self.items), source

    def add_item(self, name):
        item = {"id": len(self.items) + 1, "name": name}
        self.items.append(item)
        self.cached = False
        return item

    def ping(self):
        if not self.healthy:
            raise ConnectionError("database down")


def client(store=None):
    return create_app(store or FakeStore()).test_client()


def test_healthz_never_touches_dependencies():
    resp = client(FakeStore(healthy=False)).get("/healthz")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}


def test_readyz_reports_dependency_failure():
    assert client(FakeStore(healthy=True)).get("/readyz").status_code == 200
    assert client(FakeStore(healthy=False)).get("/readyz").status_code == 503


def test_index_reports_version(monkeypatch):
    monkeypatch.setenv("APP_VERSION", "abc123")
    assert client().get("/").get_json()["version"] == "abc123"


def test_add_then_list_uses_cache_after_first_read():
    c = client()
    assert c.post("/items", json={"name": "  first  "}).status_code == 201
    first = c.get("/items").get_json()
    assert first == {"items": [{"id": 1, "name": "first"}], "source": "database"}
    assert c.get("/items").get_json()["source"] == "cache"


def test_add_item_validates_name():
    c = client()
    assert c.post("/items", json={}).status_code == 400
    assert c.post("/items", json={"name": "   "}).status_code == 400
    assert c.post("/items", json={"name": "x" * 201}).status_code == 400
    assert c.post("/items", data="not json").status_code == 400


class FakeSession:
    """Static credentials, so signing works offline."""

    def __init__(self):
        import botocore.session

        self._s = botocore.session.get_session()
        self.events = self._s.get_component("event_emitter")

    def get_credentials(self):
        return Credentials("AKIDEXAMPLE", "secret")


def test_elasticache_token_is_presigned_connect_request():
    token = aws_auth.elasticache_token("eks-platform-dev", "eks-platform-dev-app", "ap-south-1", FakeSession())
    assert token.startswith("eks-platform-dev/?Action=connect&User=eks-platform-dev-app")
    assert "ResourceType=ServerlessCache" in token
    assert "X-Amz-Signature=" in token and "X-Amz-Expires=900" in token
    assert not token.startswith("https://")


def test_migration_grants_least_privilege():
    rendered = " ".join(str(s.as_string(None)) for s in migrate.statements("app", "app"))
    assert "GRANT rds_iam" in rendered
    assert "GRANT SELECT, INSERT ON items" in rendered
    assert "DELETE" not in rendered and "SUPERUSER" not in rendered
