"""Backend API placeholder.

Phase 2 uses it to prove the supply chain (build, scan, sign, deploy by digest).
Phase 4 grows it into the real Flask API (Aurora, Redis, RAG).
"""

import os

from flask import Flask, jsonify


def create_app() -> Flask:
    app = Flask(__name__)

    @app.get("/healthz")
    def healthz():
        return jsonify(status="ok")

    @app.get("/")
    def index():
        return jsonify(
            service="backend",
            version=os.environ.get("APP_VERSION", "dev"),
        )

    return app


app = create_app()
