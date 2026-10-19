# Quick Agent Track — MVP Checklist

Intel AI PC Dev Kit 4.x · Skills-first local agent path  
**Status:** Planning · **Audience:** engineering + validation  
**Sources:** `Intel_AI_PC_DevKit_4x_Skills_First_Proposal.pptx`, `AgentSkills-v1.docx`

This checklist defines **scope lock**, **acceptance tests**, **evidence artifacts**, and **exit criteria** for the MVP. Treat unchecked items as blockers for calling the MVP complete.

---

## 0. Decisions to lock before build (Day 0)

| # | Decision | Owner | Locked? | Notes |
|---|----------|-------|---------|-------|
| D1 | **Verify / smoke model** — **Qwen 3.5 0.8B** (`OpenVINO/Qwen3.5-0.8B-int4-ov`, **CPU**; see `DECISIONS.md`) | | ☑ | V4-ovms-model; `intel-ovms-agentic-setup -Profile verify` |
| D9 | **Agent model** — **Qwen 3.6 35B A3B (OpenVINO)** (`OpenVINO/Qwen3.6-35B-A3B-int4-ov`; `-Pull` on Hermes/OpenClaw setup) | | ☑ | D10 reference HW |
| D10 | **Reference hardware** — Intel® Core™ Ultra **(Series 3)**, **≥ 64 GB** RAM | | ☑ | [`docs/recommended-hardware.md`](../recommended-hardware.md) |
| D2 | **OVMS contract** — base URL `http://localhost:8000/v3`, paths `/v3/models`, `/v3/chat/completions` | | ☑ | See `DECISIONS.md` |
| D3 | **OS for MVP** — **Windows only** | | ☑ | Linux out of MVP ship criteria |
| D4 | **Agent hosts** — [Agent Skills open standard](https://agentskills.io/home) + Hermes/OpenClaw validated | | ☑ | Portable `skills/` + `docs/agent-skills-compatibility.md` |
| D5 | **Install mode** — top-up primary; **must handle Dev Kit not installed** (Scenario A′) | | ☑ | Verify branches to install; see `DECISIONS.md` § D5 |
| D6 | **Skill IDs** — canonical **`intel-*`**; deck names aliases only; coding skill **`openvino-coding-assistant`** + `scope: lite` | | ☑ | See `DECISIONS.md` § D6 |
| D7 | **Risk classes** — five-class model; **read = no approval** | | ☑ | See `DECISIONS.md` § D7 |
| D8 | **Reports** — **JSON stdout only** for MVP; date-stamped schemas; schema warn + functional pass → exit 0 | | ☑ | See `DECISIONS.md` § D8 |

### Deck ↔ implementation skill ID mapping

| Deck (P0) | Canonical skill ID |
|-----------|-------------------|
| `devkit-install-verify-agent` | `intel-devkit-install` + `intel-devkit-verify` (split install vs verify) |
| `ovms-serve-local-model` | `intel-ovms-agentic-setup` |
| `hermes-on-intel-aipc` | `intel-agent-provider-config` (target: hermes) |
| `openclaw-on-intel-aipc` | `intel-agent-provider-config` (target: openclaw) |
| `endpoint-smoke-test-report` | `intel-endpoint-smoke-test-report` (or bundled in verify + OVMS setup) |
| `openvino-docs-code-assistant-lite` | `openvino-coding-assistant` (`scope: lite` in card metadata) |

---

## 1. MVP definition (in scope)

**User-visible outcome:** On a supported Intel AI PC, an operator (or agent with approvals) can complete:

```text
install/verify Dev Kit → start agentic OVMS → point Hermes or OpenClaw at localhost:8000/v3
→ run smoke test → receive reproducible JSON + markdown report
```

**In scope**

- P0 skill cards + script adapters for **Windows only** (`intel/aipc-devkit-install` entry points)
- Direct CLI / strict JSON from skill wrappers (no MCP server required for MVP)
- Observe → Plan → Execute → Verify loop with **approval gates** on mutating actions
- Structured telemetry to **SQLite** (skill invocation, duration, outcome, model, endpoint)
- Hermes and OpenClaw **profile templates** + validation commands (staged config diff, no silent writes)

**Out of scope (gate later phases)**

- Policy-aware MCP gateway / multi-server MCP topology
- Full RAG index of all OpenVINO docs
- GUI / shared model database integration with AI Playground
- Bundling OpenClaw inside the MSI (guidance + skills only)
- External publishing of skill repo without security review
- **Linux** adapters and parity (post-MVP / P2)

---

## 2. Repository skeleton (create before first skill)

Target tree: **`agent-skills/`** at repo root (sibling to `Windows_Software_Installation/` in `training.developer.aipc`).

```text
agent-skills/
  README.md                          # Quick start + MVP loop
  skill-cards/
    intel-devkit-verify.md
    intel-devkit-install.md
    intel-ovms-agentic-setup.md
    intel-agent-provider-config.md
    intel-endpoint-smoke-test-report.md
    openvino-coding-assistant.md          # metadata scope: lite
  schemas/
    skill-card.schema.json
    skill-result-2026-08.schema.json
    validation-report-2026-08.schema.json
  skills/                              # portable agentskills.io SKILL.md (all P0)
    intel-devkit-verify/
    ...
  adapters/
    hermes/
      skills/<skill-id>/SKILL.md
      bundles/intel-devkit-quick-agent.yaml
    openclaw/
      skills/<skill-id>/SKILL.md
  scripts/
    windows/
      invoke-devkit-install.ps1
      invoke-devkit-verify.ps1
      invoke-ovms-agentic-setup.ps1
      configure-hermes-ovms.ps1
      configure-openclaw-ovms.ps1
      endpoint-smoke-test.ps1
    linux/                             # deferred (D3: Windows-only MVP)
  telemetry/
    init-db.sql
    emit-event.ps1
  tests/
    integration/
      golden-reports/                  # committed exemplar JSON reports
    unit/
  docs/
    security-model.md
    troubleshooting.md
    agent-skills-compatibility.md
    recommended-hardware.md
    implementation-status.md
```

**Skeleton checklist**

| # | Item | Done |
|---|------|------|
| S1 | `skill-card.schema.json` validates all P0 cards | ☐ |
| S2 | `skill-result-2026-08.schema.json` validates CLI stdout JSON | ☐ |
| S3 | Every P0 card includes owner, version, risk class, approval mode | ☑ |
| S4 | Windows scripts return exit code 0/≠0 and stdout JSON on success/failure | ☑ (stubs + verify) |
| S5 | SQLite DB created idempotently; events queryable by skill_id and run_id | ☐ (needs sqlite3) |
| S6 | Hermes bundle installs skills under `~/.hermes/skills/` | ☐ (bundle stub) |
| S7 | Portable `skills/` tree matches [agentskills.io](https://agentskills.io/specification) for all P0 skills; OpenClaw/Hermes adapters optional | ☑ |
| S8 | CI job (or manual gate doc) runs integration tests on reference HW | ☑ (`tests/integration/MANUAL-HW-LAB.md`) |

---

## 3. Minimum acceptance metadata (every P0 skill)

Each skill card and every successful run must satisfy:

| Field | Required |
|-------|----------|
| Owner + semantic version | ☐ |
| Supported OS + hardware profile | ☐ |
| Validated model(s) + OVMS version | ☐ |
| Risk class + approval mode | ☐ |
| Automated tests + known failure list | ☐ |
| Hardware-fit card reference | ☐ |
| Scan/sign status (internal policy) | ☐ |
| Outputs: **JSON report** (stdout); markdown optional until P1 | ☐ |

**Default posture:** deterministic tools, approval gates on non-`read` risks, **fail-closed functional validation** (no false pass on tests). Schema validation per D8: warn if invalid JSON schema, exit code follows **functional** outcome.

---

## 4. P0 skill acceptance tests

### 4.1 `intel-devkit-verify` (build first)

**Purpose:** Read-only evidence foundation for all other skills.

| # | Test | Pass criteria |
|---|------|----------------|
| V1 | Installer state readable | Finds `applications.json` / tracked packages; sets `devkit_status`: `present` \| `partial` \| `absent` with evidence |
| V2 | Tooling presence | Git detected with version |
| V3 | OpenVINO GenAI | `openvino_genai` path present (standard Intel layout) |
| V4 | OVMS | Installed + **D1 verify model** on disk (strict); **D9 agent model** skip if missing; **running** skip if server down |
| V5 | Minimal inference | One chat completion or documented skip reason |
| V6 | Report | JSON stdout; `functional_status` + `schema_valid`; `overall_status` ∈ {pass, fail, partial, blocked}; no false functional pass; if `absent`, includes `next_skill: intel-devkit-install` |

| Skill complete | ☐ |

---

### 4.2 `intel-devkit-install` (mutating; gated)

**Purpose:** Wrap `Setup_1.ps1 install` with checkpointing and logs.

| # | Test | Pass criteria |
|---|------|----------------|
| I1 | Preflight | Admin/network/disk checks; user approval recorded before install |
| I2 | CLI invoke | Calls documented install path; streams progress or periodic status |
| I3 | State | Updates or reads install DB; log paths in report |
| I4 | Idempotency | Re-run documents already-installed components without corruption |
| I5 | Failure | Non-zero exit + JSON error object + remediation hints |
| I6 | Uninstall | Out of MVP unless explicitly in scope — if out, document “manual uninstall” |

| I7 | Not-installed path | After verify `absent`, install skill runs with approval; post-install verify shows `present` or `partial` with logs |

| Skill complete | ☐ |

---

### 4.3 `intel-ovms-agentic-setup`

**Purpose:** Wrap `ovms_agentic_setup.ps1`; enable local agentic inference.

| # | Test | Pass criteria |
|---|------|----------------|
| O1 | Launch | Model shorthand, target GPU/CPU/NPU, port configurable |
| O2 | Health | GET `/v3/models` lists expected model |
| O3 | Tool call | Built-in tool-call test passes (script `-Test` or equivalent) |
| O4 | Chat | POST `/v3/chat/completions` succeeds with default model |
| O5 | Logs | Paths captured in report |
| O6 | Teardown | Document stop process; optional cleanup approval |

| Skill complete | ☐ |

---

### 4.4 `intel-agent-provider-config` (Hermes + OpenClaw)

**Purpose:** Stage provider config for OVMS endpoint — **never silent write**.

| # | Test | Pass criteria |
|---|------|----------------|
| C1 | Hermes diff | Produces staged diff for `~/.hermes/config.yaml` (base URL, model) |
| C2 | OpenClaw diff | Produces staged diff for provider config / `openclaw.json` |
| C3 | Validation cmd | Documents one-liner to test chat after apply |
| C4 | Rollback | Rollback steps in markdown report |
| C5 | Apply gate | Apply only after explicit approval flag |

| Hermes profile complete | ☐ |
| OpenClaw profile complete | ☐ |

---

### 4.5 `intel-endpoint-smoke-test-report`

**Purpose:** Single command agents can run post-setup.

| # | Test | Pass criteria |
|---|------|----------------|
| E1 | Models list | Parses model id from `/v3/models` |
| E2 | Latency | Records TTFB or total time for one completion |
| E3 | Tool path | Optional tool-call smoke when agentic model loaded |
| E4 | Reproducibility | Same inputs → same schema; run_id in telemetry |
| E5 | Hermes/OpenClaw | Optional: one message via each host if configured |

| Skill complete | ☐ |

---

### 4.6 `openvino-coding-assistant` (scope: lite)

**Purpose:** Version-aware coding help without full doc crawl.

| # | Test | Pass criteria |
|---|------|----------------|
| A1 | Version bind | Reads installed OpenVINO version from environment |
| A2 | Scope | Lite = curated local snippets + link to official docs; no full RAG |
| A3 | Validation loop | Suggests compile/test command; does not claim code works without test |
| A4 | Stale API guard | Warns when generated API may not match installed version |

| Skill complete | ☐ |

---

## 5. End-to-end MVP scenarios (must pass on reference hardware)

Run on **at least one** validated Intel AI PC config (document SKU, GPU, driver, Dev Kit version).

### Scenario A — Top-up path (primary)

| Step | Action | Pass |
|------|--------|------|
| A1 | `intel-devkit-verify` on machine with Dev Kit already installed | ☐ |
| A2 | `intel-ovms-agentic-setup` with locked default model | ☐ |
| A3 | `intel-agent-provider-config` → Hermes → apply with approval | ☐ |
| A4 | Hermes: one chat against local OVMS | ☐ |
| A5 | `intel-endpoint-smoke-test-report` | ☐ |
| A6 | All reports validate against JSON schema | ☐ |

### Scenario A′ — Dev Kit not installed (required test)

| Step | Action | Pass |
|------|--------|------|
| A′1 | `intel-devkit-verify` → `devkit_status: absent`, `next_skill: intel-devkit-install` | ☐ |
| A′2 | Agent/operator approves install; `intel-devkit-install` runs | ☐ |
| A′3 | Re-run verify → `present` or `partial` (no false pass) | ☐ |
| A′4 | Continue A2–A6 on same machine after successful install | ☐ |

*Fresh bare OS install may exceed MVP time targets; document wall-clock if used.*

### Scenario B — OpenClaw path

| Step | Action | Pass |
|------|--------|------|
| B1 | Repeat A2–A5 with OpenClaw profile (test/sandbox posture) | ☐ |
| B2 | Security checklist in `docs/security-model.md` acknowledged | ☐ |

### Scenario C — Agent-driven loop (manual or scripted)

| Step | Action | Pass |
|------|--------|------|
| C1 | Agent receives skill cards only (no MCP) | ☐ |
| C2 | Agent runs verify → (install if absent, with approval) → setup → smoke | ☐ |
| C3 | Agent requests approval before any config write | ☐ |
| C4 | SQLite shows full span: preflight → complete/fail | ☐ |

---

## 6. Telemetry minimum (MVP)

| Event | Fields |
|-------|--------|
| `skill_invocation_start` | run_id, skill_id, version, host_agent, os, hardware_id |
| `preflight_result` | pass/fail, checks[] |
| `approval_requested` / `approval_granted` | action, risk_class |
| `skill_invocation_end` | outcome, duration_ms, endpoint, model, exit_code |
| `verification_failed` | test_id, message, log excerpt pointer |

| Telemetry complete | ☐ |

---

## 7. Security & governance gates (MVP)

| # | Gate | Done |
|---|------|------|
| G1 | OpenClaw docs: test system, local-only endpoint default | ☐ |
| G2 | No secrets in skill prompts or committed reports | ☐ |
| G3 | Third-party skill trust model documented | ☐ |
| G4 | Long-running install: async/progress pattern documented (Hermes timeout) | ☐ |
| G5 | Security review scheduled **before** external publish | ☐ |

---

## 8. MVP exit criteria (ship/no-ship)

**Ship MVP** when **all** are true:

- [ ] Decisions D1–D10 locked and recorded in `docs/planning/DECISIONS.md`
- [ ] Repository skeleton S1–S8 complete (S8 may be manual HW lab until CI exists)
- [ ] P0 skills 4.1–4.5 complete; 4.6 lite acceptable with documented limits
- [ ] Scenario A passes on reference hardware
- [ ] Scenario A′ passes (not-installed → install → re-verify → agent loop)
- [ ] Scenario B passes OR explicit waiver with security sign-off
- [ ] Scenario C demonstrated once (record demo or test log)
- [ ] Telemetry minimum implemented
- [ ] Gates G1–G4 complete; G5 scheduled

**Artifacts for stakeholders**

- [ ] One-page MVP results summary (time-to-first-success, HW config, model)
- [ ] Zip or tag of skill repo at version `v0.1.0-mvp`
- [ ] Known issues / failure catalog attached to each skill card

---

## 9. Post-MVP backlog pointer (not required for MVP sign-off)

P1: `intel-model-management`, `intel-sample-setup`, RAG lite, benchmark telemetry, skill-card generator.  
P2: policy-aware MCP, optimization skills, governed scale-out.

See `IMPLEMENTATION-ROADMAP.md` for phased delivery.
