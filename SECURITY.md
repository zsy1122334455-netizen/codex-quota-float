# Security Policy

## Reporting a vulnerability

Please use a private GitHub security advisory after the repository is published. Do not include account identifiers, authentication data, or full quota response payloads in a public issue.

## Security boundaries

- The browser panel is loopback-only (`127.0.0.1`).
- The plugin does not read Codex authentication files or task content.
- Quota values are display-only; the plugin does not change account settings or rate limits.

This is a preview project that depends on an experimental Codex method. Review release notes before upgrading if the upstream response format changes.
