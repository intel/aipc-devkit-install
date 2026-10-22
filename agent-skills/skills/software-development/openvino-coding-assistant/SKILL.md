---
name: openvino-coding-assistant
description: >-
  Set up a local coding assistant in VS Code Continue on Windows, using the OpenVINO Model Server (OVMS) model already on port 8000. Accept OpenVINO/Muse-Glimmer-30B-int4-ov or OpenVINO/Qwen3.6-35B-A3B-int4-ov. Do not replace a running Muse-Glimmer or Qwen3.6 server. Download Qwen3.6 only when neither model is advertised. Needs VS Code with the Continue extension and the Dev Kit OVMS scripts. Not for Cursor, Hermes, or OpenClaw provider setup (intel-agent-provider-config), and not for installing the Developer Kit (intel-devkit-install).
license: MIT
compatibility: Windows (PowerShell). Intel Core Ultra Series 3 with at least 64 GB RAM recommended for these local models. Network only when OVMS must download Qwen3.6.
metadata:
  intel.skill_id: openvino-coding-assistant
  intel.skill_version: "0.2.0"
  intel.scope: lite
  intel.risk_class: write-config
---

# openvino-coding-assistant

Set up **VS Code + Continue** against the OVMS model already on port **8000**, aligned with [Visual Studio Code Local Assistant (2026)](https://docs.openvino.ai/2026/model-server/ovms_demos_code_completion_vsc.html).

**Not this skill:** Cursor, Hermes, or OpenClaw. Those use `intel-agent-provider-config` on the same port **8000** server.

## Models

Use whichever of these `GET /v3/models` already lists. Do not stop that server and do not download the other model.

| Catalog id | Typical API id |
|------------|----------------|
| `OpenVINO/Muse-Glimmer-30B-int4-ov` | `Muse-Glimmer-30B` |
| `OpenVINO/Qwen3.6-35B-A3B-int4-ov` | `Qwen3.6-35B-A3B` |

Port **8000** (`http://localhost:8000/v3`). Target device **GPU** when a download is required.

Continue uses the same OVMS server as Hermes. Leave it running.

## Full setup (OVMS + Continue config)

From the **`agent-skills`** root as a **standard user**.

When Muse-Glimmer or Qwen3.6 is already listed, do not pass **`-Pull`** or **`-ApproveStopOvms`**:

```powershell
.\scripts\windows\invoke-openvino-coding-assistant-setup.ps1 -Approve -Apply
```

When neither model is listed, download Qwen3.6:

```powershell
.\scripts\windows\invoke-openvino-coding-assistant-setup.ps1 -Approve -Pull -Apply
```

- **`-Approve`** — required for an OVMS launch and the Continue config write.
- **`-Pull`** — download Qwen3.6 only when neither accepted model is already on port 8000.
- **`-Apply`** — merge into `%USERPROFILE%\.continue\config.yaml` (backup `config.yaml.bak.<timestamp>`). Does **not** change Continue’s default model. The user selects the OVMS entry for the model that is serving.

If port **8000** is held by a model that is neither Muse-Glimmer nor Qwen3.6:

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
2. Open Continue and choose the **OVMS** entry for the model that is serving (it is not the automatic default).
3. Chat or edit. Turn on autocomplete in Continue if you want it (the UI default is off).

## Verify

- `GET http://localhost:8000/v3/models` includes **Muse-Glimmer** or **Qwen3.6-35B-A3B**.
- Continue chat returns a completion. Do not claim it works until the user tries.

## What to tell the user

Reply with **`user_message`** only.

If the user asked only for Continue, stop when it passes. Do not mention **`next_skill`**.

If the user's request includes the next step, follow **`next_skill`** and still say only **`user_message`**.

If the user asks for verbose output, what happened, or why it failed, then include warnings, checks, and **`diagnostics`**.

## When the Dev Kit is missing

Run **`intel-devkit-verify`**. If GenAI is missing, **`intel-devkit-install`**, then return here. Do not use this skill to switch Hermes.
