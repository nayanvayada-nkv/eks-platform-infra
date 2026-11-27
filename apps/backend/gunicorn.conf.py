"""Gunicorn settings. Metrics from all workers are merged (prometheus_client multiprocess
mode) and served by the master on METRICS_PORT, separate from the API port."""

import os
import shutil

bind = "0.0.0.0:8080"
workers = 2
worker_tmp_dir = "/tmp"
accesslog = "-"

METRICS_DIR = os.environ.setdefault("PROMETHEUS_MULTIPROC_DIR", "/tmp/prometheus")


def on_starting(server):
    shutil.rmtree(METRICS_DIR, ignore_errors=True)  # stale files from a previous run would double count
    os.makedirs(METRICS_DIR, exist_ok=True)


def when_ready(server):
    from prometheus_client import CollectorRegistry, multiprocess, start_http_server

    registry = CollectorRegistry()
    multiprocess.MultiProcessCollector(registry)
    start_http_server(int(os.environ.get("METRICS_PORT", "9464")), registry=registry)


def child_exit(server, worker):
    from prometheus_client import multiprocess

    multiprocess.mark_process_dead(worker.pid)
