"""Metrics (Prometheus) and traces (OpenTelemetry -> ADOT collector -> AWS X-Ray).

Metrics are served on a separate port (METRICS_PORT, default 9464) by the gunicorn master,
not on the API port: the Service and the ingress gateway only reach port 8080, so
/metrics is never public. Only Prometheus's identity may call 9464 (AuthorizationPolicy).
"""

import os
import time

from flask import Flask, g, request
from prometheus_client import Counter, Histogram

REQUESTS = Counter(
    "http_requests_total", "HTTP requests by route and status", ["method", "route", "status"]
)
LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    ["method", "route"],
    buckets=(0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10),
)
SKIP = {"/healthz", "/readyz"}  # probes would drown the SLO in easy successes


def _route() -> str:
    # The URL pattern, never the raw path: /items/123 and /items/456 are one series.
    return request.url_rule.rule if request.url_rule else "unmatched"


def instrument(app: Flask) -> None:
    @app.before_request
    def _start():
        g._start = time.perf_counter()

    @app.after_request
    def _record(response):
        route = _route()
        if route not in SKIP:
            REQUESTS.labels(request.method, route, str(response.status_code)).inc()
            LATENCY.labels(request.method, route).observe(time.perf_counter() - g._start)
        return response

    _tracing(app)


def _tracing(app: Flask) -> None:
    """Enabled only when OTEL_EXPORTER_OTLP_ENDPOINT is set (in the cluster, not in tests)."""
    if not os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT"):
        return
    from opentelemetry import trace
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
    from opentelemetry.instrumentation.flask import FlaskInstrumentor
    from opentelemetry.instrumentation.psycopg import PsycopgInstrumentor
    from opentelemetry.instrumentation.redis import RedisInstrumentor
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor

    provider = TracerProvider(resource=Resource.create({"service.name": "backend"}))
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    trace.set_tracer_provider(provider)
    FlaskInstrumentor().instrument_app(app, excluded_urls="healthz,readyz")
    PsycopgInstrumentor().instrument()  # SQL statements become spans (parameters are not recorded)
    RedisInstrumentor().instrument()
