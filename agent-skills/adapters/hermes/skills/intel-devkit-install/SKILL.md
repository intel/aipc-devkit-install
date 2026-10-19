---
name: intel-devkit-install
description: Install or top-up the Intel AI PC Dev Kit on Windows. Use UAC elevation from a standard-user Hermes session; poll until complete. Requires user approval.
metadata:
  hermes:
    risk_class: install
    requires_elevation: uac
---

# intel-devkit-install (Hermes)

Canonical: [`skills/intel-devkit-install/SKILL.md`](../../../../skills/software-development/intel-devkit-install/SKILL.md).  
Elevation playbook: [`docs/hermes-install-elevation.md`](../../../../docs/hermes-install-elevation.md).

## Before you run

1. Confirm the user **approves** install (`-Approve` and explicit chat consent).
2. Tell the user: **Windows will show a UAC prompt — click Yes** to allow Administrator for Dev Kit setup.
3. Run from the **`agent-skills`** repository root (working directory matters).

## Start install (standard-user Hermes)

Invoke this skill with **`-Approve -Elevate`** (Hermes runs the invoker; do not tell the user to open PowerShell).

Parse JSON:

- `functional_status: partial` + `install_job.job_id` → install **in progress** (not success). Tell the user **`user_message`** only.
- `functional_status: blocked` + `UAC_DENIED` → user declined UAC; ask to retry.
- **`install_poll`** → how **you** poll: same skill with `-WaitInstallJob` and `InstallJobId`. Do **not** show `script_invocation` or `.ps1` paths to the user.

## Poll until finished

Re-invoke **`intel-devkit-install`** with **`-WaitInstallJob -InstallJobId '<job_id>'`** every few minutes (install may take **hours**).

When the poll returns **`functional_status: pass`**, tell the user **`user_message`**. Invoke **`intel-devkit-verify`** only when their request includes verification or a later step (do not run Hermes elevated for OVMS).

## Full loop (Scenario C)

`intel-devkit-verify` → this skill (`-Approve -Elevate` + poll) → `intel-devkit-verify` → `intel-ovms-agentic-setup` → `intel-agent-provider-config` → `intel-endpoint-smoke-test-report` → switch Hermes model to local OVMS (`http://localhost:8000/v3`).
