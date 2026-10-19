# Manual hardware lab gate (S8)

Until CI exists, run on reference Intel AI PC and attach logs here.

**Pack under test (2026-09-10):** OVMS hardening (preflight, pull lock, port policy, model intent) + Hermes **`local_provider_handoff`** (default **`configure-*` without `-Pull`**).

## Reference config (D10)

| Field | Value |
|-------|--------|
| Processor | Intel® Core™ Ultra (Series 3) |
| Memory | ≥ 64 GB |
| OS | Windows 11 |
| Dev Kit path | Clone root beside `agent-skills/` (e.g. `...\aipc-devkit-install-main`) |
| Verify model (D1) | `OpenVINO/Qwen3.5-0.8B-int4-ov` |
| Agent model (D9) | `OpenVINO/Qwen3.6-35B-A3B-int4-ov` |
| OVMS for D9 | **≥ 2026.3.1** (`python_on`); **`upgrade-ovms-runtime.ps1 -Approve`** if Dev Kit shipped older OVMS. D9 default **GPU** (`-Profile agent`). |
| Target (D9) | GPU (lab-validated); CPU optional via `-Target CPU` |

### Documented lab units (sign-off hardware)

| Unit | Operator | Processor | RAM | OS | Notes |
|------|----------|-------------|-----|-----|--------|
| **optane** (dev) | optane | Intel® Core™ Ultra X7 358H | 31.4 GB | Windows 11 Pro 25H2 | A′ + M1 + Hermes A3/A4 on **D1**; D9 not run (below D10 RAM) |
| **optane1** | optane1 | (Series 3 ref) | ≥ 64 GB | Windows 11 | M1 2026-08-28; D10-class agent model target |

D10 table above remains the **MVP reference** target; runs on **optane** are valid for install/OVMS/Hermes on **0.8B** with hardware called out in **Runs**.

---

## In-place refresh (no OS reset) — Scenario A″

Use the **same PC** after a prior lab pass. You do **not** need to reinstall Windows or re-run Setup_1/2 if Dev Kit is already present.

### What to stop / clear (minimal)

| Item | Action | Why |
|------|--------|-----|
| **OVMS** | Stop **`ovms.exe`** (Task Manager) and close any **detached** PowerShell window that ran `ovms_agentic_setup.ps1` | Frees **:8000**; avoids wrong model on port during port-policy tests |
| **Pull lock** | Delete **`%USERPROFILE%\OVMS\.skill-state\pull-state.json`** if present (only when no download is running) | Unblocks **`PULL_IN_PROGRESS`** after a crashed or killed launcher. **Missing folder is normal** until the first **`-Pull`** with this skill pack. |
| **Old skill pack** | Replace **`agent-skills\`** with this zip (see below) | New invokers and SKILL text |
| **MOTW** | **`Unblock-File`** on zip and all **`*.ps1`** under `agent-skills` | Required after zip extract |

Save JSON with **`Out-File -Encoding utf8`** (not `Tee-Object`) so Hermes/lab parsers keep one JSON object.

```powershell
$DevKitRoot = 'C:\path\to\aipc-devkit-install-main'   # parent of agent-skills + Windows_Software_Installation
cd "$DevKitRoot\agent-skills"

Get-Process ovms -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item -LiteralPath (Join-Path $env:USERPROFILE 'OVMS\.skill-state\pull-state.json') -ErrorAction SilentlyContinue
```

**Not from agent-skills:** an empty **`C:\temp\ovms.txt`** (or an empty **`C:\temp\logs\ovms`**) is unrelated to pull lock. OVMS skill output is JSON on stdout; upstream **`ovms_agentic_setup.ps1`** logs to its **detached PowerShell window**. Safe to delete stray **`C:\temp\ovms.txt`**.

### Reset OVMS user data + models (recommended for this pack)

Use this when you want a **cold pull** and a clean test of disk preflight, first **`-Pull`** (no **`-ApproveRetryPull`**), and junction layout — **without** reinstalling Windows or Dev Kit.

**Removes (large download again):**

- **`%USERPROFILE%\OVMS`** — all **`models`** and **`.ovcache`** for the signed-in lab user
- **`models`** / **`.ovcache`** under the Dev Kit **`...\Windows_Software_Installation\OVMS`** tree (junctions or real folders only — **not** `ovms.exe`)

**Does not remove:**

- **`ovms.exe`** / Dev Kit OVMS install under the clone or **`C:\Intel\OVMS`**
- **`C:\Intel\openvino_genai`**, Setup_1/2 payloads, or the Dev Kit clone itself

Run as the **same standard user** you use for Track A (not Administrator), after OVMS is stopped:

```powershell
$DevKitRoot = 'C:\path\to\aipc-devkit-install-main'
$OvmsCwd = Join-Path $DevKitRoot 'Windows_Software_Installation\OVMS'

Get-Process ovms -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item -LiteralPath (Join-Path $env:USERPROFILE 'OVMS\.skill-state\pull-state.json') -ErrorAction SilentlyContinue

# User-scoped weights and cache (primary store for skill launch)
$userOvms = Join-Path $env:USERPROFILE 'OVMS'
if (Test-Path -LiteralPath $userOvms) {
    Remove-Item -LiteralPath $userOvms -Recurse -Force
}

# Clone OVMS working dir: remove models/.ovcache only (junction-safe)
foreach ($name in @('models', '.ovcache')) {
    $linkPath = Join-Path $OvmsCwd $name
    if (-not (Test-Path -LiteralPath $linkPath)) { continue }
    $item = Get-Item -LiteralPath $linkPath -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        cmd.exe /c "rmdir `"$linkPath`""
    } else {
        Remove-Item -LiteralPath $linkPath -Recurse -Force
    }
}

# Optional leftovers from junction repair (small backups)
Get-ChildItem -LiteralPath $OvmsCwd -Directory -Filter 'models.pre-junction.*' -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force
Get-ChildItem -LiteralPath $OvmsCwd -Directory -Filter '.ovcache.pre-junction.*' -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force
```

If you previously used **`AIPC_OVMS_USE_CLONE_PATHS=1`** or pulled into **`C:\Intel\OVMS\models`**, also delete that **`models`** tree (and **`.ovcache`** beside it) **only** if you no longer need those copies — keep **`ovms.exe`**.

After wipe, first OVMS run recreates profile folders and junctions (`invoke-ovms-agentic-setup.ps1` or **`repair-ovms-user-data-layout.ps1`**). Expect **full model download** time for **`-Pull`**.

### What you usually keep (if you skip the reset above)

| Item | Keep? |
|------|--------|
| Dev Kit clone, **`C:\Intel\openvino_genai`**, winget-installed payloads | **Yes** — no reinstall for A″ |
| **`%USERPROFILE%\OVMS`** | **Yes** only for fast re-test (reuse, **`-ApproveRetryPull`**) |
| Hermes **`config.yaml`** | **Yes** unless re-testing **first-time handoff** |

### Optional cleanup (only when testing that scenario)

| Goal | Optional action |
|------|------------------|
| **Port conflict / `-ApproveStopOvms`** | Leave **wrong** model running on :8000 once to validate **`PORT_CONFLICT`** / stop flow |
| **Hermes “switch to local” from cloud** | New Hermes chat after handoff; optionally revert config to cloud first to repeat the playbook |
| **Single-model delete only** | Remove one folder under **`%USERPROFILE%\OVMS\models\OpenVINO\`** instead of full reset |

### Deploy new zip on the lab machine

```powershell
# On build machine or after copying devkit4.0-agent-skills.zip to the lab:
Unblock-File -LiteralPath "$env:USERPROFILE\Downloads\devkit4.0-agent-skills.zip"
$DevKitRoot = 'C:\path\to\aipc-devkit-install-main'
Rename-Item "$DevKitRoot\agent-skills" "$DevKitRoot\agent-skills.bak.$(Get-Date -Format yyyyMMdd)" -ErrorAction SilentlyContinue
Expand-Archive -LiteralPath "$env:USERPROFILE\Downloads\devkit4.0-agent-skills.zip" -DestinationPath $DevKitRoot -Force
Get-ChildItem "$DevKitRoot\agent-skills" -Recurse -Filter *.ps1 | Unblock-File
```

Re-register Hermes external skills if you use **`skills.external_dirs`** (path unchanged if `agent-skills` path is the same).

---

## M1 sign-off (no agents)

Run from `agent-skills/` on Dev Kit–present hardware. Save JSON stdout for each step.

```powershell
.\scripts\windows\invoke-devkit-verify.ps1 | Out-File verify-m1.json -Encoding utf8

.\scripts\windows\invoke-ovms-agentic-setup.ps1 -Approve -Pull -Profile verify |
  Out-File ovms-m1.json -Encoding utf8

.\scripts\windows\invoke-devkit-verify.ps1 | Out-File verify-after-ovms-m1.json -Encoding utf8

.\scripts\windows\endpoint-smoke-test.ps1 | Out-File smoke-m1.json -Encoding utf8
```

Pass criteria:

- Verify: `functional_status` pass or partial (no false pass on absent)
- OVMS setup: **O2** (model intent for D1) + **O3** + **O4** pass on verify profile; **`agent_inference_ready`** may be **false** (expected for verify-only)
- Post-OVMS verify: **V4-ovms-running**, **V5-minimal-inference**, and **V6-agentic-inference** reflect server state (V6 fail is OK when only D1 is loaded)
- Smoke: `functional_status` pass; note `latency_ms`

**A″ extra checks (hardening):**

- Second run with OVMS still up: `invoke-ovms-agentic-setup.ps1 -Approve -Profile verify` (no `-Pull`) → **O0** reuse, no second download
- `configure-hermes-ovms.ps1 -Approve` while OVMS **down** → **`functional_status=blocked`**, `error.code=OVMS_NOT_READY`, `next_skill=intel-ovms-agentic-setup`

Lab notes: standard-user session; junctions under Dev Kit **`...\OVMS`** → **`%USERPROFILE%\OVMS`** — [admin-vs-user-runtime.md](../../docs/admin-vs-user-runtime.md), [troubleshooting.md](../../docs/troubleshooting.md).

---

## Hermes — switch to local (Scenario A3 / A4, updated flow)

**Order:** OVMS first (D1 or D9), then provider skill, then **manual** Hermes switch (not automatic mid-session).

### D1 on 32 GB dev (0.8B)

```powershell
.\scripts\windows\invoke-ovms-agentic-setup.ps1 -Approve -Pull -Profile verify |
  Out-File ovms-hermes-d1.json -Encoding utf8

.\scripts\windows\configure-hermes-ovms.ps1 -Approve -Model 'OpenVINO/Qwen3.5-0.8B-int4-ov' |
  Out-File configure-hermes-a3.json -Encoding utf8
```

Pass: **`O1-agent-ovms-model`** pass (or skip with endpoint already serving D1), **`C1-staged-diff`** pass, JSON includes **`local_provider_handoff`**.

### D9 on 64 GB D10

```powershell
.\scripts\windows\invoke-ovms-agentic-setup.ps1 -Approve -Pull -Profile agent |
  Out-File ovms-agent-d9.json -Encoding utf8
# Resume after partial pull: add -ApproveRetryPull
# Wrong model on :8000: add -ApproveStopOvms after user approval

.\scripts\windows\configure-hermes-ovms.ps1 -Approve |
  Out-File configure-hermes-d9.json -Encoding utf8
```

**Do not** rely on **`configure-hermes-ovms -Approve -Pull`** alone for first-time D9 unless you also pass **`-ApproveRetryPull`** when weights already exist (default configure **`-Pull:$false`** avoids parallel pulls).

**`-Apply` not implemented.** Use **`local_provider_handoff.hermes_cli_steps`** or:

| Install | Typical config path |
|---------|---------------------|
| Hermes Desktop (Windows) | `%LOCALAPPDATA%\hermes\config.yaml` |
| Some CLI layouts | `%USERPROFILE%\.hermes\config.yaml` |

```yaml
model:
  default: "OpenVINO/Qwen3.6-35B-A3B-int4-ov"
  provider: "custom"
  base_url: "http://localhost:8000/v3"
```

**A4 pass:** new chat after **`hermes model`** (or equivalent); one message answered via local OVMS; `GET /v3/models` lists the same model id.

### Blocked codes to exercise on A″

| `error.code` | How to trigger |
|--------------|----------------|
| `OVMS_NOT_READY` | `configure-hermes-ovms.ps1 -Approve` with OVMS stopped |
| `PORT_CONFLICT` | `:8000` in use, wrong model, no `-ApproveStopOvms` |
| `RETRY_PULL_REQUIRES_APPROVAL` | `-Pull` when model folder exists or partial tree; without `-ApproveRetryPull` |
| `DISK_INSUFFICIENT` | (lab only if volume under threshold) |
| `MODEL_INTENT_MISMATCH` | `-SkipLaunch` while server serves a different model than `-Model` |

---

## Scenario A′ — clean Windows (admin handoff)

Reset OS (or fresh VM). Use a **standard daily account** for Track A; elevate only for install.

| Step | Session | Command / action |
|------|---------|------------------|
| Prep | Standard | Clone Dev Kit + extract/unblock `agent-skills` beside `Windows_Software_Installation` |
| A′-0 | Standard | `invoke-devkit-verify.ps1` → **`devkit_status=absent`**, `next_skill=intel-devkit-install` |
| A′-1 | **Administrator** | `invoke-devkit-install.ps1 -Approve` (Setup_1 + default Setup_2); read JSON **handoff warnings** |
| A′-2 | **Standard** | Close Admin window; `invoke-devkit-verify.ps1` (V3 pass; V4/V5 skip until OVMS) |
| A′-3 | Standard | `invoke-ovms-agentic-setup.ps1 -Approve -Pull -Profile verify` |
| A′-4 | Standard | `invoke-devkit-verify.ps1` (V4-ovms-running, V5 when server up) |
| A′-5 | Standard | `endpoint-smoke-test.ps1` |
| A′-6 | Standard | Hermes flow: OVMS D9 → `configure-hermes-ovms.ps1 -Approve` → handoff → A4 chat |

Pass = M1 criteria + **no** ownership errors + **no** elevated session for A′-2 onward. Save JSON as `verify-a-prime-*.json`.

---

## Scenario D — VS Code Continue + Qwen3.6 35B (D13)

Standard user; Dev Kit + VS Code + **Continue.continue** extension. Uses port **8000** (same OVMS as Hermes/D9).

| Step | Command / action | Pass |
|------|------------------|------|
| D1 | `invoke-openvino-coding-assistant-setup.ps1 -Approve -Pull -Apply` | JSON **functional_status=pass**; **P2**, **P4** pass |
| D2 | `GET http://localhost:8000/v3/models` | Lists **`Qwen3.6-35B-A3B`** |
| D3 | Reload VS Code; Continue → select **OVMS Qwen3.6-35B-A3B** | One chat reply from local OVMS |
| D4 | (Optional) Enable autocomplete in Continue UI; type in a code file | Suggestion or clear timeout message |

Save JSON: `continue-coder-setup.json`. If **8000** is serving the wrong model: `-ApproveStopOvms` after user approval.

OVMS-only retry:

```powershell
.\scripts\windows\invoke-ovms-agentic-setup.ps1 -Approve -Pull `
  -Model 'OpenVINO/Qwen3.6-35B-A3B-int4-ov' -Target GPU -Port 8000
.\scripts\windows\configure-continue-ovms.ps1 -Approve -Apply
```

---

## Contract tests (any machine)

```powershell
cd tests
.\Run-ContractTests.ps1
```

---

## Full MVP checklist

- [x] Scenario A — A1, A2, A5; **A3/A4 Hermes (D1 0.8B on 32 GB dev; D9 on 64 GB D10 — see Runs)**
- [x] Scenario A′ (optane 64 GB clean install 2026-09-02; Admin install + standard-user M1/D9/Hermes — see Runs)
- [ ] Scenario A″ — in-place skills refresh + hardening/handoff (this pack)
- [ ] Scenario B
- [ ] Scenario C

---

## Runs

| Date | Operator | Scenario | Result | Log link |
|------|----------|----------|--------|----------|
| 2026-09-10 | | A″ hardening + handoff | | |
| 2026-09-02 / 03 | optane | A′ + M1 + **D9** + Hermes **A3/A4** | **Pass** | **64 GB** D10-class. Artifacts: `Downloads\valid\`. D9 **3.6-35B-A3B**; manual Hermes apply. |
| 2026-09-01 | optane | A3/A4 Hermes + OVMS (D1 0.8B) | **Pass** | 31.4 GB; Hermes custom endpoint; chat OK |
| 2026-08-31 | optane | A′ (install) + M1 A′-4/A′-5 | **Pass** | Junction → `%USERPROFILE%\OVMS` |
| 2026-08-28 | optane1 lab | M1 (A1/A2/A5) + post-OVMS verify | **Pass** | D1 smoke **671 ms** |
