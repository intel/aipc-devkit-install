# Intel AI PC Dev Kit 4.x — Agent Skills Project Report

**Purpose:** Stakeholder summary and input for presentations (e.g. Microsoft Copilot 365 / PowerPoint)  
**Repository:** `devkit4.0` branch **`Devkit4.0`** (Agent Skills pack for inner-source integration into `training.developer.aipc`)  
**Report date:** August 25, 2026  

---

## 1. Executive summary

This project delivers an **Agent Skills–compatible skill pack** so AI agents and operators on **Windows Intel AI PCs** can run a repeatable loop: **verify the Dev Kit → install or top-up → start OpenVINO Model Server (OVMS) → connect Hermes or OpenClaw → smoke-test local chat**. Skills emit **structured JSON on stdout** for automation, with **approval gates** on install, network, and config changes.

The approach is **skills-first, MCP-later**: PowerShell invokers wrap existing Dev Kit installer scripts (`Setup_1.ps1`, `Setup_2.ps1`, `ovms_agentic_setup.ps1`) instead of building a parallel installer. **M1 (Verify + OVMS)** is largely **code-complete**; **reference hardware sign-off** and **M2 (agent config apply)** remain in progress. Recent work extended **install** to include **Setup_2** (OpenVINO GenAI) and hardened install/verify based on **live lab testing**.

---

## 2. Problem and opportunity

**Problem:** Developers and agent hosts need a **trustworthy, automatable path** to local models on Intel AI PC Dev Kit hardware—without ad hoc scripts, silent config changes, or unclear install state.

**Opportunity:** Align with the open **[Agent Skills](https://agentskills.io/home)** standard so **Cursor, Hermes, OpenClaw, Claude Code**, and other hosts can use the same portable `skills/` tree, while Intel validates **Hermes and OpenClaw** on reference hardware.

**Target user outcome (MVP):**

```text
Install / verify Dev Kit → start agentic OVMS → point agent at http://localhost:8000/v3
→ run smoke test → receive reproducible JSON report
```

---

## 3. Project scope

### In scope (MVP)

- **Windows only** (decision D3)
- **Six P0 skills** (canonical `intel-*` IDs) plus lite **OpenVINO coding assistant**
- PowerShell **invokers** with strict **JSON stdout** (`skill-result-2026-08`)
- **Risk classes** and **`-Approve`** for mutating operations (D7)
- **Two model tiers:** D1 verify/smoke (**Qwen 3.5 0.8B** OpenVINO) and D9 agent (**Qwen 3.6 35B A3B** OpenVINO)
- **Reference hardware class:** Intel Core Ultra Series 3, **≥ 64 GB RAM** (D10)—documented, not yet enforced in scripts
- Portable **`skills/`** + Intel **`skill-cards/`** + optional **Hermes/OpenClaw adapters**
- Local **contract tests**, golden JSON reports, **manual HW lab** checklist
- **Clone-first policy:** `agent-skills/` sits beside `Windows_Software_Installation/` in the installer repo; skills do **not** download installer or OVMS scripts at runtime

### Out of scope (later phases)

- MCP policy gateway and multi-server topology
- Full OpenVINO doc RAG
- GUI / AI Playground model database integration
- Bundling OpenClaw in MSI
- Linux parity
- External public publish without security review
- Production **async install progress** for multi-hour Setup runs (planned M3.1; lab workaround: tail install logs)

---

## 4. Technical architecture

| Layer | Role |
|--------|------|
| **Agent hosts** | Hermes, OpenClaw, Cursor, etc.—read `SKILL.md`, run invokers |
| **Invokers** | `agent-skills/scripts/windows/*.ps1`—preflight, approval, JSON reports |
| **Dev Kit installer** | `Setup_1.ps1` (winget), `Setup_2.ps1` (GenAI zips/venvs), `ovms_agentic_setup.ps1` |
| **OVMS** | Local server at `http://localhost:8000/v3` (D2) |
| **Evidence** | Checks (V*, I*, O*, E*), logs, golden reports, optional SQLite telemetry |

**MVP operator workflow:**

```text
intel-devkit-verify
  → [intel-devkit-install if absent/partial]
  → intel-ovms-agentic-setup (-Profile verify)
  → configure-hermes-ovms / configure-openclaw-ovms
  → intel-endpoint-smoke-test-report
```

**Repository layout (target in `training.developer.aipc`):**

```text
training.developer.aipc\
  agent-skills\
  AGENT-SKILLS.md          # optional index at repo root
  Windows_Software_Installation\
    WingetGUI_Installer\Setup_1.ps1
    WingetGUI_Installer\Setup_2.ps1
    OVMS\ovms_agentic_setup.ps1
```

Customer guide: [agent-skills/README.md](agent-skills/README.md)

---

## 5. Milestones and timeline

Indicative **MVP (M0–M3): 6–9 weeks** for a small team.

| Phase | Name | Goal |
|-------|------|------|
| **M0** | Foundation | Schemas, repo scaffold, telemetry, decisions D1–D8, wrapper conventions |
| **M1** | Verify + OVMS | Read-only verify + OVMS inference path **without** requiring agent hosts |
| **M2** | Agent connect | Hermes/OpenClaw provider config (**staged diff**; **`-Apply`** with backup) |
| **M3** | MVP hardening | E2E scenarios, install progress/async, CI schema validation, stakeholder demo |
| **P1** | Developer value | Samples, models, lite RAG, benchmarks (post-MVP) |
| **P2** | Governed scale | MCP gateway, GUI/DB convergence (post-MVP) |

**M1 exit gate:** Verify §4.1, OVMS §4.3, smoke §4.5 on reference HW; Scenario A steps **A1, A2, A5** without Hermes/OpenClaw.

**M2 exit gate:** Provider config §4.4, §4.6; Scenario A full (Hermes); Scenario B (OpenClaw); **no silent config writes**.

**M3 exit gate:** Full MVP checklist; tag `v0.1.0-mvp`; security review scheduled.

---

## 6. P0 skills and current status

| Skill ID | Purpose | Status |
|----------|---------|--------|
| **intel-devkit-verify** | Dev Kit state, OpenVINO GenAI path, OVMS on disk/running, V5 minimal chat | **Functional (M1)** — V1–V5 |
| **intel-devkit-install** | `Setup_1` + **`Setup_2`** (GenAI), preflight I1–I6 | **Functional** — long-running; Admin |
| **intel-ovms-agentic-setup** | Runs `ovms_agentic_setup.ps1`; O1–O6 | **Functional (M1)** |
| **intel-endpoint-smoke-test-report** | E1–E4 chat smoke | **Functional (M1)** — HW validation pending |
| **intel-agent-provider-config** | Hermes/OpenClaw staging + D9 pull | **Partial (M2)** — `-Apply` not done |
| **openvino-coding-assistant** | Lite coding guidance | **Stub / adapter** (M2+) |

Customer quick start: [agent-skills/README.md](agent-skills/README.md)

---

## 7. Progress to date

### M0 — Foundation (largely complete)

- Decision log **D1–D10** (model ids, approvals, and report format)
- JSON schemas (`skill-result-2026-08`, skill cards, validation report)
- Repo tree: `skills/`, `skill-cards/`, `schemas/`, `scripts/windows/`, `adapters/`, `tests/`
- Telemetry scaffold (SQLite; optional)
- Wrapper conventions: exit codes, approval, JSON stdout

### M1 — Verify + OVMS (code complete; HW sign-off in progress)

**Delivered:**

- **`invoke-devkit-verify.ps1`:** V1 installer state; V2 git; V3 `openvino_genai`; V4 OVMS installed/model/running; **V5** minimal inference when server is up
- **`invoke-ovms-agentic-setup.ps1`:** Executes installer **`ovms_agentic_setup.ps1`**; health, chat, optional tool test; before/after `ovms.exe` evidence
- **`endpoint-smoke-test.ps1`:** E1–E4
- **Shared helpers** in `_skill-common.ps1` (discovery, OVMS API, launch/wait, model resolution)
- **Contract tests:** `tests/Run-ContractTests.ps1`, fixtures, golden reports
- **Documentation:** [MANUAL-HW-LAB.md](agent-skills/tests/integration/MANUAL-HW-LAB.md), troubleshooting

**Originally deferred from M1:** full production install skill (partially addressed—see install section), Hermes `-Apply`, CI schema strict mode.

### Install skill (advanced beyond original M1 scope)

**Delivered / iterated (including Aug 2026 lab feedback):**

- **`invoke-devkit-install.ps1`:** Preflight (admin, network, disk); **Setup_1** via child PowerShell (`ExecutionPolicy Bypass`, `Unblock-File`)
- **Setup_2 integration:** Default after successful Setup_1; **`-Setup2Only`**, **`-SkipSetup2`**, **`-ForceSetup2`**, **`-DevKitWorkingDir`** (default `C:\Intel`)
- Checks **I1–I6** (including **I5 Setup_2**, **I6 openvino_genai** path)
- Failure hints, log tails, troubleshooting for execution policy and Setup_1 exit codes
- Clone-first policy; no runtime download of installer/OVMS scripts

### M2 — Agent connect (started, not complete)

- **`configure-hermes-ovms.ps1` / `configure-openclaw-ovms.ps1`:** Staging and D9 pull wiring
- **`-Apply` with backup/rollback:** Not implemented
- Hermes bundle sample YAML; adapter SKILL.md overlays

### M3 — Hardening (not started as phase)

- Async/progress for long install (checklist **G4**)—documented, not implemented
- Full CI JSON Schema validation—local contract tests only
- MVP tag and formal §8 exit—pending

### Repository and delivery

- Git branch **`Devkit4.0`**; intended landing in **`training.developer.aipc`** alongside `Windows_Software_Installation/`
- Handoff zip: `agent-skills/` + root **`AGENT-SKILLS.md`**

---

## 8. Hardware validation progress (reference lab)

**Active testing on a Dev Kit machine (Aug 2026):**

| Step | Result / notes |
|------|----------------|
| **Setup_1** (winget) | Success (~15 packages); manual and skill-driven paths debugged |
| **Skill install wrapper** | Fixed: Unicode parse error, execution policy / unsigned scripts, child PS exit codes |
| **Verify V2-git** | Fixed after Git install + new PowerShell session (PATH) |
| **Verify V3-openvino-genai** | Failed until **Setup_2**; integrated into install skill |
| **Setup_2** | Requires Administrator; default **`C:\Intel\openvino_genai`** |
| **OVMS + smoke** | Next after verify passes (A2, A5) |

**Lessons:**

- Multi-hour installs need operator expectations and future progress signaling (M3.1)
- Lab issues (git PATH, Mark-of-the-Web, PowerShell encoding) documented in [troubleshooting](agent-skills/docs/troubleshooting.md)
- Verify honesty: **V5** fails if chat fails even when disk checks pass

---

## 9. Key decisions (appendix)

| ID | Decision |
|----|----------|
| D1 | Verify model: **Qwen 3.5 0.8B** OpenVINO (CPU) |
| D9 | Agent model: **Qwen 3.6 35B A3B** OpenVINO (`OpenVINO/Qwen3.6-35B-A3B-int4-ov`) |
| D2 | OVMS: `http://localhost:8000/v3` |
| D4 | Agent Skills standard + Hermes/OpenClaw validated |
| D5 | Top-up primary; must handle **Dev Kit absent** (Scenario A′) |
| D7 | Read = no approval; install/network/config = approval |
| D8 | JSON stdout; schema warnings may still exit 0 |
| D10 | Reference HW: Core Ultra Series 3, ≥ 64 GB RAM (documented) |

---

## 10. Risks and open items

- **Long install vs agent timeout** — agents may kill runs before Setup_1/2 finish
- **M1 HW sign-off** — not all golden scenarios signed on reference SKU
- **M2 `-Apply`** — provider config still review-only without automated apply/rollback
- **Setup_2 partial failures** — upstream script may exit 0 with component failures; skill checks folder presence (I6)
- **Security review** — required before external publish
- **Schema CI** — warn-only at runtime; strict validation not in pipeline

---

## 11. Recommended next steps

1. Complete **Setup_2** on lab machine; re-run **verify** (V3 pass)
2. **OVMS verify profile:** `invoke-ovms-agentic-setup.ps1 -Approve -Pull -Profile verify`
3. **Endpoint smoke test**; record in **MANUAL-HW-LAB.md**
4. **M2:** Implement **`-Apply`** for Hermes/OpenClaw; Scenario A/B demos
5. **M3:** Install progress/async (G4), CI schema step, MVP tag **`v0.1.0-mvp`**
6. **Inner-source:** Merge **`Devkit4.0`** into `training.developer.aipc`; README link to `agent-skills/`

---

## 12. Suggested PowerPoint outline

1. Title — Intel AI PC Dev Kit 4.x Agent Skills
2. Vision — Local agent loop on Windows AI PC
3. Scope — In / out of MVP
4. Architecture — Agents → invokers → installer → OVMS
5. Milestones M0–M3 timeline
6. P0 skills table (status)
7. M1 accomplishments — Verify, OVMS, smoke, tests
8. Install evolution — Setup_1 + Setup_2, approvals, JSON evidence
9. Lab validation — What we tested, what we fixed
10. Decisions D1/D9/D2/D7 (compact table)
11. Risks and mitigations
12. Next 30 days — M2 apply, HW sign-off, M3 hardening
13. Appendix — Repo layout, clone-first policy, reference HW

---

## 13. Elevator pitch

**We are building an open-standard Agent Skills pack that wraps the existing Intel AI PC Dev Kit installer and OVMS launchers so any compatible agent can verify, install, serve, and smoke-test local OpenVINO models—with JSON evidence and human approval on every mutating step.**

---

*Update this report when milestones close or HW sign-off completes.*
