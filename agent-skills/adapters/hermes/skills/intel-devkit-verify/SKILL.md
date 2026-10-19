---
name: intel-devkit-verify
description: Verify Intel AI PC Dev Kit install state (read-only). Canonical instructions in skills/software-development/intel-devkit-verify/SKILL.md.
metadata:
  hermes:
    risk_class: read
---

# intel-devkit-verify

Portable skill: [`skills/intel-devkit-verify/SKILL.md`](../../../../skills/software-development/intel-devkit-verify/SKILL.md).

```powershell
& scripts/windows/invoke-devkit-verify.ps1
```

Interpret JSON stdout (`skill-result-2026-08`). Tell the user **`user_message`** only.

Follow **`next_skill`** only when the user's request includes that step. Do not say the skill id. Do **not** paste raw `.\scripts\windows\*.ps1` commands.

| `next_skill` | When |
|--------------|------|
| **`intel-devkit-install`** | `devkit_status` absent, or **V3-openvino-genai** failed/skipped (GenAI missing) |
| **`intel-devkit-ovms-slice-fetch`** | V3 pass, V4 fail, and `ovms_agentic_setup.ps1` missing under the verify install root |
| **`intel-ovms-agentic-setup`** | V3 pass and GenAI ready; OVMS runtime missing, not running, or agent model not loaded |

If **`next_skill`** is **`intel-ovms-agentic-setup`** and **`agent_inference_ready`** is false, use **`-Profile agent`** when appropriate—not install.

If verify **`functional_status`** is **`pass`** with **`agent_inference_ready: true`**, **`next_skill`** should be **`intel-agent-provider-config`**—offer that as the optional next step to stage Hermes local OVMS settings (user still starts a new chat / switches model manually).
