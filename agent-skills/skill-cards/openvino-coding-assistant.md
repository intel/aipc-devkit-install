---
skill_id: openvino-coding-assistant
version: 0.2.0
scope: lite
owner: aipc-agent-skills
description: VS Code Continue + OVMS Qwen3.6 35B on port 8000 (same model as OVMS agentic setup); merges Continue config without changing default model.
risk_class: write-config
approval_mode: required
supported_os: [windows]
platforms: []
agent_skills_standard: true
hardware_fit_card: docs/recommended-hardware.md
recommended_hardware:
  processor: "Intel® Core™ Ultra (Series 3)"
  memory_gb_min: 64
deck_alias: [openvino-docs-code-assistant-lite]
canonical_doc: https://docs.openvino.ai/2026/model-server/ovms_demos_code_completion_vsc.html
invoke:
  windows_script: scripts/windows/invoke-openvino-coding-assistant-setup.ps1
  companion_scripts:
    - scripts/windows/configure-continue-ovms.ps1
    - scripts/windows/invoke-ovms-agentic-setup.ps1
ovms_contract:
  base_url: http://localhost:8000/v3
  catalog_model: OpenVINO/Qwen3.6-35B-A3B-int4-ov
  serving_model: Qwen3.6-35B-A3B
---

# openvino-coding-assistant

VS Code **Continue** + **OVMS** local coding assistant ([2026 doc](https://docs.openvino.ai/2026/model-server/ovms_demos_code_completion_vsc.html)). **Cursor / Hermes / OpenClaw out of scope** for this skill.

## OVMS

- Catalog: **`OpenVINO/Qwen3.6-35B-A3B-int4-ov`** (same as OVMS agentic setup)
- Port **8000** (`http://localhost:8000/v3`)
- API name **`Qwen3.6-35B-A3B`**

## Continue

- Merge into **`%USERPROFILE%\.continue\config.yaml`**
- **Add/update** OVMS model entry; **do not** set Continue default model
- **`-Apply -Approve`** writes file; backup **`config.yaml.bak.<timestamp>`**

## Checks

| Id | Meaning |
|----|---------|
| P1-vscode-continue | VS Code CLI + Continue extension (partial if extension not listed) |
| P2-ovms-coder-endpoint | Qwen3.6 35B on `GET /v3/models` at :8000 |
| P3-continue-config-staged | Merged YAML preview |
| P4-continue-config-apply | File written |

## Recommended hardware

Intel® Core™ Ultra (Series 3), **≥ 64 GB** RAM for Qwen3.6 35B — [`docs/recommended-hardware.md`](../docs/recommended-hardware.md).

## Acceptance

- OVMS serves **`Qwen3.6-35B-A3B`** on **:8000**
- Continue config merged; user selects model in UI
- User validates chat in Continue (autocomplete optional)
