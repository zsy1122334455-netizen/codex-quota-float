# Privacy

Codex Quota Float is designed to show quota with the smallest practical data surface.

## Data read

- The plugin starts the local Codex app-server and calls `account/rateLimits/read`.
- Codex handles the existing signed-in session. The plugin does not open or parse `~/.codex/auth.json`.
- The plugin does not read Codex task databases, task titles, prompts, conversation content, logs, or local token activity.

## Data written

- `~/.codex/quota-float-cache.json`: last successful official quota response.
- `~/.codex/quota-float-position.json`: widget position.
- `~/.codex/quota-float-widget.pid`: widget process identifier.
- `~/.codex/quota-float-widget.log`: widget runtime errors, if any.

The optional manual fallback is read from `~/.codex/quota-float.json` only when no live or cached official quota is available.

## Network behavior

The plugin does not send data to a third-party service. The Codex app-server may communicate with OpenAI using the user's existing Codex session. The optional browser panel is forced to `127.0.0.1` and is not exposed to the local network.

## Removing local data

Stop the widget and delete the `quota-float-*` files listed above from `~/.codex`.
