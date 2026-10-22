---
name: intel-agent-provider-config
description: >-
  Point Hermes or OpenClaw at a local OpenVINO Model Server (OVMS) on Windows after the agent model is already being served on port 8000. Stages provider settings and returns the steps to switch the model and start a new chat. OVMS running does not switch the agent by itself. Use after intel-ovms-agentic-setup with the agent profile. Confirm chat only after the user completes that switch. Not for installing the Intel AI PC Developer Kit, launching OVMS, or VS Code Continue (openvino-coding-assistant uses the model already on port 8000).
license: MIT
compatibility: Windows (PowerShell). Intel Core Ultra (Series 3) and 64 GB+ RAM recommended for agent model. Network for optional -Pull.
metadata:
  intel.skill_id: intel-agent-provider-config
  intel.skill_version: "0.2.0"
  intel.risk_class: write-config
---

# intel-agent-provider-config

Stage local OVMS provider settings and hand the user the switch steps. Do not call `ovms_agentic_setup.ps1` directly. Do not assume the current cloud session changes provider on its own.

**Script location.** Do not search the disk for these scripts. This file is `agent-skills\skills\software-development\intel-agent-provider-config\SKILL.md`. The invokers are in `agent-skills\scripts\windows\`, which is `..\..\..\scripts\windows\` from this skill directory. Run those paths. `.\scripts\windows\...` works only when the current directory is already `agent-skills`.

## Order when the user asks for local OVMS

1. **`intel-devkit-verify`** (optional health check).
2. **`intel-ovms-agentic-setup`** with **`-Profile agent`** until the agent model is served. Use **`-ApproveStopOvms`** only after the user approves stopping a conflicting listener on port 8000. Use **`-ApproveRetryPull`** to resume or re-pull.
3. **This skill** with **`-Pull:$false`** (the default). It stages a config diff and returns **`local_provider_handoff`** (`requires_new_session`).
4. The user finishes **`hermes model`** (or reviews the staged config). Set **`model.default`** to the quoted catalog id: `hermes config set model.default "OpenVINO/Qwen3.6-35B-A3B-int4-ov"`. The short id `Qwen3.6-35B-A3B` is not accepted. Start a **new chat** and confirm it answers.

## What to tell the user

Reply with **`user_message`** only. Do not claim Hermes agent chat is ready unless **`agent_inference_ready`** is true.

If the user asked only for this step, stop when it passes. Do not mention **`next_skill`**.

If the user's request includes the next step, follow **`next_skill`** and still say only **`user_message`**.

If the user asks for verbose output, what happened, or why it failed, then include warnings, checks, **`diagnostics`**, and **`local_provider_handoff`**.

## Hermes (OVMS already serving the agent model)

```powershell
..\..\..\scripts\windows\configure-hermes-ovms.ps1 -Approve
```

Hermes, and also download or start the agent model in one flow:

```powershell
..\..\..\scripts\windows\configure-hermes-ovms.ps1 -Approve -Pull -ApproveRetryPull
```

## OpenClaw

```powershell
..\..\..\scripts\windows\configure-openclaw-ovms.ps1 -Approve
```

## Other Agent Skills hosts

```powershell
..\..\..\scripts\windows\configure-agent-provider.ps1 -TargetAgent hermes -Approve
```

Use **`-Pull`** only when the user approved network and OVMS is not already serving the agent model. The default **`-Pull:$false`** avoids a second download after `invoke-ovms-agentic-setup`. Host notes: [references/hosts.md](references/hosts.md).

## When not to use this

OVMS is not serving the agent model yet. Use **`intel-ovms-agentic-setup`** with **`-Profile agent`**. The Dev Kit or GenAI is missing. Use **`intel-devkit-install`**. VS Code Continue on port 8000 is **`openvino-coding-assistant`**.
