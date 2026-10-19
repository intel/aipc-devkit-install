# Recommended reference hardware

Skills in this pack are validated against the following **reference platform**. Other machines may work for subsets of the flow (for example verify/smoke on smaller configs). **Full agent chat with the large local model** is intended for this class of system on any [Agent Skills](https://agentskills.io/home)–compatible host.

| Attribute | Requirement |
|-----------|-------------|
| **Processor** | **Intel® Core™ Ultra (Series 3)** |
| **System memory** | **≥ 64 GB** |
| **OS (MVP)** | Windows (see D3) |

## Model expectations

| Role | Decision | Typical use |
|------|----------|-------------|
| Verify / smoke | **D1** — Qwen 3.5 0.8B | Fast Dev Kit + OVMS checks |
| Agent chat and VS Code Continue | **D9** — **Qwen 3.6 35B A3B** (OpenVINO, `OpenVINO/Qwen3.6-35B-A3B-int4-ov`) | Hermes / OpenClaw / Continue on port 8000 |

**D9 runtime:** use OpenVINO Model Server **2026.3.1 or newer** (`python_on` Windows zip). Dev Kit first install may ship older OVMS; run `scripts/windows/upgrade-ovms-runtime.ps1 -Approve` before D9 sign-off. Prefer **GPU** for D9 (MoE). Lab validated 3.6-35B-A3B on D10; former D9 **`OpenVINO/Qwen3.8-27B-int4-ov`** was retired after `openvino.dll` crashes on reference HW.

The **D9 model id may change** when newer OpenVINO-quantized releases replace the default; skills read the locked value from `DECISIONS.md` / `DefaultAgentModelId` until you override with `-Model`.

## Trademarks

Intel, Intel Core, and Intel Core Ultra are trademarks of Intel Corporation or its subsidiaries.
