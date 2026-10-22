# Intel AI PC Dev Kit 4.x — Agent Skills MVP

**Status update for slides** · August 27, 2026  
**Branch / deliverable:** `Devkit4.0` · `agent-skills/` in the Dev Kit clone (beside `Windows_Software_Installation`)

---

## Executive summary (1 slide)

- **Local OVMS verify path is working on reference lab hardware** after fixes to health checks, chat/tool ordering, and timing/warmup.
- **M1 core skills are functionally implemented** (verify, install wrapper, OVMS setup, endpoint smoke); **agent provider config remains partial** (staging only, no `-Apply`).
- **Decisions D1–D10 remain locked**; formal MVP closure still needs **HW lab sign-off**, **contract tests**, and **M2 apply path** for Hermes/OpenClaw.

---

## Completed recently (lab + engineering)

### OVMS skill (`intel-ovms-agentic-setup`)

- O2: Reliable parsing of `GET /v3/models` (including D1 model `OpenVINO/Qwen3.5-0.8B-int4-ov`).
- O1: Detached launch of `ovms_agentic_setup.ps1` so the skill completes while OVMS runs in a separate window.
- O3/O4 reorder and behavior:
  - **O3-tool-test** — Dev Kit `-Test` (text + tool-call smoke).
  - **O4-chat** — chat completion evidence (on verify profile, passes when O3 `-Test` text generation succeeds).
  - **O3-prep** — polls chat before `-Test` to reduce 412/warmup races after `-Pull`.
- HTTP alignment with Dev Kit recipes (`Invoke-WebRequest`, JSON body); troubleshooting for 404/412 documented.

### Install / verify (prior work, stable on lab)

- `intel-devkit-install`: Setup_1 execution policy, Setup_2 / genai-minimal / Setup2Only behavior, path discovery (`AIPC_DEVKIT_INSTALL_ROOT`, `C:\Intel`).
- `intel-devkit-verify`: V1–V5 including minimal chat when OVMS is up.

### Handoff & operations

- Distribution is the Dev Kit clone. `agent-skills` sits beside `Windows_Software_Installation`. See [Clone the Dev Kit repo](../README.md#clone-the-dev-kit-repo).
- **`PROJECT-REPORT.md`** at repo root for stakeholder narrative.

### Lab validation

- **Track A OVMS step passes** on test machine (O1–O5, verify profile).
- Zip unblock required on lab PC (expected for unsigned archive with PowerShell); not a product defect.

---

## In progress / partial

| Item | Status | Notes |
|------|--------|--------|
| `intel-agent-provider-config` | **Partial (M2)** | C1 staged diff; D9 pull wired; **`-Apply` not implemented** |
| Scenario A (full MVP E2E) | **Partial** | A1/A2 strong; A3–A4 need apply + agent chat validation |
| `intel-endpoint-smoke-test-report` | **Ready to run** | E1–E4 implemented; formal lab run pending |
| Contract tests | **Pending sign-off** | `tests/Run-ContractTests.ps1` |
| HW lab record | **Pending** | `tests/integration/MANUAL-HW-LAB.md` |

---

## Not started / post-MVP (checklist)

- JSON Schema validation in CI (S1/S2) — runtime warn-only today.
- SQLite telemetry pipeline (S5) — optional.
- Hermes bundle auto-install (S6) — stub.
- Linux adapters — out of MVP (D3).
- External publish / scan-sign policy on cards — internal gate.

---

## MVP definition (reminder slide)

**Target operator flow**

```text
verify Dev Kit → [install if absent] → start agentic OVMS (D1 0.8B verify)
→ stage Hermes/OpenClaw for localhost:8000/v3 → smoke test → JSON reports on stdout
```

**In scope:** Windows P0 skills, approval gates, JSON stdout, clone-first (no runtime download of installer/OVMS scripts).

**Out of scope:** MCP gateway, full RAG, Linux, silent config apply without approval (until M2 `-Apply`).

---

## Risks & mitigations (1 slide)

| Risk | Mitigation |
|------|------------|
| Windows blocks `.ps1` on lab machines | `Unblock-File` on `agent-skills\*.ps1`, or run with `-ExecutionPolicy Bypass`. See [troubleshooting.md](troubleshooting.md). |
| OVMS chat 412 before model warmup | O3-prep polling; O3 before O4 in execution; user waits on `-Pull` compile |
| Long Setup_2 / full GenAI install | Default genai-minimal; `-Setup2Full` documented; Setup2Only graceful skip |
| MVP “done” vs “works on one lab” | MANUAL-HW-LAB + checklist Scenario A sign-off still required |

---

## Recommended next steps (slide bullets)

1. Run **`endpoint-smoke-test.ps1`** and **`Run-ContractTests.ps1`** on lab; file **`MANUAL-HW-LAB.md`**.
2. Complete **Scenario A** steps **A5** and document **A3** (staged provider diff).
3. **M2:** Implement **`-Apply`** with backup/rollback for Hermes/OpenClaw (or document manual apply as interim).
4. Optional: CI schema validation; D10 hardware warn-only in verify.
5. Inner-source: commit `agent-skills` on **`Devkit4.0`** in the Dev Kit repo. Testers use that clone.

---

## One-line status labels (for slide footers)

- **Overall MVP:** *Implementation ~75–80%; formal acceptance ~50–60% (checklist + M2 + HW sign-off).*
- **M1 (verify + OVMS + smoke):** *Code complete; **HW validated for OVMS verify** on lab.*
- **M2 (agent connect):** *Staging only; apply pending.*
- **M3 (install polish):** *Functional; progress/checkpointing enhancements optional.*

---

## Suggested slide titles for Copilot mapping

1. Executive summary
2. What we completed this sprint (OVMS + lab)
3. MVP component status (table)
4. End-to-end scenario progress (A1–A5)
5. Risks & mitigations
6. Next steps & exit criteria
