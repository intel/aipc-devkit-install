# Implementation status

Engineering notes for the Agent Skills pack. **Customer-facing setup guide:** [README.md](../README.md).

Last updated for **DevKit 4.0** agent-skills integration into `training.developer.aipc`.

## Summary

| Area | Status |
|------|--------|
| `intel-devkit-verify` | **Functional (M1)** — V1–V5; absent/partial/present branching, JSON stdout |
| `intel-devkit-install` | **Functional** — runs `Setup_1.ps1 install` then `Setup_2.ps1` (GenAI); long-running; Admin required |
| `intel-ovms-agentic-setup` | **Functional (M1)** — runs `ovms_agentic_setup.ps1`; O1–O6 checks |
| `intel-agent-provider-config` | **Partial (M2)** — O1 D9 pull wired; C1 staged diff; `-Apply` not implemented |
| `intel-endpoint-smoke-test-report` | **Functional (M1)** — E1–E4; `-IncludeToolTest` optional; validate on HW lab |
| `openvino-coding-assistant` | **Functional (D13)** — Qwen3.6 35B on :8000 + Continue config merge (`-Apply -Approve`) |
| Hermes / OpenClaw adapters | **Sample** — optional overlays; canonical text under `skills/` |
| Schema validation in CI | **Not yet** — D8 allows runtime warn-only; use `tests/Run-ContractTests.ps1` locally |
| Telemetry | **Optional** — requires `sqlite3` CLI |

## Repository layout

| Path | Purpose |
|------|---------|
| `skills/` | Portable [Agent Skills](https://agentskills.io/specification) (`SKILL.md` per skill) |
| `skill-cards/` | Source-of-truth skill definitions |
| `schemas/` | JSON Schema for cards and CLI output |
| `scripts/windows/` | PowerShell invokers (strict JSON stdout) |
| `adapters/hermes`, `adapters/openclaw` | Agent-specific `SKILL.md` |
| `telemetry/` | SQLite event store |
| `tests/integration/golden-reports/` | Exemplar JSON outputs |
| `docs/planning/` | MVP checklist, decisions, roadmap (internal) |

## Technical behavior

- **Install root (assumption):** Operator clones **`training.developer.aipc`** (or equivalent) and places **`agent-skills/`** beside **`Windows_Software_Installation/`**. Discovery order: **`AIPC_DEVKIT_INSTALL_ROOT`** → **`C:\Intel`** candidates → script walk / other paths (`Find-DevKitInstallRoot`). **`AIPC_OVMS_ROOT`** → **`C:\Intel\OVMS`** (and `\ovms`) → other paths for **`ovms.exe`** (`Get-OvmsSearchPaths`). Optional **`fetch-devkit-ovms-slice.ps1`** sparse-clones `Windows_Software_Installation/OVMS` only; full Setup_1/2 still requires **`intel-devkit-install`**.
- **Models:** D1 verify vs D9 agent (**Qwen 3.6 35B A3B** OpenVINO); defaults in `_skill-common.ps1`; policy in [`planning/DECISIONS.md`](planning/DECISIONS.md).
- **Hardware (D10):** Documented on skill cards; **not** enforced in verify scripts yet.
- **Schemas:** Date-stamped `*-2026-08`; bump with new JSON file after MVP tag—do not rename in place.
- **Checks on ordered results:** Use `Add-VerifyCheck` when mutating `checks` from helper functions (ordered hashtable + `[hashtable]` param bug on Windows PowerShell).

## MVP workflow (engineering)

```text
intel-devkit-verify → [intel-devkit-install if absent or V3 fail] → intel-ovms-agentic-setup (-Profile verify; or ovms-slice-fetch if OVMS folder missing)
→ configure-hermes-ovms / configure-openclaw-ovms → intel-endpoint-smoke-test-report
```

## Conventions

- **Skill IDs:** Canonical `intel-*` (except `openvino-coding-assistant` with `scope: lite`).
- **Exit codes:** `0` = functional pass; non-zero = functional fail. Schema warnings may still exit `0` per D8.
- **Approval:** `read` skills run without approval; other risk classes require `-Approve`.

## Planning and validation

| Document | Use |
|----------|-----|
| [`planning/DECISIONS.md`](planning/DECISIONS.md) | Locked D1–D10 |
| [`planning/MVP-CHECKLIST.md`](planning/MVP-CHECKLIST.md) | Ship checklist |
| [`planning/IMPLEMENTATION-ROADMAP.md`](planning/IMPLEMENTATION-ROADMAP.md) | Phased roadmap |
| [`planning/VALIDATION-STRATEGY.md`](planning/VALIDATION-STRATEGY.md) | Test strategy |
| [`planning/GITHUB-SHARE.md`](planning/GITHUB-SHARE.md) | Inner-source branch `DevKit4.0` |
| [`tests/integration/MANUAL-HW-LAB.md`](../tests/integration/MANUAL-HW-LAB.md) | Reference HW sign-off |

## Next wiring tasks (M2+)

1. Implement `-Apply` with backup/rollback for Hermes and OpenClaw configs.  
2. Execute `Setup_1.ps1` from `intel-devkit-install` with progress and checkpointing (M3).  
3. Add JSON Schema validation step to CI (optional strict mode).  
4. Optional: D10 hardware read-only checks in verify (warn-only).  
5. Reference HW: complete Scenario A / A′ in [`tests/integration/MANUAL-HW-LAB.md`](../tests/integration/MANUAL-HW-LAB.md).

**M1 record:** [`M1-COMPLETION.md`](M1-COMPLETION.md)
