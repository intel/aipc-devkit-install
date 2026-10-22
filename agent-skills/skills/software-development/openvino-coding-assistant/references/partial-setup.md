# Partial Continue setup

Paths below are relative to the skill directory (`openvino-coding-assistant`), not to this file. Do not search the disk. The full commands are in `SKILL.md`.

Never call `ovms_agentic_setup.ps1` directly.

## OVMS only (port 8000)

Skip this when port 8000 already lists Muse-Glimmer or Qwen3.6. Download Qwen3.6 only when neither is listed.

```powershell
..\..\..\scripts\windows\invoke-ovms-agentic-setup.ps1 -Approve -Pull `
  -Model 'OpenVINO/Qwen3.6-35B-A3B-int4-ov' -Target GPU -Port 8000
```

## Continue config only (OVMS already on port 8000)

```powershell
..\..\..\scripts\windows\configure-continue-ovms.ps1 -Approve -Apply
```

Staged diff only (no write):

```powershell
..\..\..\scripts\windows\configure-continue-ovms.ps1 -Approve
```

Continue uses the same OVMS endpoint as Hermes on port **8000**. The config uses the model id already advertised there (Muse-Glimmer or Qwen3.6).
