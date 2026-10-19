---
name: intel-devkit-install
description: >-
  Install or top up the Intel AI PC Developer Kit on Windows when verification says the kit is missing or OpenVINO GenAI is incomplete, and the user approves the system change. On Hermes, run as a standard user so Windows UAC can request Administrator, then poll until the installer job finishes. This setup does not install OpenVINO Model Server (OVMS). If the user asked only for the Dev Kit, stop when install passes. Continue only when their request includes a later step. Not for starting OVMS, downloading a chat model, switching Hermes to local inference, or the VS Code Continue coding assistant.
license: MIT
compatibility: Windows (PowerShell). Administrator and network may be required. User approval required.
metadata:
  intel.skill_id: intel-devkit-install
  intel.skill_version: "0.1.0"
  intel.risk_class: install
---

# intel-devkit-install

Install or top up the Intel AI PC Developer Kit. Run only after `intel-devkit-verify` reports the kit absent or OpenVINO GenAI (V3) failed, and the user approves the change.

From the **`agent-skills`** repository root. Do not paste `.ps1` paths to the user.

## What to tell the user

Reply with **`user_message`** only.

If the user asked only for this step, stop when it passes. Do not mention **`next_skill`**.

If the user's request includes the next step, follow **`next_skill`** and still say only **`user_message`**.

If the user asks for verbose output, what happened, or why it failed, then include warnings, checks, and **`diagnostics`**.

## Hermes / standard-user agent (UAC)

Tell the user Windows will show a UAC prompt and they should click **Yes**. Then start the install with **`-Approve -Elevate`**:

```powershell
.\scripts\windows\invoke-devkit-install.ps1 -Approve -Elevate
```

`functional_status: partial` with `install_job.phase` **`running`** means the install is in progress, not finished. Poll by re-invoking this skill with **`-WaitInstallJob -InstallJobId`** from JSON **`install_job`** / **`install_poll`**:

```powershell
.\scripts\windows\invoke-devkit-install.ps1 -WaitInstallJob -InstallJobId '<job_id>'
```

Repeat until `functional_status` is **`pass`** or **`fail`**. **`UAC_DENIED`** means the user declined UAC; ask to retry. Elevation details: [hermes-install-elevation.md](../../../docs/hermes-install-elevation.md).

When the poll returns **`pass`**, tell the user **`user_message`**. Invoke **`intel-devkit-verify`** only when their request includes verification or a later step. Do not run Hermes elevated for OVMS.

## Already an Administrator

```powershell
.\scripts\windows\invoke-devkit-install.ps1 -Approve
```

Preflight only (no install):

```powershell
.\scripts\windows\invoke-devkit-install.ps1 -Approve -PreflightOnly
```

Setup_2 choices, `-InstallRoot`, and `-DevKitWorkingDir` are in [references/setup-flags.md](references/setup-flags.md).

## Hand off

Setup_1/2 do not install OVMS. Follow **`next_skill`** only when the user's request includes that step. See [admin-vs-user-runtime.md](../../../docs/admin-vs-user-runtime.md).

## When not to use this

The user asked only to install OVMS or start the model server. Use **`intel-ovms-agentic-setup`** with **`-Profile agent`**. Switching Hermes or OpenClaw is **`intel-agent-provider-config`**. VS Code Continue is **`openvino-coding-assistant`**.
