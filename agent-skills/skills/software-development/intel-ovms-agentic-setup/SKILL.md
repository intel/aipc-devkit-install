---
name: intel-ovms-agentic-setup
description: >-
  Download and start OpenVINO Model Server (OVMS) on Windows for local chat on an Intel AI PC. Use after Developer Kit verification shows OpenVINO GenAI is ready, or when the user asks to install OVMS or start local inference. Use profile verify for a small smoke model and profile agent for the large Hermes chat model. A network download needs approval. If the user asked only for OVMS, stop when it is running. Continue to the provider step only when their request includes switching Hermes. Not for installing the Developer Kit (intel-devkit-install), switching the agent provider by itself, or VS Code Continue (openvino-coding-assistant on this same port 8000 model).
license: MIT
compatibility: Windows (PowerShell). Dev Kit OVMS scripts. Network for -Pull.
metadata:
  intel.skill_id: intel-ovms-agentic-setup
  intel.skill_version: "0.2.0"
  intel.risk_class: network
---

# intel-ovms-agentic-setup

Start OpenVINO Model Server for local chat. Run from a **standard-user** PowerShell at the **`agent-skills`** repository root, after Dev Kit install (see [admin-vs-user-runtime.md](../../../docs/admin-vs-user-runtime.md)). Models and cache use **`%USERPROFILE%\OVMS`** unless **`AIPC_OVMS_USE_CLONE_PATHS=1`**.

Invoke only `scripts\windows\invoke-ovms-agentic-setup.ps1`. Never call `ovms_agentic_setup.ps1` directly.

When the user asks to **install OVMS**, **start local inference**, or use the **large agent model**, use **`-Profile agent`**, not `verify`.

## Verify / smoke model

```powershell
.\scripts\windows\invoke-ovms-agentic-setup.ps1 -Approve -Pull -Profile verify
```

If OVMS is already running the correct model on port 8000 (reuse the endpoint; no second pull):

```powershell
.\scripts\windows\invoke-ovms-agentic-setup.ps1 -Approve -Profile verify
```

## Agent model (before Hermes provider handoff)

```powershell
.\scripts\windows\invoke-ovms-agentic-setup.ps1 -Approve -Pull -Profile agent
```

**`-Profile verify` success** may be **`partial`** with **`readiness_tier: smoke`** when only the small model is served. That is not agent-ready.

Another process or the wrong model holds port 8000. The user must approve stopping **ovms.exe** only:

```powershell
.\scripts\windows\invoke-ovms-agentic-setup.ps1 -Approve -Pull -Profile agent -ApproveStopOvms
```

Resume or re-pull after a partial download, or when weights already exist on disk:

```powershell
.\scripts\windows\invoke-ovms-agentic-setup.ps1 -Approve -Pull -Profile agent -ApproveRetryPull
```

OVMS is already running and only health or chat checks are needed:

```powershell
.\scripts\windows\invoke-ovms-agentic-setup.ps1 -Approve -SkipLaunch -Profile verify
```

Blocked `error.code` values are in [references/run-flags.md](references/run-flags.md).

## What to tell the user

Reply with **`user_message`** only. Do not say Hermes is on local inference unless the user finished the provider switch. OVMS up is not a provider switch.

If the user asked only for OVMS, stop when it passes. Do not mention **`next_skill`**.

If the user's request includes the provider switch, follow **`next_skill`** and still say only **`user_message`**.

If the user asks for verbose output, what happened, or why it failed, then include warnings, checks, and **`diagnostics`**.

Endpoint default: `http://localhost:8000/v3`.

## Hand off

Follow **`next_skill`** only when the user's request includes that step. A smoke-only server stays here until the user wants the agent profile.

## When not to use this

The Developer Kit or OpenVINO GenAI is missing. Use **`intel-devkit-install`**, then **`intel-devkit-verify`**. VS Code Continue on this same port 8000 model is **`openvino-coding-assistant`**.
