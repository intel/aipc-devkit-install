---
skill_id: intel-endpoint-smoke-test-report
version: 0.1.0
owner: aipc-agent-skills
risk_class: read
approval_mode: none
supported_os: [windows]
platforms: [hermes, openclaw]
agent_skills_standard: true
deck_alias: [endpoint-smoke-test-report]
validated_models: [OpenVINO/Qwen3.5-0.8B-int4-ov, OpenVINO/Qwen3.6-35B-A3B-int4-ov]
hardware_fit_card: docs/recommended-hardware.md
recommended_hardware:
  processor: "Intel® Core™ Ultra (Series 3)"
  memory_gb_min: 64
invoke:
  windows_script: scripts/windows/endpoint-smoke-test.ps1
---

# intel-endpoint-smoke-test-report

POST `/v3/chat/completions` smoke test + latency; optional tool path when OVMS agentic model loaded.

Default smoke uses **D1**; full agent smoke on **D9** uses D10 hardware — [`docs/recommended-hardware.md`](../docs/recommended-hardware.md).

## Known failures

| Check | Symptom | Remediation |
|-------|---------|-------------|
| E1 | Connection refused | Run OVMS setup first; confirm D2 base URL |
| E2 | Timeout | Use D1 on CPU; check model loaded |
| E3 | Tool test fail | `-IncludeToolTest` only when agentic stack ready |
