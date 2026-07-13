---
name: codex-quota-float
description: Check official Codex remaining quota percentages and reset times, or open the always-on-top quota widget. Use when the user asks about Codex quota, remaining usage, rate limits, reset time, or the quota panel.
---

# Codex Quota Float

Use this skill when the user asks to check Codex quota, remaining usage, rate limits, reset time, or the local quota panel.

## Rules

- Prefer `codex_quota_status` for a textual status check.
- Use `codex_quota_start_float` when the user wants the desktop widget. It starts as a compact 64 px quota ring, expands on single-click, remembers its position, refreshes silently about once per minute, and never opens details automatically. Details open only after the user double-clicks the widget; a right-click menu is also available.
- Use `codex_quota_render_panel` for a static HTML snapshot or `codex_quota_start_panel` for the live browser panel.
- Treat `official-app-server` as a live official value from `account/rateLimits/read`.
- Treat `official-app-server-cache` as stale and clearly say that the last successful official value is being shown.
- Treat the generic `codex` bucket as shared quota. Treat additional buckets as independently metered model quota, not as proof that the user is currently using that model. Do not imply that every selectable model has a separate percentage.
- Never present local Token activity as official remaining quota.
- Do not read `~/.codex/auth.json`.
- Do not read task titles, task databases, logs, prompts, or conversation content.
- The optional browser panel is loopback-only and must bind to `127.0.0.1`.

## Fallbacks

The collector caches the last successful official snapshot in `~/.codex/quota-float-cache.json`. A user-provided `~/.codex/quota-float.json` is only a final fallback when neither the live request nor the official cache is available.
