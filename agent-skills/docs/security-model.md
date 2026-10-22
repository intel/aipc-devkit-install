# Security model (MVP)

- **OpenClaw:** test/sandbox systems; local-only OVMS endpoint by default.
- **Secrets:** never commit API keys; config diffs staged before `-Apply`.
- **Skills:** treat third-party skills as untrusted code.
- **Approvals:** `read` needs no approval; install, write-config, network, and privileged skills require explicit approval.
