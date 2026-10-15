# Team ownership (3 engineers)

Minimize coordination: **three lanes**, **one contract owner**, **one skill ID per branch**.

## Lanes

| Engineer | Lane | Owns | Does not own |
|----------|------|------|----------------|
| **E1 — Platform** | Dev Kit + OVMS scripts | `scripts/windows/` invokers (except shared policy), install/OVMS/smoke wiring, fixtures for Dev Kit | Hermes/OpenClaw SKILL.md, schemas |
| **E2 — Agents** | Hermes + OpenClaw | `adapters/**`, provider config apply/rollback, Scenarios B/C demos, OpenClaw security defaults | Installer internals, schema files |
| **E3 — Trust** | Evidence + integration | `schemas/`, `skill-cards/`, telemetry, golden reports, HW lab sign-off, validation CI | OVMS flags, agent config formats |

**Contracts:** E3 owns schema *shape*; E1 owns `_skill-common.ps1` implementation (E3 approves JSON field changes).

## Directory boundaries

```text
schemas/              → E3
skill-cards/          → E3 (E2 may PR agent-hint sections only)
scripts/windows/      → E1
adapters/             → E2
telemetry/            → E3 (E1 adds emit calls)
tests/integration/    → E3 runs; each engineer adds goldens for their skills
```

## Rituals

- **Monday (15 min):** skill IDs + files each person touches this week
- **Wednesday:** only if changing `skill-result-2026-08` or `_skill-common.ps1`
- **Friday (30 min):** reference HW Scenario A; store JSON in `golden-reports/`

## Phase focus

| Phase | E1 | E2 | E3 |
|-------|----|----|-----|
| M0–M1 | verify + OVMS | SKILL.md stubs | schemas + goldens |
| M2 | smoke stable | Hermes/OpenClaw E2E | Scenario A on HW |
| M3 | `run-quick-agent-track.ps1` | Scenario C | MVP sign-off |
| P1 | sample-setup | coding assistant | model/RAG/bench reports |
| P2 | Linux scripts | MCP client configs | MCP gateway policy + governance |

## Anti-patterns

- Two people on the same `invoke-*.ps1` or same skill ID in parallel
- MCP before MVP tag without E3 namespace map
- Model/target changes without updating `DECISIONS.md`
