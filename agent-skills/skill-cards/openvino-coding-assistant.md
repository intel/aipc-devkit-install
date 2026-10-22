---
skill_id: openvino-coding-assistant
version: 0.2.0
scope: lite
owner: aipc-agent-skills
description: VS Code Continue on the OVMS model already on port 8000 (Muse-Glimmer or Qwen3.6). Does not replace that server. Merges Continue config without changing the default model.
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

- Use the model already on port **8000**: **`OpenVINO/Muse-Glimmer-30B-int4-ov`** or **`OpenVINO/Qwen3.6-35B-A3B-int4-ov`**
- Do not stop that server to download the other model
- API name comes from `GET /v3/models`

## Continue

- Merge into **`%USERPROFILE%\.continue\config.yaml`**
- **Add/update** OVMS model entry; **do not** set Continue default model
- **`-Apply -Approve`** writes file; backup **`config.yaml.bak.<timestamp>`**

## Checks

| Id | Meaning |
|----|---------|
| P1-vscode-continue | VS Code CLI + Continue extension (partial if extension not listed) |
| P2-ovms-coder-endpoint | Muse-Glimmer or Qwen3.6 on `GET /v3/models` at :8000 |
| P3-continue-config-staged | Merged YAML preview |
| P4-continue-config-apply | File written |

## Recommended hardware

Intel® Core™ Ultra (Series 3), **≥ 64 GB** RAM for Qwen3.6 35B — [`docs/recommended-hardware.md`](../docs/recommended-hardware.md).

## Acceptance

- OVMS serves **Muse-Glimmer** or **`Qwen3.6-35B-A3B`** on **:8000**
- Continue config merged; user selects model in UI
- User validates chat in Continue (autocomplete optional)
