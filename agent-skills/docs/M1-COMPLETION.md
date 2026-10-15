# M1 — Verify + OVMS (completion record)

**Phase:** M1 from [`planning/IMPLEMENTATION-ROADMAP.md`](planning/IMPLEMENTATION-ROADMAP.md)  
**Status:** Code complete · **HW sign-off:** pending reference machine runs  
**Date:** 2026-08-24

---

## Objective

Prove the **read-only verify path** and **local OVMS inference path** without Hermes/OpenClaw (roadmap exit gate: checklist §4.1, §4.3, §4.5; Scenario A steps **A1, A2, A5**).

---

## Delivered in this milestone

| ID | Deliverable | Location |
|----|-------------|----------|
| M1.1 | `intel-devkit-verify` including **V5** minimal chat when OVMS is up | `scripts/windows/invoke-devkit-verify.ps1`, `_skill-common.ps1` |
| M1.2 | `intel-ovms-agentic-setup` executes **`ovms_agentic_setup.ps1`** (O1–O6 checks) | `scripts/windows/invoke-ovms-agentic-setup.ps1` |
| M1.3 | `intel-endpoint-smoke-test-report` (E1–E4, optional tool path) | `scripts/windows/endpoint-smoke-test.ps1` |
| M1.3b | Shared OVMS helpers (launch, wait, models parse, chat smoke) | `scripts/windows/_skill-common.ps1` |
| M1.4 | L2 contract tests (fixtures + golden absent + smoke fail) | `tests/Run-ContractTests.ps1`, `tests/fixtures/` |
| M1.5 | D9 pull wiring for provider config **O1** (not M2 `-Apply`) | `Add-AgentOvmsSetupCheck` in `_skill-common.ps1` |

**Explicitly not M1:** `intel-devkit-install` production install (M3.1), Hermes/OpenClaw `-Apply` (M2), full CI schema validator (P1 / D8 warn-only).

---

## Operator flow (reference hardware)

From `agent-skills/` on a Dev Kit–present Windows machine:

```powershell
# A1 — environment evidence (read-only)
.\scripts\windows\invoke-devkit-verify.ps1

# A2 — start OVMS with D1 verify model (network + approval if -Pull)
.\scripts\windows\invoke-ovms-agentic-setup.ps1 -Approve -Pull -Profile verify

# Re-verify optional (V5 runs when OVMS responds on :8000)
.\scripts\windows\invoke-devkit-verify.ps1

# A5 — endpoint smoke report
.\scripts\windows\endpoint-smoke-test.ps1
```

**Already running OVMS:** skip launch:

```powershell
.\scripts\windows\invoke-ovms-agentic-setup.ps1 -Approve -SkipLaunch -Profile verify
```

**Tool-call parity (O3 / DECISIONS D1):** enabled by default for `-Profile verify`; force on agent profile:

```powershell
.\scripts\windows\invoke-ovms-agentic-setup.ps1 -Approve -Profile agent -RunToolTest
```

---

## Skill checks implemented

### Verify (§4.1)

| Check | Behavior |
|-------|----------|
| V1–V4 | Unchanged branching; absent → `next_skill` |
| **V5** | When V4-ovms-running **pass**, one `POST /v3/chat/completions` with D1 model (or best match from `/v3/models`) |

### OVMS setup (§4.3)

| Check | Behavior |
|-------|----------|
| O1-launch | Runs `ovms_agentic_setup.ps1` from installer `OVMS/` (cwd = script dir); `-Pull` when requested |
| O2-health | `GET /v3/models` after wait (up to 180s) |
| O3-tool-test | `ovms_agentic_setup.ps1 -Test` (verify profile default; includes text + tool-call smoke) |
| O4-chat | POST `/v3/chat/completions` (passes when O3 `-Test` text generation succeeds on verify profile) |
| O5-logs | Output captured in `logs[]` |
| O6 | Teardown documented in `warnings[]` (manual stop) |

### Smoke report (§4.5)

| Check | Behavior |
|-------|----------|
| E1 | Parse model ids from `/v3/models`; set `serving_model` |
| E2 | Latency for one completion |
| E3 | Optional `-IncludeToolTest` → `ovms_agentic_setup.ps1 -Test` |
| E4 | `run_id` + schema id in message |

---

## Contract tests (no hardware)

```powershell
cd agent-skills\tests
.\Run-ContractTests.ps1
```

- **Absent fixture:** `AIPC_DEVKIT_INSTALL_ROOT` → `fixtures/devkit-absent` → golden `verify-devkit-absent.json`
- **Present-minimal:** fixture with `applications.json` + stub scripts → `devkit_status=present`
- **Smoke:** unreachable port → `functional_status=fail`

---

## Known limitations (document before MVP tag)

1. **Port parameter** is passed to `ovms_agentic_setup.ps1` only when not `8000`; installer script must accept `-Port` (if unsupported, ignore or align with D2).
2. **Model id matching** uses exact list from `/v3/models`, then suffix heuristic, then first model — document mismatches in HW lab log.
3. **Launch failures** with OVMS already running may still yield **pass** if O2/O4 succeed (`functional_status` partial if non-critical checks fail).
4. **V5** fails verify when chat fails even if disk checks pass — intentional honesty per checklist.
5. **Reference HW** runs not executed in this repo commit; fill [`tests/integration/MANUAL-HW-LAB.md`](../tests/integration/MANUAL-HW-LAB.md).

---

## Failure modes (skill cards)

See updated sections in:

- `skill-cards/intel-devkit-verify.md`
- `skill-cards/intel-ovms-agentic-setup.md`
- `skill-cards/intel-endpoint-smoke-test-report.md`

---

## Exit gate checklist (M1)

| Gate | Code | HW lab |
|------|------|--------|
| §4.1 verify complete | V5 added | Run on D10 machine |
| §4.3 OVMS setup | Wired | Run `-Approve -Pull -Profile verify` |
| §4.5 smoke report | E1–E4 | After OVMS up |
| Scenario A A1/A2/A5 | Scripts ready | ☐ operator |
| Contract tests | `Run-ContractTests.ps1` | Run locally / CI |
| Failure catalog | Skill cards | Updated |

**Next phase (M2):** Hermes/OpenClaw `-Apply`, full Scenario A with agents, `intel-devkit-install` for A′.

---

## Files touched in M1 (review list)

| File | Change |
|------|--------|
| `scripts/windows/_skill-common.ps1` | OVMS launch, API helpers, V5, O1 agent pull |
| `scripts/windows/invoke-ovms-agentic-setup.ps1` | Full O1–O6 flow |
| `scripts/windows/endpoint-smoke-test.ps1` | E1–E4 |
| `scripts/windows/invoke-devkit-verify.ps1` | V5 + absent skip |
| `scripts/windows/configure-agent-provider.ps1` | O1 status handling |
| `tests/Run-ContractTests.ps1` | New |
| `tests/reference-config.json` | New |
| `tests/fixtures/**` | Contract fixtures |
| `tests/integration/golden-reports/smoke-endpoint-unreachable.json` | New |
| `docs/M1-COMPLETION.md` | This document |
| `docs/implementation-status.md` | Status table |
| `skill-cards/*.md` | Failure modes |
| `tests/integration/MANUAL-HW-LAB.md` | M1 run script |
