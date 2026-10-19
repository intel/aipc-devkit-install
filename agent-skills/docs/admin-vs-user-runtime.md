# Admin vs standard user — Dev Kit and OVMS

Mixing **Administrator install** with **standard-user OVMS** is the usual cause of **“directory is not owned by the current user.”** Skills default to **user-scoped OVMS data** on launch so you can drop elevation as soon as install finishes.

## Golden path (clean Windows lab)

Use this order on a reset test machine (Scenario A′ in [MANUAL-HW-LAB.md](../tests/integration/MANUAL-HW-LAB.md)).

| Phase | Session | What to run |
|-------|---------|-------------|
| **1 — Install** | **Administrator** (UAC via **`-Elevate`** from Hermes, or Admin PowerShell) | `invoke-devkit-install.ps1 -Approve -Elevate` then poll `-WaitInstallJob` — [hermes-install-elevation.md](../hermes-install-elevation.md) |
| **2 — Handoff** | Close Admin window | Sign in as your **daily standard user** (or open **non-elevated** PowerShell as that user) |
| **3 — Track A** | **Standard user** | `invoke-devkit-verify.ps1` → `invoke-ovms-agentic-setup.ps1 -Approve -Pull -Profile verify` → verify again → `endpoint-smoke-test.ps1` → configure Hermes/OpenClaw when ready |

**Setup_1 alone** is not the handoff point if you still need **Setup_2** for verify **V3** (`openvino_genai`). The default install skill runs both while elevated; hand off **after the install skill reports success**, not after Setup_1 only.

**Never** on a clean test: run `ovms_agentic_setup.ps1 -Pull` as Administrator with default `.\models` and `.\ovcache` under the clone — that creates Admin-owned trees and breaks step 3.

### Quick elevation check

```powershell
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
```

Install skill JSON includes **handoff warnings** after a real install. Verify, OVMS, and smoke add a **warning** if you are still elevated.

## What runs as Administrator

| Action | Elevated? | Typical writes |
|--------|-----------|----------------|
| **`invoke-devkit-install.ps1` / `Setup_1.ps1 install`** | **Yes (required)** | Winget packages, Visual Studio components, **`C:\Intel\`**, Program Files, **`C:\temp\logs\install\`** |
| **`Setup_2.ps1` / genai-minimal (default after Setup_1 in install skill)** | **Yes (same Admin session)** | **`C:\Intel\openvino_genai`**, venvs, long CMake/pip builds |
| **Manual `ovms_agentic_setup.ps1 -Pull` as Admin with clone-relative paths** | Avoid | **`models\`**, **`.ovcache\`** under clone **`OVMS`**, owned by **Administrators** |

## What runs as standard user (recommended after install)

| Action | Elevated? | Notes |
|--------|-----------|--------|
| **`invoke-devkit-verify.ps1`** | No | Read-only |
| **`invoke-ovms-agentic-setup.ps1`** (skill launch) | No | Auto **junction** `models`/`.ovcache` under `...\OVMS` → `%USERPROFILE%\OVMS`; **does not** pass absolute `-CacheDir` (OVMS JSON bug). Run **`repair-ovms-user-data-layout.ps1`** after reboot if needed. |
| **`endpoint-smoke-test.ps1`** | No | HTTP to localhost |
| **`configure-*-ovms.ps1`** (staging only) | No | Writes staged diff to JSON only until `-Apply` exists |

## How `ovms_agentic_setup.ps1` uses disk

Run from **`Windows_Software_Installation\OVMS`** (working directory matters):

| Relative path | Purpose |
|---------------|---------|
| **`ovms\`** | Downloaded OVMS binaries (if missing) |
| **`models\`** | Model repository (`-ModelRepositoryPath`, default `models`) |
| **`.ovcache\`** | Compile cache (`-CacheDir`, default `.ovcache`) |

OVMS / Hugging Face tooling may **refuse to write** if those folders were created by another user or by an elevated session.

Verify discovery also checks **`C:\Intel\OVMS`** and **`%USERPROFILE%\OVMS`** — **the user who starts the server must own the cache/repo it writes to**.

## Skill defaults (no extra env on clean lab)

| Variable | Effect |
|----------|--------|
| *(default)* | Skill **detached OVMS launch** uses **`%USERPROFILE%\OVMS\models`** and **`.ovcache`** |
| **`AIPC_OVMS_USER_DATA=1`** | Same paths (explicit opt-in) |
| **`AIPC_OVMS_USE_CLONE_PATHS=1`** | Use clone-relative paths (only if same user/elevation as creator) |

Manual upstream launch as standard user (OVMS JSON bug workaround — junctions + relative defaults):

```powershell
$ovmsDir = '...\Windows_Software_Installation\OVMS'
$userOvms = Join-Path $env:USERPROFILE 'OVMS'
$repo = Join-Path $userOvms 'models'
$cache = Join-Path $userOvms '.ovcache'
New-Item -ItemType Directory -Force -Path $repo, $cache | Out-Null

Set-Location $ovmsDir
# Remove or rename existing .\models / .\.ovcache if they are normal folders (not junctions)
cmd /c mklink /J models $repo
cmd /c mklink /J .ovcache $cache

.\ovms_agentic_setup.ps1 -Model "OpenVINO/Qwen3.5-0.8B-int4-ov" -Target CPU -Pull
```

Do **not** pass `-ModelRepositoryPath` / `-CacheDir` with absolute `C:\Users\...` paths unless upstream/OVMS fixes JSON escaping.

## If you already created Admin-owned OVMS folders (recovery)

**Option A — Prefer on clean retest:** reset machine or delete Admin-owned **`models`** / **`.ovcache`** under the clone and use user paths only.

**Option B — ACL fix (shared machine, lab only):**

```powershell
# Run elevated; replace DOMAIN\user and path
icacls "...\Windows_Software_Installation\OVMS\models" /grant "DOMAIN\user:(OI)(CI)M" /T
icacls "...\Windows_Software_Installation\OVMS\.ovcache" /grant "DOMAIN\user:(OI)(CI)M" /T
```

## Diagnostics

```powershell
whoami
Get-Acl "$env:USERPROFILE\OVMS\models" -ErrorAction SilentlyContinue | Format-List
Get-Acl "...\Windows_Software_Installation\OVMS\models" -ErrorAction SilentlyContinue | Format-List
```

Check the **detached OVMS PowerShell window** for the full error line (often names the directory).

## Skills scope

- **`intel-devkit-install`** requires Admin; JSON warns to **hand off to standard user** after Setup_1/2 complete.
- **`intel-ovms-agentic-setup`** does not retarget old Admin-owned clone folders; it **defaults to profile OVMS data** on skill launch.
- **`AIPC_OVMS_ROOT`** selects **`ovms.exe`** for verify; it does not fix model cache ACLs.
