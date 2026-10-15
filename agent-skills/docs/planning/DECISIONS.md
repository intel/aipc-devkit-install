# Quick Agent Track — Decision Log

Record of Day-0 locks for MVP. Update **Locked?** and date when stakeholders agree.

| # | Decision | Status | Value / notes | Locked on |
|---|----------|--------|---------------|-----------|
| D1 | Default local model | **Locked** | **Verify / smoke model:** **Qwen 3.5 0.8B** — `OpenVINO/Qwen3.5-0.8B-int4-ov`, **CPU**, `-Pull` for `intel-ovms-agentic-setup -Profile verify`. Used by **V4-ovms-model** and fast acceptance tests. Optional API alias: `-ModelName "Qwen3.5-0.8B"`. Tool parser: `hermes3` (Qwen3* match). Fallback if pull fails: `qwen3-4b` or `OpenVINO/Qwen3-0.6B-int4-ov`. **Agent chat uses D9**, not D1. | 2026-08-21 |
| D2 | OVMS contract | **Locked** | Base `http://localhost:8000/v3`; `GET /v3/models`, `POST /v3/chat/completions`; OpenAI-compatible smoke test in MVP | 2026-08-20 |
| D3 | Primary OS for MVP | **Locked** | **Windows only** for MVP (no Linux scripts/cards required for ship; Linux deferred to P2) | 2026-08-20 |
| D4 | Agent hosts | **Locked** | **Primary:** [Agent Skills open standard](https://agentskills.io/specification) — portable [`skills/`](../skills/) tree for any compatible host (see [agentskills.io/home](https://agentskills.io/home)). **Validated on Intel AI PC (Windows):** **Hermes Agent** + **OpenClaw** (provider configure scripts). Other hosts use same `scripts/windows/` invokers; provider UX is product-specific. | 2026-08-21 |
| D5 | Install mode | **Locked** | **Primary:** top-up when Dev Kit already present (Scenario A). **Required:** detect when Dev Kit is **not** installed and branch cleanly—verify reports `devkit_status: absent|partial|present`, recommends `intel-devkit-install` with approval; full install not required for MVP sign-off on Scenario A only, but install skill + not-installed path must be testable (Scenario A′). | 2026-08-20 |
| D6 | Skill ID namespace | **Locked** | **Canonical `intel-*` only** in repo, telemetry, and cards. Deck P0 names are documentation aliases only. Lite coding skill ID: **`openvino-coding-assistant`** (not `-lite` suffix); **`scope: lite`** in skill-card metadata. | 2026-08-20 |
| D7 | Risk classes | **Locked** | **Five classes:** `read` \| `write-config` \| `install` \| `network` \| `privileged`. **`read`:** no approval required (telemetry only). All other classes: explicit approval before execute unless card documents a stricter rule. | 2026-08-20 |
| D8 | Report formats | **Locked** | **MVP stdout:** JSON only (no required `.md` artifact at ship). **Schema IDs:** date-stamped (e.g. `validation-report-2026-08`, `skill-result-2026-08`). **Runtime validation:** if JSON fails schema, emit `schema_valid: false` + warnings in report; **exit 0 allowed** when functional checks passed; **exit non-zero** when functional outcome is fail. (Tighten to fail-closed in P1 if needed.) | 2026-08-20 |
| D9 | Agent local model | **Locked** | **Qwen 3.6 35B A3B (OpenVINO, agent, MoE)** — `OpenVINO/Qwen3.6-35B-A3B-int4-ov`. Default target **GPU** for agent profile (CPU optional). **`-Pull` during Hermes/OpenClaw setup** (`configure-hermes-ovms.ps1` / `configure-openclaw-ovms.ps1`). Provider `model` must match **`GET /v3/models`** after OVMS starts. **Supersedes** `OpenVINO/Qwen3.8-27B-int4-ov` (lab: OVMS crash in `openvino.dll` on 3.8-27B; 3.6-35B-A3B validated on D10). **Revision policy:** pass `-Model` to override without changing cards. | 2026-09-02 |
| D10 | Reference hardware | **Locked** | **Intel® Core™ Ultra (Series 3)** with **≥ 64 GB** system memory. Documented on all skill cards and [`docs/recommended-hardware.md`](../recommended-hardware.md). D1 verify may run on lesser hardware; D9 agent path is signed off on D10. | 2026-08-21 |
| D11 | Skill JSON user vs diagnostic channel | **Locked** | **User:** `summary`, `user_message`, `next_steps`, `blocked_reason`, user `warnings`. **Diagnostic:** `checks[]`, `diagnostics` (incl. `milestone_refs` D1/D9, `catalog_model_id`, `error.code`), `logs[]`. Copy from [`schemas/check-registry.json`](../../schemas/check-registry.json). Agents must not read milestone/check ids aloud. See [`docs/agent-skill-output.md`](../agent-skill-output.md). | 2026-09-11 |
| D12 | Agentic inference readiness | **Locked** | **`agent_inference_ready`** / **`readiness_tier`** (`smoke` \| `agent`) from `GET /v3/models` agent regex. Checks **`A1-agentic-inference`** (OVMS skill), **`V6-agentic-inference`** (verify). `-Profile verify` pass without agent model → **`partial`** + user copy smoke-only. Hermes must not claim agent chat ready unless **`agent_inference_ready`**. | 2026-09-11 |
| D13 | VS Code Continue coding assistant | **Locked** | **Continue + OVMS only** (not Cursor/Hermes). Same catalog as D9: **`OpenVINO/Qwen3.6-35B-A3B-int4-ov`**, serving **`Qwen3.6-35B-A3B`**. Merge **`~/.continue/config.yaml`** (add/update entry; **do not** set Continue default). Canonical doc: [2026 Continue demo](https://docs.openvino.ai/2026/model-server/ovms_demos_code_completion_vsc.html). Skill: **`openvino-coding-assistant`**. | 2026-10-07 |
| D14 | OVMS port for coding | **Locked** | **Continue** uses the same endpoint as verify / D9 / Hermes: **`http://localhost:8000/v3`**. Do not start a second OVMS for Continue. | 2026-10-07 |

## Path discovery (implementation policy)

Not separate Day-0 IDs; locked for skill script behavior:

| Priority | Dev Kit install root (`Find-DevKitInstallRoot`) | `ovms.exe` (`Find-OvmsInstallDirectory`) |
|----------|--------------------------------------------------|------------------------------------------|
| 1 | **`AIPC_DEVKIT_INSTALL_ROOT`** | **`AIPC_OVMS_ROOT`** (and OVMS under **`AIPC_DEVKIT_INSTALL_ROOT`**) |
| 2 | **`C:\Intel`** (known subfolders + directory scan) | **`C:\Intel\OVMS`**, **`C:\Intel\OVMS\ovms`** |
| 3 | Script walk from `agent-skills`, then other candidate paths | `-InstallRoot`, other clone paths, **`%USERPROFILE%\OVMS`** (first match) |

## D1 — Reference commands (Windows) — verify / smoke

From Dev Kit `OVMS` folder:

```powershell
.\ovms_agentic_setup.ps1 -Model "OpenVINO/Qwen3.5-0.8B-int4-ov" -Target CPU -Pull
.\ovms_agentic_setup.ps1 -Test -Model "OpenVINO/Qwen3.5-0.8B-int4-ov" -Target CPU
```

Or via skills:

```powershell
.\scripts\windows\invoke-ovms-agentic-setup.ps1 -Approve -Pull -Profile verify
```

Hermes / OpenClaw use **D9** (not D1) for chat; see below.
## D9 — Reference commands (Windows) — Hermes / OpenClaw

Agent setup pulls **Qwen 3.6 35B A3B (OpenVINO)** — `OpenVINO/Qwen3.6-35B-A3B-int4-ov` — and stages provider config (default **`-Pull`**).

```powershell
.\scripts\windows\configure-hermes-ovms.ps1 -Approve
.\scripts\windows\configure-openclaw-ovms.ps1 -Approve
```

Underlying OVMS invocation (when wired):

```powershell
.\ovms_agentic_setup.ps1 -Model "OpenVINO/Qwen3.6-35B-A3B-int4-ov" -Target GPU -Pull
```

Use **OVMS ≥ 2026.3.1** (`python_on`) on fresh Dev Kit installs — see `upgrade-ovms-runtime.ps1 -Approve`.

## D13 — Reference commands (Windows) — VS Code Continue + Qwen3.6 35B

Port **8000** (D14); catalog **`OpenVINO/Qwen3.6-35B-A3B-int4-ov`**; API model **`Qwen3.6-35B-A3B`**. Same model as D9 agent setup.

```powershell
.\scripts\windows\invoke-openvino-coding-assistant-setup.ps1 -Approve -Pull -Apply
```

Or OVMS then Continue separately:

```powershell
.\scripts\windows\invoke-ovms-agentic-setup.ps1 -Approve -Pull `
  -Model "OpenVINO/Qwen3.6-35B-A3B-int4-ov" -Target GPU -Port 8000
.\scripts\windows\configure-continue-ovms.ps1 -Approve -Apply
```

Continue merge adds/updates **`~/.continue/config.yaml`**; does **not** change Continue default model.

## D1 — MVP checklist implications

- **4.3 O1–O4:** Acceptance tests run against `OpenVINO/Qwen3.5-0.8B-int4-ov` (or configured `-ModelName`).
- **4.4 C1–C2:** Staged diffs must reference **D9** agent model id (`OpenVINO/Qwen3.6-35B-A3B-int4-ov`), not D1.
- **Scenario A2:** `intel-ovms-agentic-setup -Profile verify` locked to D1; agent path uses D9 via `intel-agent-provider-config`.
- **Skill cards:** Document “verify on reference HW” for D1; agent HW sign-off for D9.

## D5 — Dev Kit present vs not installed

MVP must support **both** flows without false “pass” on verify:

| `devkit_status` | Meaning | Verify behavior | Next step |
|-----------------|---------|-----------------|-----------|
| `present` | Installer DB / expected paths found | Run full check matrix (V1–V5) | OVMS setup → agents |
| `partial` | Some artifacts; incomplete install | `overall_status: partial`; list gaps | **`next_skill: intel-devkit-install`** when V3 fails; **`intel-ovms-agentic-setup`** (or **`intel-devkit-ovms-slice-fetch`**) when V3 pass and OVMS not on disk; OVMS setup when runtime present but not running |
| `absent` | No tracked install / missing core paths | `overall_status: fail` or `blocked` for OVMS-dependent checks; **no** claim that OpenVINO/OVMS are ready | Emit `next_skill: intel-devkit-install`, preflight + **approval required** before mutating |

**Scenario A (sign-off):** top-up on Dev Kit–present machine.  
**Scenario A′ (required build/test):** verify on machine **without** Dev Kit → structured report → install skill invoked (with approval) → re-verify → continue loop.

Install on a **fresh OS** remains a stretch goal (long runtime); not a blocker for MVP tag if Scenario A + A′ pass and fresh-OS is documented as known limitation (WW28 top-up note).

## D6 — Canonical P0 skill IDs

| Skill ID | Deck alias (docs only) |
|----------|-------------------------|
| `intel-devkit-verify` | part of `devkit-install-verify-agent` |
| `intel-devkit-install` | part of `devkit-install-verify-agent` |
| `intel-ovms-agentic-setup` | `ovms-serve-local-model` |
| `intel-agent-provider-config` | `hermes-on-intel-aipc`, `openclaw-on-intel-aipc` |
| `intel-endpoint-smoke-test-report` | `endpoint-smoke-test-report` |
| `openvino-coding-assistant` | `openvino-docs-code-assistant-lite` (metadata: `scope: lite`) |

## D7 — Approval matrix (MVP)

| Risk class | Approval before execute |
|------------|---------------------------|
| `read` | No |
| `write-config` | Yes |
| `install` | Yes |
| `network` | Yes (when card marks network; e.g. model pull) |
| `privileged` | Yes |

## D8 — JSON report shape (MVP)

- Every run includes: `schema_id`, `schema_valid`, `functional_status`, `warnings[]`.
- Prefer generating markdown from JSON in P1; optional local `.md` for demos is allowed but not a ship gate.
