---
skill_id: intel-agent-provider-config
version: 0.2.0
owner: aipc-agent-skills
risk_class: write-config
approval_mode: required
supported_os: [windows]
platforms: [hermes, openclaw]
agent_skills_standard: true
deck_alias: [hermes-on-intel-aipc, openclaw-on-intel-aipc]
validated_models: [OpenVINO/Qwen3.6-35B-A3B-int4-ov]
hardware_fit_card: docs/recommended-hardware.md
recommended_hardware:
  processor: "Intel® Core™ Ultra (Series 3)"
  memory_gb_min: 64
invoke:
  windows_script: scripts/windows/configure-agent-provider.ps1
---

# intel-agent-provider-config

Hermes / OpenClaw setup for local OVMS. Portable instructions for all [Agent Skills](https://agentskills.io/home) hosts: [`skills/software-development/intel-agent-provider-config/`](../skills/software-development/intel-agent-provider-config/SKILL.md).

1. **O1 — Agent model (D9):** Default **`-Pull:$false`**. If OVMS does not advertise D9, skill is **blocked** with `next_skill=intel-ovms-agentic-setup`. Optional **`-Pull`** runs full OVMS checks (disk preflight, pull lock, port policy) — requires **`-Approve`** and often **`-ApproveRetryPull`** for resume/re-pull.
2. **C1 — Provider config:** Staged Hermes `model.default` / OpenClaw `model` from **`GET /v3/models`** (`C2-v3-models`), not the catalog pull id. **`catalog_model_id`** in JSON is for OVMS setup only.
3. **`local_provider_handoff`:** Hermes CLI steps; user must switch provider / new session (no silent Apply).

## Recommended hardware

Intel® Core™ Ultra (Series 3), **≥ 64 GB** RAM — required class for D9 agent model — [`docs/recommended-hardware.md`](../docs/recommended-hardware.md).

Wrappers: `configure-hermes-ovms.ps1`, `configure-openclaw-ovms.ps1`. **Never silent write** — `-Apply` requires `-Approve`.

**Switch-to-local:** run `intel-ovms-agentic-setup` first, then this skill with **`-Approve`** (no `-Pull`). Pass **`-Pull`** only when user approved download in this step. Override model with **`-Model`** when D9 is updated before the next pack release.
