# Validation and continuous testing strategy

How we validate agent skills over time: every PR, on fixtures, and on reference Intel AI PC hardware.

**Related:** `docs/planning/MVP-CHECKLIST.md`, `schemas/`, `docs/planning/DECISIONS.md` D8.

---

## 1. Four layers

| Layer | What | Where it runs | Blocks merge? |
|-------|------|---------------|---------------|
| **L1 Static** | Skill-card frontmatter vs `skill-card.schema.json`; risk ↔ approval; script paths exist | CI (any OS for lint; Windows for PS) | Yes |
| **L2 Contract** | Invoker stdout validates `skill-result-2026-08`; compare to golden (strict fields) | Windows CI | Yes (shape + key outcomes) |
| **L3 Fixtures** | Scripts against fake Dev Kit trees (`absent` / `present`) without full install | Windows CI | Yes for verify branching |
| **L4 Reference HW** | Real Dev Kit + OVMS + agents; Scenarios A, A′, B | Self-hosted runner on AI PC | Yes for `main` / release |
| **L5 Agent smoke** | Scenario C (deterministic script first; LLM nightly later) | Reference HW | Nightly |
| **L6 Release** | Full matrix + archived `validation-report-2026-08` | Tag pipeline | Required for MVP tag |

```text
Every PR:  L1 → L2 → L3
Nightly:   L4 (+ L5 when ready)
Release:   L6
```

---

## 2. Contract testing (skills as CLI APIs)

**Public surface per skill:**

- Entry: `scripts/windows/invoke-*.ps1` (args, exit code)
- Output: JSON on stdout with `schema_id: skill-result-2026-08`

**Per skill, in repo:**

```text
  tests/
  Run-ContractTests.ps1          # L2 contract entrypoint (M1)
  reference-config.json          # pinned devkit SHA, model, target
  fixtures/
    devkit-absent/
    devkit-present-minimal/
  contract/
    intel-devkit-verify/
      cases/
      expected/
  integration/golden-reports/      # already started
```

**Golden diff policy:**

- **Strict match:** `schema_id`, `skill_id`, `functional_status`, `checks[].id` + `status`, `devkit_status`, `next_skill` when applicable
- **Ignore:** `run_id`, timestamps, absolute paths, latency
- **Never allow:** functional `pass` when golden expects `fail` / `blocked` for the same fixture

**D8 runtime:** exit code follows **functional** outcome; `schema_valid: false` may still exit 0 if functional pass (warn in CI log).

---

## 3. Reference hardware

- **One self-hosted runner** on a labeled AI PC (e.g. `intel-aipc-cpu`, D1 Qwen3.5 0.8B CPU).
- **Schedule:** nightly Scenario A + A′; path-filtered run when `skill-cards/` or `scripts/` changes.
- **Artifacts:** upload JSON reports from CI (30-day retention).
- **Telemetry:** same runner appends to SQLite; weekly export optional.

Pin upstream Dev Kit in `tests/reference-config.json`. Optional weekly job against `aipc-devkit-install` `main` opens an issue on failure (non-blocking).

---

## 4. Skill-card lint (L1)

Script `tests/validate-skill-cards.ps1` (to implement) should:

- Validate frontmatter against `skill-card.schema.json`
- Enforce `read` → `approval_mode: none` (D7)
- Ensure `invoke.windows_script` exists
- Cross-check canonical IDs with `DECISIONS.md`

---

## 5. Telemetry as health signal

On reference runner, track:

- Failure rate by `skill_id` (7d)
- p95 duration for install / OVMS
- Spikes in `verification_failed`

Nightly: assert each scenario emits `skill_invocation_start` → `skill_invocation_end`.

---

## 6. Version matrix (start narrow)

| Dimension | MVP | Later |
|-----------|-----|--------|
| OS | Windows 11 | More builds |
| Model / target | D1 in DECISIONS.md | Fallback models |
| Dev Kit | Pinned git SHA | Weekly upstream smoke |
| Agents | Hermes + OpenClaw pinned | Expand in P1 |

---

## 7. CI workflows (target)

```text
.github/workflows/
  skill-cards-lint.yml      # L1
  contract-windows.yml      # L2 + L3 on windows-latest or self-hosted
  reference-hw-nightly.yml  # L4 on [self-hosted, intel-aipc-cpu]
```

**Branch protection (recommended):**

- PR: L1–L3 green
- `main`: reference HW green within last 48h
- Tag `v0.1.0-mvp`: L6 artifact attached

---

## 8. Build order (1–2 weeks)

1. `Run-ContractTests.ps1` + golden diff for `intel-devkit-verify`
2. `validate-skill-cards.ps1`
3. Windows CI with `devkit-absent` / `devkit-present-minimal` fixtures
4. Self-hosted runner + nightly Scenario A
5. Link scenarios to `tests/integration/MANUAL-HW-LAB.md`

---

## 9. Ownership (team of 3)

See [`TEAM-OWNERSHIP.md`](TEAM-OWNERSHIP.md): E3 owns L1–L2 and golden reports; E1 fixtures + Windows CI; E2 agent scenarios (L5).
