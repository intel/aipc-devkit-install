# Security model (MVP)

- **OpenClaw:** test/sandbox systems; local-only OVMS endpoint by default.
- **Secrets:** never commit API keys; config diffs staged before `-Apply`.
- **Skills:** treat third-party skills as untrusted code.
- **Approvals:** D7 — `read` no approval; install/write-config/network/privileged require explicit approval.

See [DECISIONS.md](planning/DECISIONS.md) D4–D5, D7.
