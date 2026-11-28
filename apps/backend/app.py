"""Backend API: items stored in Aurora PostgreSQL, cached in Valkey (Phase 4),
with metrics and traces (Phase 6, see telemetry.py).

Every login uses a short-lived IAM token from the pod's identity; the app holds no passwords.
"""

import os

from flask import Flask, jsonify, request

from telemetry import instrument, record_llm_usage

MAX_NAME = 200
MAX_QUESTION = 1000
MAX_DOCUMENT = 200_000  # characters per upload


def create_app(store=None, embedder=None, answerer=None) -> Flask:
    app = Flask(__name__)
    instrument(app)
    state = {"store": store, "embedder": embedder, "answerer": answerer}

    def get_store():
        if state["store"] is None:
            from store import AwsStore  # imported lazily so tests need no AWS settings

            state["store"] = AwsStore()
        return state["store"]

    def get_rag():
        if state["embedder"] is None or state["answerer"] is None:
            import rag  # imported lazily: tests inject fakes, no AWS settings needed

            state["embedder"], state["answerer"] = rag.from_env()
        return state["embedder"], state["answerer"]

    def current_tenant():
        """Tenant from 'Authorization: Bearer <api key>'. Returns (tenant_id, error_response)."""
        header = request.headers.get("Authorization", "")
        if not header.startswith("Bearer ") or len(header) > 200:
            return None, (jsonify(error="missing API key"), 401)
        tenant = get_store().tenant_for_key(header.removeprefix("Bearer ").strip())
        if tenant is None:
            return None, (jsonify(error="invalid API key"), 401)
        return tenant, None

    @app.get("/healthz")
    def healthz():
        # Liveness: the process works. Never checks dependencies, so a database blip
        # does not make Kubernetes restart every pod.
        return jsonify(status="ok")

    @app.get("/readyz")
    def readyz():
        # Readiness: can we reach Aurora and Valkey? If not, take this pod out of the Service.
        try:
            get_store().ping()
        except Exception as exc:  # noqa: BLE001 - report any dependency failure
            app.logger.warning("not ready: %s", exc)
            return jsonify(status="unavailable"), 503
        return jsonify(status="ready")

    @app.get("/")
    def index():
        return jsonify(service="backend", version=os.environ.get("APP_VERSION", "dev"))

    @app.get("/items")
    def list_items():
        items, source = get_store().list_items()
        return jsonify(items=items, source=source)

    @app.post("/items")
    def add_item():
        body = request.get_json(silent=True) or {}
        name = body.get("name")
        if not isinstance(name, str) or not name.strip() or len(name) > MAX_NAME:
            return jsonify(error=f"name must be a non-empty string of at most {MAX_NAME} characters"), 400
        return jsonify(get_store().add_item(name.strip())), 201

    # ---------------------------------------------------------------- Phase 9: RAG per tenant

    @app.post("/documents")
    def add_document():
        tenant, error = current_tenant()
        if error:
            return error
        body = request.get_json(silent=True) or {}
        title, content = body.get("title"), body.get("content")
        if not isinstance(title, str) or not title.strip() or len(title) > MAX_NAME:
            return jsonify(error=f"title must be 1 to {MAX_NAME} characters"), 400
        if not isinstance(content, str) or not content.strip() or len(content) > MAX_DOCUMENT:
            return jsonify(error=f"content must be 1 to {MAX_DOCUMENT} characters"), 400
        import rag

        embedder, _ = get_rag()
        chunks = [(c, rag.to_pgvector(embedder.embed(c))) for c in rag.chunk_text(content)]
        stored = get_store().add_chunks(tenant, title.strip(), chunks)
        return jsonify(title=title.strip(), chunks=stored), 201

    @app.post("/ask")
    def ask():
        tenant, error = current_tenant()
        if error:
            return error
        body = request.get_json(silent=True) or {}
        question = body.get("question")
        if not isinstance(question, str) or not question.strip() or len(question) > MAX_QUESTION:
            return jsonify(error=f"question must be 1 to {MAX_QUESTION} characters"), 400
        question = question.strip()
        store = get_store()
        cached = store.cached_answer(tenant, question)
        if cached:
            return jsonify(**cached, cached=True)
        import rag

        embedder, answerer = get_rag()
        chunks = store.search(tenant, rag.to_pgvector(embedder.embed(question)), rag.TOP_K)
        if not chunks:  # nothing to ground an answer in: do not spend model tokens
            return jsonify(answer=None, sources=[], reason="no documents for this tenant"), 404
        result = answerer.answer(question, chunks)
        record_llm_usage(result.get("usage", {}), refused=result["refused"])
        if result["refused"]:
            return jsonify(answer=None, sources=[], reason="the model declined this request"), 422
        payload = {"answer": result["answer"], "sources": result["sources"]}
        store.cache_answer(tenant, question, payload)
        return jsonify(**payload, cached=False)

    return app


app = create_app()
