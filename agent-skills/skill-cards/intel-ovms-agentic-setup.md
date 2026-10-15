---
skill_id: intel-ovms-agentic-setup
version: 0.3.0
owner: aipc-agent-skills
risk_class: network
approval_mode: required
supported_os: [windows]
platforms: [hermes, openclaw]
agent_skills_standard: true
deck_alias: [ovms-serve-local-model]
validated_models: [OpenVINO/Qwen3.5-0.8B-int4-ov]
model_profiles:
  verify: OpenVINO/Qwen3.5-0.8B-int4-ov
  agent: OpenVINO/Qwen3.6-35B-A3B-int4-ov
hardware_fit_card: docs/recommended-hardware.md
recommended_hardware:
  processor: "Intel® Core™ Ultra (Series 3)"
  memory_gb_min: 64
ovms_contract:
  base_url: http://localhost:8000/v3
  models_path: /v3/models
  chat_path: /v3/chat/completions
invoke:
  windows_script: scripts/windows/invoke-ovms-agentic-setup.ps1
---

# intel-ovms-agentic-setup

Starts agentic OVMS via `ovms_agentic_setup.ps1`.

**Profile `verify` (D1):** `-Profile verify` → `OpenVINO/Qwen3.5-0.8B-int4-ov`, `-Target CPU`, optional `-Pull`.

**Profile `agent` (D9):** **Qwen 3.6 35B A3B (OpenVINO)** — prefer `configure-hermes-ovms.ps1` / `configure-openclaw-ovms.ps1` (pull + provider). Direct: `-Profile agent -Approve -Pull` (defaults **GPU**). Model id may change per D9; override with `-Model`.

## Parameters (Windows script)

| Flag | Purpose |
|------|---------|
| `-Approve` | Required (network risk class) |
| `-Pull` | Pass `-Pull` to `ovms_agentic_setup.ps1` (disk preflight, pull lock) |
| `-ApproveRetryPull` | Required for resume/re-pull when partial or model on disk |
| `-ApproveStopOvms` | Stop **ovms.exe** on port conflict after user approval |
| `-MinFreeDiskGb` | Override model-specific free-space threshold |
| `-SkipLaunch` | Health/chat only when OVMS already on `:8000` |
| `-RunToolTest` | Force O3 `-Test` (default on `-Profile verify`) |

**Agentic inference:** JSON includes **`A1-agentic-inference`**, **`agent_inference_ready`**, **`readiness_tier`**. `-Profile verify` may end **`partial`** (smoke only); use **`-Profile agent`** for Hermes large-model chat.

## Known failures

| Check | Symptom | Remediation |
|-------|---------|-------------|
| O1 | Launch exit non-zero | Inspect `logs[]`; confirm Dev Kit OVMS scripts |
| O2 | Timeout | Firewall/port; increase wait or start OVMS manually |
| O3 | `-Test` fail | Re-run installer OVMS test; try `-Profile verify` |
| O4 | Chat 4xx | Use model id from O2 / `serving_model` |

## Recommended hardware

Agent profile (D9) on Intel® Core™ Ultra (Series 3) with **≥ 64 GB** RAM — [`docs/recommended-hardware.md`](../docs/recommended-hardware.md).
