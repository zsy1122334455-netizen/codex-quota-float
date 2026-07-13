#!/usr/bin/env python3
"""Collect official Codex quota status without reading local task content."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import queue
import shutil
import subprocess
import threading
import time
from pathlib import Path
from typing import Any


PLUGIN_NAME = "codex-quota-float"
DEFAULT_CONFIG = Path.home() / ".codex" / "quota-float.json"
DEFAULT_CACHE = Path.home() / ".codex" / "quota-float-cache.json"
APP_SERVER_TIMEOUT_SECONDS = 12


def iso_from_ts(ts: int | float | None) -> str | None:
    if ts is None:
        return None
    return dt.datetime.fromtimestamp(float(ts), tz=dt.timezone.utc).astimezone().isoformat()


def load_manual_config(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"{path} must contain a JSON object.")
    return payload


def normalized_manual_limit(entry: dict[str, Any], index: int) -> dict[str, Any]:
    label = str(entry.get("label") or entry.get("name") or f"Manual limit {index + 1}")
    percent = entry.get("remainingPercent", entry.get("percent"))
    if percent is not None:
        percent = max(0, min(100, float(percent)))
    return {
        "id": str(entry.get("id") or f"manual-{index + 1}"),
        "label": label,
        "limitId": str(entry.get("limitId") or f"manual-{index + 1}"),
        "limitName": entry.get("limitName") or label,
        "window": entry.get("window"),
        "usedPercent": 100 - percent if percent is not None else None,
        "remainingPercent": percent,
        "remainingLabel": entry.get("remainingLabel"),
        "resetsAt": entry.get("resetsAt") or entry.get("resetAt"),
        "resetLabel": entry.get("resetLabel"),
        "source": "manual",
        "status": "available" if percent is not None else "partial",
        "note": entry.get("note") or "Read from the optional manual quota file.",
    }


def find_codex_executable() -> Path | None:
    configured = os.environ.get("CODEX_QUOTA_CODEX_EXE") or os.environ.get("CODEX_CLI")
    local_app_data = os.environ.get("LOCALAPPDATA")
    candidates = [
        Path(configured).expanduser() if configured else None,
        Path.home() / ".codex" / "plugins" / ".plugin-appserver" / "codex.exe",
        Path(local_app_data) / "OpenAI" / "Codex" / "bin" / "codex.exe" if local_app_data else None,
    ]
    path_candidate = shutil.which("codex") or shutil.which("codex.exe")
    if path_candidate:
        candidates.append(Path(path_candidate))
    for candidate in candidates:
        if candidate and candidate.is_file():
            return candidate
    return None


def app_server_request(executable: Path, method: str, params: Any) -> dict[str, Any]:
    process = subprocess.Popen(
        [str(executable), "app-server", "--stdio"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )
    messages: queue.Queue[dict[str, Any]] = queue.Queue()

    def read_stdout() -> None:
        assert process.stdout is not None
        for line in process.stdout:
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(payload, dict):
                messages.put(payload)

    threading.Thread(target=read_stdout, daemon=True).start()

    def send(payload: dict[str, Any]) -> None:
        if process.stdin is None:
            raise RuntimeError("Codex app-server stdin is unavailable.")
        process.stdin.write(json.dumps(payload, ensure_ascii=False) + "\n")
        process.stdin.flush()

    deadline = time.monotonic() + APP_SERVER_TIMEOUT_SECONDS
    try:
        send({
            "id": 1,
            "method": "initialize",
            "params": {
                "clientInfo": {
                    "name": PLUGIN_NAME,
                    "title": "Codex Quota Float",
                    "version": "0.1.0",
                },
                "capabilities": {"experimentalApi": True},
            },
        })
        while time.monotonic() < deadline:
            try:
                response = messages.get(timeout=max(0.1, deadline - time.monotonic()))
            except queue.Empty as exc:
                raise TimeoutError("Codex app-server initialization timed out.") from exc
            if response.get("id") == 1:
                if response.get("error"):
                    raise RuntimeError(f"Codex app-server initialization failed: {response['error']}")
                break
        else:
            raise TimeoutError("Codex app-server initialization timed out.")

        send({"id": 2, "method": method, "params": params})
        while time.monotonic() < deadline:
            try:
                response = messages.get(timeout=max(0.1, deadline - time.monotonic()))
            except queue.Empty as exc:
                raise TimeoutError(f"Codex app-server request timed out: {method}") from exc
            if response.get("id") != 2:
                continue
            if response.get("error"):
                raise RuntimeError(f"Codex app-server request failed: {response['error']}")
            result = response.get("result")
            if not isinstance(result, dict):
                raise RuntimeError("Codex app-server returned an invalid quota response.")
            return result
        raise TimeoutError(f"Codex app-server request timed out: {method}")
    finally:
        try:
            if process.stdin:
                process.stdin.close()
        except OSError:
            pass
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()


def window_label(minutes: int | None) -> str:
    if not minutes:
        return "\u989d\u5ea6\u5468\u671f"
    if minutes % 10080 == 0:
        return f"{minutes // 10080}\u5468"
    if minutes % 1440 == 0:
        return f"{minutes // 1440}\u5929"
    if minutes % 60 == 0:
        return f"{minutes // 60}\u5c0f\u65f6"
    return f"{minutes}\u5206\u949f"


def reset_label(timestamp: int | None) -> str | None:
    if timestamp is None:
        return None
    value = dt.datetime.fromtimestamp(timestamp).astimezone()
    return f"{value.month}\u6708{value.day}\u65e5 {value:%H:%M}\u91cd\u7f6e"


def normalize_official_limits(payload: dict[str, Any], source: str) -> tuple[list[dict[str, Any]], str | None]:
    snapshots: list[tuple[str, dict[str, Any]]] = []
    by_limit_id = payload.get("rateLimitsByLimitId")
    if isinstance(by_limit_id, dict) and by_limit_id:
        ordered = sorted(by_limit_id.items(), key=lambda item: (0 if item[0] == "codex" else 1, str(item[0])))
        snapshots.extend((str(limit_id), value) for limit_id, value in ordered if isinstance(value, dict))
    elif isinstance(payload.get("rateLimits"), dict):
        snapshot = payload["rateLimits"]
        snapshots.append((str(snapshot.get("limitId") or "codex"), snapshot))

    limits: list[dict[str, Any]] = []
    plan: str | None = None
    for limit_id, snapshot in snapshots:
        plan = plan or snapshot.get("planType")
        limit_name = snapshot.get("limitName") or "Codex"
        for bucket_name in ("primary", "secondary"):
            bucket = snapshot.get(bucket_name)
            if not isinstance(bucket, dict) or bucket.get("usedPercent") is None:
                continue
            used = max(0, min(100, int(bucket["usedPercent"])))
            remaining = 100 - used
            duration = bucket.get("windowDurationMins")
            resets_at = bucket.get("resetsAt")
            period = window_label(int(duration) if duration is not None else None)
            limits.append({
                "id": f"{limit_id}-{bucket_name}",
                "label": f"{limit_name} \u00b7 {period}",
                "limitId": limit_id,
                "limitName": limit_name,
                "window": period,
                "windowDurationMins": duration,
                "usedPercent": used,
                "remainingPercent": remaining,
                "remainingLabel": f"\u5269\u4f59 {remaining}%",
                "resetsAt": iso_from_ts(resets_at),
                "resetLabel": reset_label(int(resets_at)) if resets_at is not None else None,
                "source": source,
                "status": "available" if source == "official-app-server" else "stale",
                "note": "Returned by the official Codex account/rateLimits/read method.",
            })
    return limits, plan


def read_cached_snapshot(cache_path: Path) -> tuple[list[dict[str, Any]], str | None, str | None]:
    try:
        cached = json.loads(cache_path.read_text(encoding="utf-8"))
        payload = cached.get("payload") if isinstance(cached, dict) else None
        if isinstance(payload, dict):
            limits, plan = normalize_official_limits(payload, "official-app-server-cache")
            if limits:
                return limits, plan, cached.get("fetchedAt")
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        pass
    return [], None, None


def read_official_rate_limits(cache_path: Path) -> tuple[list[dict[str, Any]], str | None, str, list[str]]:
    warnings: list[str] = []
    executable = find_codex_executable()
    try:
        if executable is None:
            raise FileNotFoundError("No callable Codex executable was found.")
        payload = app_server_request(executable, "account/rateLimits/read", None)
        limits, plan = normalize_official_limits(payload, "official-app-server")
        if not limits:
            raise RuntimeError("Codex returned a quota response with no displayable windows.")
    except Exception as exc:
        warnings.append(f"Live official quota request failed: {exc}")
        cached_limits, cached_plan, fetched_at = read_cached_snapshot(cache_path)
        if cached_limits:
            warnings.append(f"Showing the last official snapshot from {fetched_at or 'an unknown time'}.")
            return cached_limits, cached_plan, "official-app-server-cache", warnings
        return [], None, "not_found", warnings

    try:
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        cache_path.write_text(
            json.dumps({"fetchedAt": iso_from_ts(time.time()), "payload": payload}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    except OSError as exc:
        warnings.append(f"Could not write the official quota cache: {exc}")
    return limits, plan, "official-app-server", warnings


def collect_status(args: argparse.Namespace) -> dict[str, Any]:
    now = int(time.time())
    config_path = Path(getattr(args, "config", None) or os.environ.get("CODEX_QUOTA_FLOAT_CONFIG") or DEFAULT_CONFIG).expanduser()
    cache_path = Path(getattr(args, "cache", None) or os.environ.get("CODEX_QUOTA_FLOAT_CACHE") or DEFAULT_CACHE).expanduser()

    warnings: list[str] = []
    manual_config: dict[str, Any] | None = None
    try:
        manual_config = load_manual_config(config_path)
    except Exception as exc:
        warnings.append(f"Could not read the optional manual quota file: {exc}")

    official_limits, official_plan, official_source, official_warnings = read_official_rate_limits(cache_path)
    warnings.extend(official_warnings)

    manual_limits: list[dict[str, Any]] = []
    if manual_config:
        entries = manual_config.get("limits", [])
        if isinstance(entries, list):
            manual_limits = [normalized_manual_limit(entry, index) for index, entry in enumerate(entries) if isinstance(entry, dict)]
        else:
            warnings.append("The limits field in the manual quota file must be an array.")

    if official_limits:
        limits = official_limits
        official_status = "available" if official_source == "official-app-server" else "stale"
        official_note = (
            "Read live through the official Codex account/rateLimits/read method."
            if official_status == "available"
            else "The live request failed; showing the last successful official snapshot."
        )
    elif manual_limits:
        limits = manual_limits
        official_source = "manual"
        official_status = "available"
        official_note = "Using the optional manual quota file."
    else:
        limits = [{
            "id": "official-codex-quota",
            "label": "Codex official quota",
            "limitId": "codex",
            "limitName": "Codex",
            "window": None,
            "usedPercent": None,
            "remainingPercent": None,
            "remainingLabel": "not visible",
            "resetsAt": None,
            "resetLabel": None,
            "source": "official-app-server",
            "status": "unavailable",
            "note": "Codex official quota request failed and no fallback is available.",
        }]
        official_status = "unavailable"
        official_note = "The official quota request failed and no cached value is available."

    return {
        "plugin": PLUGIN_NAME,
        "generatedAt": iso_from_ts(now),
        "plan": official_plan or ((manual_config or {}).get("plan") if manual_config else None),
        "officialQuota": {"status": official_status, "source": official_source, "note": official_note},
        "limits": limits,
        "warnings": warnings,
        "privacy": {
            "readsAuthFile": False,
            "readsTaskContent": False,
            "networkBind": "127.0.0.1 only when the optional browser panel is started",
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Collect official Codex quota status.")
    parser.add_argument("--config", help="Path to an optional manual quota override.")
    parser.add_argument("--cache", help="Path to the last successful official quota snapshot.")
    parser.add_argument("--pretty", action="store_true", help="Pretty-print JSON.")
    args = parser.parse_args()
    print(json.dumps(collect_status(args), ensure_ascii=False, indent=2 if args.pretty else None))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
