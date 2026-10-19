# intel-devkit-verify checks

The invoker prints these check ids in JSON `checks[]`. The skill follows `next_skill` from the result. It does not re-decide the hand-off from this table.

| Id | What it reports |
|---|---|
| `V1-installer-state` | `devkit_status`: absent, partial, or present |
| `V2-git` | `git --version` when the Dev Kit is not absent |
| `V3-openvino-genai` | `openvino_genai` found on the install |
| `V4-ovms-installed` | OVMS runtime / `ovms_agentic_setup.ps1` under the install root |
| `V4-ovms-model` | Verify (smoke) model on disk |
| `V4-agent-model-on-disk` | Agent model on disk |
| `V4-ovms-running` | OVMS answering on the default endpoint |
| `V5-minimal-inference` | Small-model inference check |
| `V6-agentic-inference` | Agent-model inference check; feeds `agent_inference_ready` |

A V4-only failure after V3 passes is an OVMS gap. Hand off to `intel-ovms-agentic-setup` or `intel-devkit-ovms-slice-fetch`, not `intel-devkit-install`.
