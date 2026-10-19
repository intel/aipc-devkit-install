---
name: openvino-coding-assistant
description: >-
  Set up a local coding assistant in VS Code Continue on Windows, served by the same OpenVINO Model Server (OVMS) model as intel-ovms-agentic-setup: Qwen3.6 35B (OpenVINO/Qwen3.6-35B-A3B-int4-ov) on port 8000. Use when the user wants that model inside VS Code Continue. Needs VS Code with the Continue extension and the Dev Kit OVMS scripts. Not for Cursor, Hermes, or OpenClaw provider setup (intel-agent-provider-config), and not for installing the Developer Kit (intel-devkit-install).
license: MIT
compatibility: Windows (PowerShell). Intel Core Ultra Series 3 with at least 64 GB RAM recommended for Qwen3.6 35B. Network for OVMS -Pull.
metadata:
  intel.skill_id: openvino-coding-assistant
  intel.skill_version: "0.2.0"
  intel.scope: lite
  intel.risk_class: write-config
---

# openvino-coding-assistant

Set up **VS Code + Continue** against the local OVMS agent model, aligned with [Visual Studio Code Local Assistant (2026)](https://docs.openvino.ai/2026/model-server/ovms_demos_code_completion_vsc.html).

**Not this skill:** Cursor, Hermes, or OpenClaw. Those use `intel-agent-provider-config` on the same port **8000** server.

## Defaults

| Setting | Value |
|---------|--------|
| OVMS catalog model | `OpenVINO/Qwen3.6-35B-A3B-int4-ov` (same as OVMS agentic setup) |
| API model id (`GET /v3/models`) | `Qwen3.6-35B-A3B` |
| OVMS port | **8000** (`http://localhost:8000/v3`) |
| Target device | GPU |

Continue uses the same OVMS server as Hermes on port **8000**. Do not stop that server.

## Full setup (OVMS + Continue config)

From the **`agent-skills`** root as a **standard user**:

```powershell
.\scripts\windows\invoke-openvino-coding-assistant-setup.ps1 -Approve -Pull -Apply
```

- **`-Approve`** — required for OVMS launch, optional `-Pull`, and the Continue config write.
- **`-Pull`** — download Qwen3.6 35B weights if they are not already on disk (network).
- **`-Apply`** — merge into `%USERPROFILE%\.continue\config.yaml` (backup `config.yaml.bak.<timestamp>`). Does **not** change Continue’s default model. The user selects **OVMS Qwen3.6-35B-A3B** in Continue.

If port **8000** is held by the wrong OVMS model:

```powershell
.\scripts\windows\invoke-openvino-coding-assistant-setup.ps1 -Approve -Pull -Apply -ApproveStopOvms
```

Resume or re-pull:

```powershell
.\scripts\windows\invoke-openvino-coding-assistant-setup.ps1 -Approve -Pull -Apply -ApproveRetryPull
```

OVMS-only and Continue-only commands are in [references/partial-setup.md](references/partial-setup.md). The config fragment is [references/continue-ovms-coder-model.yaml](references/continue-ovms-coder-model.yaml).

## After apply

1. Reload VS Code (**Developer: Reload Window**).
2. Open Continue and choose **OVMS Qwen3.6-35B-A3B** (it is not the automatic default).
3. Chat or edit. Turn on autocomplete in Continue if you want it (the UI default is off).

## Verify

- `GET http://localhost:8000/v3/models` includes **`Qwen3.6-35B-A3B`**.
- Continue chat returns a completion. Do not claim it works until the user tries.

## What to tell the user

Reply with **`user_message`** only.

If the user asked only for Continue, stop when it passes. Do not mention **`next_skill`**.

If the user's request includes the next step, follow **`next_skill`** and still say only **`user_message`**.

If the user asks for verbose output, what happened, or why it failed, then include warnings, checks, and **`diagnostics`**.

## When the Dev Kit is missing

Run **`intel-devkit-verify`**. If GenAI is missing, **`intel-devkit-install`**, then return here. Do not use this skill to switch Hermes.
