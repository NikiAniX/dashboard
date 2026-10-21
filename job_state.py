"""Persistent last-run tracking for dashboard jobs.

Every POST to a registered job endpoint (browser or curl) is recorded in a CSV
file keyed by endpoint path, so the frontend can poll ``/api/jobs/status``.

Public API: ``JobStateStore`` and ``register_job_tracking``.
"""

from __future__ import annotations

import csv
import json
import os
import tempfile
import threading
import time
from pathlib import Path

from flask import Flask, Response, g, jsonify, request

BASE_DIR = Path(__file__).resolve().parent
JOB_STATE_CSV = BASE_DIR / "data" / "job_runs.csv"
CSV_FIELDS = ["endpoint", "status", "last_run", "http_status", "logs"]
STATUS_RUNNING = "running"
STATUS_COMPLETED = "completed"
STATUS_FAILED = "failed"
HTTP_ERROR_THRESHOLD = 400
MAX_LOG_LINES = 200
TIMESTAMP_FORMAT = "%H:%M:%S"
STATUS_ROUTE = "/api/jobs/status"


class JobStateStore:
    """Thread-safe store of the latest run per endpoint, backed by a CSV file."""

    def __init__(self, csv_path: Path = JOB_STATE_CSV) -> None:
        self._csv_path = csv_path.resolve()
        self._lock = threading.Lock()
        self._rows: dict[str, dict] = self._load()
        self._fail_interrupted_runs()

    def start(self, endpoint: str) -> None:
        """Mark *endpoint* as running."""
        with self._lock:
            previous = self._rows.get(endpoint, {})
            self._rows[endpoint] = {
                "endpoint": endpoint,
                "status": STATUS_RUNNING,
                "last_run": time.time(),
                "http_status": "",
                "logs": previous.get("logs", "[]"),
            }
            self._save()

    def finish(self, endpoint: str, http_status: int, logs: list[str]) -> None:
        """Record the outcome of the run that was started for *endpoint*."""
        failed = http_status >= HTTP_ERROR_THRESHOLD
        stamp = time.strftime(TIMESTAMP_FORMAT)
        lines = [f"[{stamp}] {line}" for line in logs[-MAX_LOG_LINES:]]
        with self._lock:
            self._rows[endpoint] = {
                "endpoint": endpoint,
                "status": STATUS_FAILED if failed else STATUS_COMPLETED,
                "last_run": time.time(),
                "http_status": http_status,
                "logs": json.dumps(lines),
            }
            self._save()

    def snapshot(self) -> dict[str, dict]:
        """Return JSON-ready state keyed by endpoint."""
        with self._lock:
            return {
                endpoint: {
                    "status": row["status"],
                    "last_run": float(row["last_run"]),
                    "http_status": row["http_status"],
                    "logs": json.loads(row["logs"] or "[]"),
                }
                for endpoint, row in self._rows.items()
            }

    def _load(self) -> dict[str, dict]:
        if not self._csv_path.exists():
            return {}
        with self._csv_path.open(newline="", encoding="utf-8") as handle:
            return {row["endpoint"]: row for row in csv.DictReader(handle)}

    def _fail_interrupted_runs(self) -> None:
        """A run still 'running' at startup died with the previous process."""
        interrupted = [r for r in self._rows.values() if r["status"] == STATUS_RUNNING]
        for row in interrupted:
            row["status"] = STATUS_FAILED
            row["logs"] = json.dumps(["Run interrupted by dashboard restart."])
        if interrupted:
            self._save()

    def _save(self) -> None:
        """Atomically rewrite the CSV (caller holds the lock)."""
        self._csv_path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp_name = tempfile.mkstemp(dir=self._csv_path.parent, suffix=".tmp")
        with os.fdopen(fd, "w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=CSV_FIELDS)
            writer.writeheader()
            writer.writerows(self._rows.values())
        Path(tmp_name).replace(self._csv_path)


def _extract_logs(response: Response) -> list[str]:
    """Pull the module's ``logs`` array from a JSON response, else HTTP status."""
    if response.is_json and not response.direct_passthrough:
        data = response.get_json(silent=True)
        if isinstance(data, dict) and isinstance(data.get("logs"), list):
            return [str(line) for line in data["logs"]]
    return [f"HTTP {response.status}"]


def register_job_tracking(app: Flask, endpoints: set[str], store: JobStateStore | None = None) -> JobStateStore:
    """Track POSTs to *endpoints* and expose ``GET /api/jobs/status``."""
    store = store or JobStateStore()

    def tracked_endpoint() -> str | None:
        if request.method == "POST" and request.path in endpoints:
            return request.path
        return None

    @app.before_request
    def mark_job_started():
        endpoint = tracked_endpoint()
        if endpoint:
            g.job_endpoint = endpoint
            store.start(endpoint)

    @app.after_request
    def mark_job_finished(response: Response) -> Response:
        endpoint = g.pop("job_endpoint", None)
        if endpoint:
            store.finish(endpoint, response.status_code, _extract_logs(response))
        return response

    @app.get(STATUS_ROUTE)
    def jobs_status():
        return jsonify(store.snapshot())

    return store
