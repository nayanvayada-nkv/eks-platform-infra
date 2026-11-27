"""Load test for the backend API through CloudFront (Phase 8).

Profiles (LOAD_PROFILE): smoke | ramp | spike | soak. See docs/runbooks/load-test.md.
Traffic mix, by default: 80% reads of /items (mostly cache hits), 10% writes, 10% index.
RAG (/ask) is OFF unless RAG_KEY is set: every uncached answer costs Claude tokens, so it runs
at a low, fixed share (RAG_WEIGHT) and with a small rotating question set (cache hits count too).
"""

import os
import random
import uuid

from locust import HttpUser, LoadTestShape, between, task

RAG_KEY = os.environ.get("RAG_KEY", "")
RAG_QUESTIONS = [
    "How many days does a customer have to file a damage claim?",
    "What shipping credit applies after a 5 day delay?",
    "What is the fee for cancelling after pickup?",
]


class ApiUser(HttpUser):
    wait_time = between(0.5, 2)

    @task(8)
    def list_items(self):
        self.client.get("/items", name="GET /items")

    @task(1)
    def add_item(self):
        self.client.post("/items", json={"name": f"load-{uuid.uuid4().hex[:8]}"}, name="POST /items")

    @task(1)
    def index(self):
        self.client.get("/", name="GET /")


class RagUser(HttpUser):
    """Only spawned when RAG_KEY is set (weight 0 otherwise)."""

    weight = int(os.environ.get("RAG_WEIGHT", "1")) if RAG_KEY else 0
    wait_time = between(5, 15)

    @task
    def ask(self):
        self.client.post(
            "/ask",
            json={"question": random.choice(RAG_QUESTIONS)},
            headers={"Authorization": f"Bearer {RAG_KEY}"},
            name="POST /ask",
        )


PROFILES = {
    # (seconds from start, total users, spawn rate per second)
    "smoke": [(60, 5, 1)],  # 1 minute, 5 users: does it work at all?
    "ramp": [(120, 25, 1), (300, 100, 2), (600, 200, 2), (780, 200, 2), (900, 0, 10)],
    "spike": [(120, 20, 2), (180, 300, 50), (420, 300, 50), (540, 20, 20), (600, 0, 10)],
    "soak": [(120, 60, 2), (1920, 60, 2), (1980, 0, 10)],
}


class Profile(LoadTestShape):
    """Stages for the chosen profile; the run stops after the last stage."""

    stages = PROFILES[os.environ.get("LOAD_PROFILE", "smoke")]

    def tick(self):
        run_time = self.get_run_time()
        for end, users, rate in self.stages:
            if run_time < end:
                return users, rate
        return None
