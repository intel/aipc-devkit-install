# Partial Continue setup

Run from the `agent-skills` repository root. The full `-Approve -Pull -Apply` command is in `SKILL.md`.

Never call `ovms_agentic_setup.ps1` directly.

## OVMS only (port 8000)

Same model as `intel-ovms-agentic-setup` profile **agent**. Skip this if that server is already listing Qwen3.6 35B.

```powershell
.\scripts\windows\invoke-ovms-agentic-setup.ps1 -Approve -Pull `
  -Model 'OpenVINO/Qwen3.6-35B-A3B-int4-ov' -Target GPU -Port 8000
```

## Continue config only (OVMS already on port 8000)

```powershell
.\scripts\windows\configure-continue-ovms.ps1 -Approve -Apply
```

Staged diff only (no write):

```powershell
.\scripts\windows\configure-continue-ovms.ps1 -Approve
```

Continue uses the same OVMS endpoint as Hermes and OpenClaw: port **8000** and **`OpenVINO/Qwen3.6-35B-A3B-int4-ov`**.
