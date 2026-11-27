"""Backend API: items stored in Aurora PostgreSQL, cached in Valkey (Phase 4),
with metrics and traces (Phase 6, see telemetry.py).

Every login uses a short-lived IAM token from the pod's identity; the app holds no passwords.
"""

import os

from flask import Flask, jsonify, request

from telemetry import instrument

MAX_NAME = 200


def create_app(store=None) -> Flask:
    app = Flask(__name__)
    instrument(app)
    state = {"store": store}

    def get_store():
        if state["store"] is None:
            from store import AwsStore  # imported lazily so tests need no AWS settings

            state["store"] = AwsStore()
        return state["store"]

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

    return app


app = create_app()
