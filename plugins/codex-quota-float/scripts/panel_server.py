#!/usr/bin/env python3
"""Serve a live local quota panel."""

from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

from collect_status import collect_status
from render_panel import build_html


class Handler(BaseHTTPRequestHandler):
    server_version = "CodexQuotaFloat/0.1"

    def _status(self) -> dict:
        return collect_status(self.server.args)  # type: ignore[attr-defined]

    def _send(self, code: int, body: bytes, content_type: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        if path == "/api/status":
            payload = json.dumps(self._status(), ensure_ascii=False).encode("utf-8")
            self._send(200, payload, "application/json; charset=utf-8")
            return
        if path in {"/", "/panel"}:
            body = build_html(self._status()).encode("utf-8")
            self._send(200, body, "text/html; charset=utf-8")
            return
        self._send(404, b"Not found", "text/plain; charset=utf-8")

    def log_message(self, format: str, *args: object) -> None:
        return


def main() -> int:
    parser = argparse.ArgumentParser(description="Serve Codex Quota Float panel.")
    parser.add_argument("--port", type=int, default=17447)
    parser.add_argument("--config")
    parser.add_argument("--cache")
    args = parser.parse_args()

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.args = args  # type: ignore[attr-defined]
    print(f"http://127.0.0.1:{args.port}/", flush=True)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
