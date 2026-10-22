# Provider hosts

`intel-agent-provider-config` stages settings. The user still switches the agent and starts a new chat.

| Host | Invoker | After the script |
|---|---|---|
| Hermes | `scripts/windows/configure-hermes-ovms.ps1` | `hermes model`, then `hermes config set model.default "OpenVINO/Qwen3.6-35B-A3B-int4-ov"`, then a new chat |
| OpenClaw | `scripts/windows/configure-openclaw-ovms.ps1` | Review the staged config and start a new session on that same model id |
| Other | `scripts/windows/configure-agent-provider.ps1 -TargetAgent hermes` | Same endpoint and model id; the product's own provider UI differs |

`-Apply` is not an automatic Hermes provider switch. Follow `local_provider_handoff` in the JSON result.

Port **8000** is this path. Continue uses that same server and whichever of Muse-Glimmer or Qwen3.6 is already advertised (`openvino-coding-assistant`).
