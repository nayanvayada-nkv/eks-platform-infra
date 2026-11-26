from app import create_app


def client():
    return create_app().test_client()


def test_healthz():
    resp = client().get("/healthz")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}


def test_index_reports_version(monkeypatch):
    monkeypatch.setenv("APP_VERSION", "abc123")
    resp = client().get("/")
    assert resp.status_code == 200
    assert resp.get_json()["version"] == "abc123"
