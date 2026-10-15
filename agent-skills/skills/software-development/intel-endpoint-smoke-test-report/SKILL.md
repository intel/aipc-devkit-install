---
name: intel-endpoint-smoke-test-report
description: >-
  Send one OpenAI-compatible chat request to a local OpenVINO Model Server (OVMS) on Windows and report whether the endpoint answered. Use after OVMS is running, usually after intel-ovms-agentic-setup and, when the agent should use that server, intel-agent-provider-config. The default endpoint is localhost port 8000. A passing smoke test shows the server responded. It does not install the Intel AI PC Developer Kit, start OVMS, or switch Hermes or OpenClaw onto that server. Not for VS Code Continue setup (openvino-coding-assistant on port 8000).
license: MIT
compatibility: Windows (PowerShell). Localhost OVMS on port 8000 by default.
metadata:
  intel.skill_id: intel-endpoint-smoke-test-report
  intel.skill_version: "0.1.0"
  intel.risk_class: read
---

# intel-endpoint-smoke-test-report

Confirm the local OVMS chat endpoint answers. Run from the **`agent-skills`** repository root, after OVMS is up:

```powershell
.\scripts\windows\endpoint-smoke-test.ps1
```

The default base URL is `http://localhost:8000/v3`. The default model is the small verify model. Pass **`-Model`** with the id from **`GET /v3/models`** when the server is on the agent model. Pass **`-BaseUrl`** only for a non-default endpoint.

## What to tell the user

Reply with **`user_message`** only. A pass means this request got a chat completion. It does not mean Hermes or OpenClaw is using the server.

If the user asked only for this check, stop. Do not mention **`next_skill`**.

If the user's request includes the next step, follow **`next_skill`** and still say only **`user_message`**.

If the user asks for verbose output, what happened, or why it failed, then include warnings, checks, and **`diagnostics`**.

Model choice notes: [references/what-it-checks.md](references/what-it-checks.md).

## Hand off

Follow **`next_skill`** only when the user's request includes that step.

## When not to use this

Installing the Dev Kit, launching OVMS, or writing Continue config. Continue on port 8000 is **`openvino-coding-assistant`**.
