#!/usr/bin/env python3
"""Render a privacy-focused Codex quota status panel."""

from __future__ import annotations

import argparse
import html
import json
from pathlib import Path

from collect_status import collect_status


def percent_text(value: object) -> str:
    if value is None:
        return "--"
    try:
        return f"{float(value):.0f}%"
    except (TypeError, ValueError):
        return "--"


def friendly_label(item: dict) -> str:
    window = item.get("window") or "quota period"
    if item.get("limitId") == "codex":
        return f"Shared Codex quota - {window}"
    name = str(item.get("limitName") or item.get("label") or "Model")
    return f"{name} independent quota - {window}"


def build_html(status: dict) -> str:
    limits = status.get("limits", [])
    available = [item for item in limits if item.get("remainingPercent") is not None]
    shared = [item for item in available if item.get("limitId") == "codex"]
    primary = min(shared or available, key=lambda item: float(item.get("remainingPercent", 100))) if available else {}
    primary_percent = primary.get("remainingPercent")
    primary_fill = max(0, min(100, float(primary_percent))) if primary_percent is not None else 0
    official = status.get("officialQuota", {})
    source_label = {
        "official-app-server": "Official live data",
        "official-app-server-cache": "Official cached data",
        "manual": "Manual fallback",
    }.get(official.get("source"), "Unavailable")
    status_class = "live" if official.get("status") == "available" else "stale"

    rows = []
    for item in available:
        used = item.get("usedPercent")
        reset = item.get("resetLabel") or "Reset time unavailable"
        scope = "shared" if item.get("limitId") == "codex" else "independent"
        rows.append(
            '<div class="quota-row">'
            "<div>"
            f"<strong>{html.escape(friendly_label(item))}</strong>"
            f"<span>{html.escape(reset)} - {scope} bucket</span>"
            "</div>"
            '<div class="quota-value">'
            f"<strong>{html.escape(percent_text(item.get('remainingPercent')))}</strong>"
            f"<span>{html.escape(f'{used}% used' if used is not None else 'Usage unavailable')}</span>"
            "</div>"
            "</div>"
        )
    if not rows:
        rows.append('<div class="empty">No displayable official quota is currently available.</div>')

    warning_html = "".join(f"<li>{html.escape(str(item))}</li>" for item in status.get("warnings", []))
    if warning_html:
        warning_html = f"<aside><strong>Status note</strong><ul>{warning_html}</ul></aside>"

    data_json = json.dumps(status, ensure_ascii=False)
    generated_at = html.escape(str(status.get("generatedAt") or "unknown"))
    plan = html.escape(str(status.get("plan") or "unknown").upper())
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Codex Quota Float</title>
  <style>
    :root {{ color-scheme: light; font-family: "Segoe UI", sans-serif; color: #1b252b; background: #eef1f2; letter-spacing: 0; }}
    * {{ box-sizing: border-box; }}
    body {{ margin: 0; min-height: 100vh; padding: 32px 18px; background: #eef1f2; }}
    main {{ width: min(720px, 100%); margin: 0 auto; overflow: hidden; border: 1px solid #dce2e0; border-radius: 8px; background: #fcfdfd; box-shadow: 0 12px 34px rgba(27, 47, 43, .10); }}
    header {{ display: flex; align-items: flex-start; justify-content: space-between; gap: 20px; padding: 24px 26px 18px; border-bottom: 1px solid #e4e8e7; }}
    h1 {{ margin: 0; font-size: 19px; font-weight: 650; }}
    header p {{ margin: 7px 0 0; color: #6c767d; font-size: 13px; }}
    .source {{ display: inline-flex; align-items: center; gap: 7px; color: #238c72; font-size: 12px; font-weight: 650; white-space: nowrap; }}
    .source::before {{ content: ""; width: 7px; height: 7px; border-radius: 50%; background: currentColor; }}
    .source.stale {{ color: #8a9299; }}
    .hero {{ padding: 26px; }}
    .hero-grid {{ display: grid; grid-template-columns: 150px 1fr; align-items: center; gap: 24px; }}
    .big {{ font: 650 54px/1 "Segoe UI", sans-serif; }}
    .hero-copy strong {{ display: block; font-size: 16px; font-weight: 650; }}
    .hero-copy span {{ display: block; margin-top: 9px; color: #68737a; font-size: 13px; }}
    .bar {{ height: 6px; margin-top: 22px; overflow: hidden; border-radius: 3px; background: #e2e8e6; }}
    .bar i {{ display: block; width: {primary_fill}%; height: 100%; background: #238c72; }}
    section {{ padding: 0 26px 24px; }}
    section h2 {{ margin: 0 0 10px; color: #616c73; font-size: 12px; font-weight: 650; text-transform: uppercase; }}
    .quota-row {{ display: flex; align-items: center; justify-content: space-between; gap: 20px; padding: 15px 0; border-top: 1px solid #e7eae9; }}
    .quota-row strong {{ display: block; font-size: 14px; font-weight: 650; }}
    .quota-row span {{ display: block; margin-top: 5px; color: #788188; font-size: 12px; }}
    .quota-value {{ min-width: 76px; text-align: right; }}
    .quota-value strong {{ color: #238c72; font: 650 22px/1 "Segoe UI", sans-serif; }}
    .note {{ margin: 0 26px 24px; padding: 14px 16px; border-left: 3px solid #238c72; background: #f3f6f5; color: #5f6a71; font-size: 12px; line-height: 1.7; }}
    aside {{ margin: 0 26px 24px; color: #765d24; font-size: 12px; }}
    aside ul {{ margin: 7px 0 0; padding-left: 18px; }}
    .empty {{ padding: 18px 0; color: #788188; }}
    footer {{ padding: 16px 26px; border-top: 1px solid #e4e8e7; color: #7a848b; font-size: 11px; }}
    @media (max-width: 560px) {{ .hero-grid {{ grid-template-columns: 1fr; gap: 14px; }} .big {{ font-size: 46px; }} header {{ flex-direction: column; }} }}
  </style>
</head>
<body>
  <main>
    <header>
      <div><h1>Codex Quota Float</h1><p>Official quota, periods, and reset times</p></div>
      <span class="source {status_class}">{html.escape(source_label)}</span>
    </header>
    <div class="hero">
      <div class="hero-grid">
        <div class="big">{html.escape(percent_text(primary_percent))}</div>
        <div class="hero-copy">
          <strong>{html.escape(friendly_label(primary) if primary else 'Official Codex quota')}</strong>
          <span>{html.escape(primary.get('resetLabel') or official.get('note') or 'Reset time unavailable')}</span>
        </div>
      </div>
      <div class="bar"><i></i></div>
    </div>
    <section><h2>Official quota buckets</h2>{''.join(rows)}</section>
    <div class="note">The model selector is not a quota list. This plugin only displays buckets explicitly returned by Codex. It does not read authentication files, task titles, or conversation content.</div>
    {warning_html}
    <footer>Updated: {generated_at} - Plan: {plan}</footer>
  </main>
  <script type="application/json" id="quota-data">{html.escape(data_json)}</script>
</body>
</html>"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Render the Codex quota panel.")
    parser.add_argument("--output", default=str(Path.home() / "plugins" / "codex-quota-float" / "work" / "quota-panel.html"))
    parser.add_argument("--config")
    parser.add_argument("--cache")
    args = parser.parse_args()
    status = collect_status(args)
    output = Path(args.output).expanduser()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(build_html(status), encoding="utf-8")
    print(json.dumps({"output": str(output), "status": status["officialQuota"], "generatedAt": status["generatedAt"]}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
