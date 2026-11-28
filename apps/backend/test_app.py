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


def _count(route, status):
    from prometheus_client import REGISTRY

    value = REGISTRY.get_sample_value(
        "http_requests_total", {"method": "GET", "route": route, "status": status}
    )
    return value or 0


def test_metrics_count_by_route_pattern_and_skip_probes():
    c = client()
    before_items, before_health = _count("/items", "200"), _count("/healthz", "200")
    c.get("/items")
    c.get("/healthz")
    c.get("/no-such-page")
    assert _count("/items", "200") == before_items + 1
    assert _count("/healthz", "200") == before_health  # probes are not part of the SLO
    assert _count("unmatched", "404") >= 1  # raw paths never become labels


# ---------------------------------------------------------------------------- Phase 9: RAG
import rag  # noqa: E402

KEYS = {"acme-key": "acme", "globex-key": "globex"}


class RagStore(FakeStore):
    """Mimics row-level security: search only ever returns the caller's tenant rows."""

    def __init__(self):
        super().__init__()
        self.docs, self.answers = [], {}

    def tenant_for_key(self, key):
        return KEYS.get(key)

    def add_chunks(self, tenant, title, chunks):
        self.docs += [{"tenant": tenant, "title": title, "content": c} for c, _ in chunks]
        return len(chunks)

    def search(self, tenant, vector, k):
        return [{"title": d["title"], "content": d["content"], "distance": 0.1} for d in self.docs if d["tenant"] == tenant][:k]

    def cached_answer(self, tenant, q):
        return self.answers.get((tenant, q))

    def cache_answer(self, tenant, q, a):
        self.answers[(tenant, q)] = a


class FakeEmbedder:
    def embed(self, text):
        return [0.0] * rag.EMBED_DIMENSIONS


class FakeAnswerer:
    def __init__(self, refuse=False):
        self.calls, self.refuse = [], refuse

    def answer(self, question, chunks):
        self.calls.append(chunks)
        if self.refuse:
            return {"answer": None, "refused": True, "sources": [], "usage": {}}
        return {"answer": "42", "refused": False, "sources": [chunks[0]["title"]], "usage": {"input_tokens": 10, "output_tokens": 2}}


def rag_client(answerer=None):
    store, ans = RagStore(), answerer or FakeAnswerer()
    return create_app(store, FakeEmbedder(), ans).test_client(), store, ans


def auth(key):
    return {"Authorization": f"Bearer {key}"}


def test_rag_requires_a_valid_api_key():
    c, _, _ = rag_client()
    assert c.post("/ask", json={"question": "x"}).status_code == 401
    assert c.post("/ask", json={"question": "x"}, headers=auth("wrong")).status_code == 401


def test_tenants_only_see_their_own_documents():
    c, _, answerer = rag_client()
    assert c.post("/documents", json={"title": "acme-policy", "content": "Acme refunds in 30 days."}, headers=auth("acme-key")).status_code == 201
    # globex has no documents: no model call is made at all
    assert c.post("/ask", json={"question": "refunds?"}, headers=auth("globex-key")).status_code == 404
    assert answerer.calls == []
    resp = c.post("/ask", json={"question": "refunds?"}, headers=auth("acme-key"))
    assert resp.status_code == 200 and resp.get_json()["sources"] == ["acme-policy"]
    assert all(ch["title"] == "acme-policy" for ch in answerer.calls[0])


def test_repeated_question_is_served_from_cache():
    c, _, answerer = rag_client()
    c.post("/documents", json={"title": "t", "content": "hello world"}, headers=auth("acme-key"))
    c.post("/ask", json={"question": "hi"}, headers=auth("acme-key"))
    second = c.post("/ask", json={"question": "hi"}, headers=auth("acme-key")).get_json()
    assert second["cached"] is True and len(answerer.calls) == 1


def test_refusal_returns_422_and_is_not_cached():
    c, store, _ = rag_client(FakeAnswerer(refuse=True))
    c.post("/documents", json={"title": "t", "content": "hello"}, headers=auth("acme-key"))
    assert c.post("/ask", json={"question": "q"}, headers=auth("acme-key")).status_code == 422
    assert store.answers == {}


def test_input_limits():
    c, _, _ = rag_client()
    assert c.post("/ask", json={"question": "x" * 1001}, headers=auth("acme-key")).status_code == 400
    assert c.post("/documents", json={"title": "", "content": "x"}, headers=auth("acme-key")).status_code == 400


def test_chunking_overlaps_and_covers_text():
    text = "".join(f"{i:05d}" for i in range(1000))  # 5000 characters
    chunks = rag.chunk_text(text, size=1200, overlap=200)
    assert all(len(ch) <= 1200 for ch in chunks)
    assert chunks[0][-200:] == chunks[1][:200]
    assert chunks[-1].endswith(text[-50:])
    assert rag.chunk_text("   ") == []


def test_tenant_sync_upserts_and_disables_missing():
    good = '[{"id": "acme", "name": "Acme", "apiKeySha256": "' + "a" * 64 + '"}]'
    stmts = migrate.tenant_sync_statements(migrate.validate_tenants(good))
    assert "ON CONFLICT" in stmts[0][0] and stmts[-1][1] == (["acme"],)
    import pytest

    with pytest.raises(ValueError):
        migrate.validate_tenants('[{"id": "acme", "name": "Acme", "apiKeySha256": "not-a-hash"}]')


def test_rls_statements_force_tenant_isolation():
    rendered = " ".join(str(s.as_string(None)) for s in migrate.rag_statements(migrate.sql.Identifier("app")))
    assert "FORCE ROW LEVEL SECURITY" in rendered
    assert "current_setting('app.tenant_id', true)" in rendered
    assert "UPDATE" not in rendered and "DELETE" not in rendered  # the API cannot change or delete rows


def test_claude_answerer_reads_text_and_citations(monkeypatch):
    from types import SimpleNamespace as NS

    fake = NS(
        stop_reason="end_turn",
        model="anthropic.claude-opus-5-5",
        usage=NS(input_tokens=100, output_tokens=20),
        content=[
            NS(type="thinking", thinking=""),
            NS(type="text", text="Refunds take 30 days.", citations=[NS(document_title="acme-policy")]),
        ],
    )
    a = rag.ClaudeAnswerer("ap-south-1", "anthropic.claude-opus-5-5", "anthropic.claude-opus-4-8")
    sent = {}

    def create(**kwargs):
        sent.update(kwargs)
        return fake

    monkeypatch.setattr(a.client.beta.messages, "create", create)
    out = a.answer("refunds?", [{"title": "acme-policy", "content": "Acme refunds in 30 days."}])
    assert out == {"answer": "Refunds take 30 days.", "refused": False, "sources": ["acme-policy"], "model": "anthropic.claude-opus-5-5", "usage": {"input_tokens": 100, "output_tokens": 20}}
    doc = sent["messages"][0]["content"][0]
    assert doc["type"] == "document" and doc["citations"] == {"enabled": True}  # retrieved text is data, not instructions
    assert sent["output_config"] == {"effort": "low"} and "temperature" not in sent
