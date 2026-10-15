---
name: intel-devkit-verify
description: >-
  Check whether the Intel AI PC Developer Kit, OpenVINO GenAI, and OpenVINO Model Server (OVMS) are ready on Windows for a local chat model. Use before installing the Dev Kit, starting OVMS, or connecting Hermes or another agent to local models. Read-only: it does not install software or download weights. If the user asked only for a check, report the result and stop. Follow next_skill only when their request includes that next step. Not for installing OVMS, switching Hermes off the cloud, or VS Code Continue.
license: MIT
compatibility: Windows (PowerShell). Intel AI PC Developer Kit recommended. No network required.
metadata:
  intel.skill_id: intel-devkit-verify
  intel.skill_version: "0.1.0"
  intel.risk_class: read
---

# intel-devkit-verify

Inspect the Windows machine. Do not install software or download models.

From the **`agent-skills`** repository root:

```powershell
.\scripts\windows\invoke-devkit-verify.ps1
```

Parse JSON stdout (`skill-result-2026-08`). Do not paste `scripts\windows\*.ps1` paths.

## What to tell the user

Reply with **`user_message`** only.

If the user asked only for this check, stop. Do not mention **`next_skill`**.

If the user's request includes the next step, follow **`next_skill`** and still say only **`user_message`**.

If the user asks for verbose output, what happened, or why it failed, then include warnings, checks, and **`diagnostics`**.

## Hand off

Follow **`next_skill`** only when the user's request includes that step:

| `next_skill` | When |
|---|---|
| `intel-devkit-install` | Dev Kit absent, or **V3** (OpenVINO GenAI) failed or skipped |
| `intel-devkit-ovms-slice-fetch` | V3 passed, V4 failed, and `ovms_agentic_setup.ps1` is missing under the install root |
| `intel-ovms-agentic-setup` | GenAI is ready but the OVMS runtime, server, or model is not |
| `intel-agent-provider-config` | Verification passed and **`agent_inference_ready`** is true |

Setup_1/2 do not install OVMS. Do not run `intel-devkit-install` for a V4-only gap. If **`next_skill`** is **`intel-ovms-agentic-setup`** and **`agent_inference_ready`** is false, use **`-Profile agent`** when the user wants local agent chat, not another install. OVMS running does not switch Hermes or OpenClaw.

Check ids are in [references/checks.md](references/checks.md).

## When not to use this

Installing the Dev Kit, starting OVMS, switching the agent provider, or setting up VS Code Continue. Use the hand-off skill above. Continue on port 8000 is `openvino-coding-assistant`.
