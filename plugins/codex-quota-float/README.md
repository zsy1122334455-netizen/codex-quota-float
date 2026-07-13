# Codex Quota Float

Codex Quota Float is a local Codex plugin that keeps the official remaining quota visible in an always-on-top Windows widget.

It reads the same official quota snapshot used by the Codex account menu through `account/rateLimits/read`. The widget shows:

- Remaining percentage for each Codex quota window.
- Quota period and reset date/time.
- Additional model-specific quota buckets when Codex returns them.
- A clearly marked cached value when a live refresh temporarily fails.

The plugin does not read `~/.codex/auth.json` and does not estimate official quota from local Token usage.

## Desktop widget

Start the widget:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start_float.ps1
```

The widget starts as a compact 64 px quota ring. Single-click it to expand a 244 x 64 px summary containing only the shared Codex quota, reset time, and data freshness. Model-specific buckets appear only in the double-click detail window. Dragging never toggles the view, and the widget remembers its screen position.

Stop it:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\stop_float.ps1
```

## Other commands

```powershell
python .\scripts\collect_status.py --pretty
python .\scripts\render_panel.py
python .\scripts\panel_server.py
```

The optional browser panel runs at `http://127.0.0.1:17447/`.

## Data source fallback

The last successful official snapshot is cached at `~/.codex/quota-float-cache.json`. A cached value is always labeled as cached. A manual `~/.codex/quota-float.json` remains available only as a final fallback.
