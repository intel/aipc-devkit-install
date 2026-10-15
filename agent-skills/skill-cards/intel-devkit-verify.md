---
skill_id: intel-devkit-verify
version: 0.1.0
owner: aipc-agent-skills
risk_class: read
approval_mode: none
supported_os: [windows]
platforms: [hermes, openclaw]
agent_skills_standard: true
hardware_fit_card: docs/recommended-hardware.md
recommended_hardware:
  processor: "Intel® Core™ Ultra (Series 3)"
  memory_gb_min: 64
deck_alias: [devkit-install-verify-agent]
validated_models: []
invoke:
  windows_script: scripts/windows/invoke-devkit-verify.ps1
---

# intel-devkit-verify

Read-only Dev Kit / environment evidence. Sets `devkit_status` and branches to install when absent.

## Checks

- V1 installer state (`applications.json`)
- V2 git on PATH
- V3 `openvino_genai` directory in standard locations
- V4 OVMS (when Dev Kit not absent): installed (`ovms.exe`); **verify model on disk (D1)** — strict match; **agent model (D9)** — informational skip if missing; running (`GET /v3/models` — skip if server down)
- **V6-agentic-inference:** large agent model advertised on OVMS when server is up (`agent_inference_ready` in JSON)
- **V5** minimal inference when V4 running passes — one chat completion or fail with message

## Known failures

| Symptom | Likely cause | Remediation |
|---------|--------------|-------------|
| `devkit_status=absent` | No `applications.json` / install root | Run `intel-devkit-install` with approval |
| V4-ovms-model fail | D1 model not on disk | `invoke-ovms-agentic-setup.ps1 -Approve -Pull -Profile verify` |
| V4-ovms-running skip | OVMS not started | OVMS setup skill or manual start |
| V5 fail | Wrong model id vs `/v3/models` | Match `serving_model` from smoke report |

## Outputs

JSON stdout (`skill-result-2026-08`). **`next_skill`:** `intel-devkit-install` when absent or **V3** fails; `intel-ovms-agentic-setup` when GenAI is ready but OVMS runtime/server/agent model is not; `intel-devkit-ovms-slice-fetch` when OVMS scripts are missing under the install root; **`intel-agent-provider-config`** when verify passes with **`agent_inference_ready: true`** (optional Hermes handoff). Say **`user_message`** only. **`next_skill`** stays on the result for the agent.

## Recommended hardware

Intel® Core™ Ultra (Series 3), **≥ 64 GB** RAM — full detail in [`docs/recommended-hardware.md`](../docs/recommended-hardware.md). D1 verify may run on smaller systems; D9 agent checks assume D10.
