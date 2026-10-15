---
skill_id: intel-devkit-install
version: 0.1.0
owner: aipc-agent-skills
risk_class: install
approval_mode: required
supported_os: [windows]
platforms: [hermes, openclaw]
agent_skills_standard: true
hardware_fit_card: docs/recommended-hardware.md
recommended_hardware:
  processor: "Intel® Core™ Ultra (Series 3)"
  memory_gb_min: 64
deck_alias: [devkit-install-verify-agent]
invoke:
  windows_script: scripts/windows/invoke-devkit-install.ps1
---

# intel-devkit-install

Wraps `Setup_1.ps1 install` with approval, preflight (I1), invoke (I2), state (I3), and JSON reporting.

## Invoke

```powershell
# Hermes / standard-user agent (UAC elevation + poll)
.\scripts\windows\invoke-devkit-install.ps1 -Approve -Elevate
.\scripts\windows\invoke-devkit-install.ps1 -WaitInstallJob -InstallJobId '<job_id>'

# Already-elevated or manual Admin session
.\scripts\windows\invoke-devkit-install.ps1 -Approve
.\scripts\windows\invoke-devkit-install.ps1 -Approve -PreflightOnly
```

See [hermes-install-elevation.md](../docs/hermes-install-elevation.md).

Default **`install`** runs **`Setup_1.ps1 install`** then **`Setup_2.ps1`** (OpenVINO GenAI under **`C:\Intel\openvino_genai`** by default). Setup_1 uses a child `powershell.exe` (`-ExecutionPolicy Bypass`). **`-SkipSetup2`** for winget only; **`-Setup2Only`** if Setup_1 already completed; **`-ForceSetup2`** to re-download GenAI content. **`-SetupCommand gui`** skips Setup_2 unless you run Setup_2 separately. OVMS: **`intel-ovms-agentic-setup`** after install.

Requires **Administrator** for Setup_1/2. **Hermes:** use **`-Approve -Elevate`** from a standard-user session (UAC), then **`-WaitInstallJob`**. Do not require a manual elevated PowerShell. Already-elevated sessions may omit **`-Elevate`**. OVMS: **`intel-ovms-agentic-setup`** after install, as **standard user**.

## Recommended hardware

Intel® Core™ Ultra (Series 3), **≥ 64 GB** RAM — [`docs/recommended-hardware.md`](../docs/recommended-hardware.md).

## Preflight

Admin, disk, network; `-Approve` required.

## Known failures

- Long runtime vs agent timeout — install runs in detached elevated window; agent **polls** `-WaitInstallJob` (see [hermes-install-elevation.md](../docs/hermes-install-elevation.md))
- Partial uninstall requiring user interaction
