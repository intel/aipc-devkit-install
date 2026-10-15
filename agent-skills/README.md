# Agent Skills for Intel AI PC Developer Kit

Windows **Agent Skills** for the Intel AI PC Dev Kit: verify the stack, install (with approval), run **OpenVINO Model Server (OVMS)**, and connect **Hermes** or other [Agent Skills](https://agentskills.io/home) hosts to local inference at `http://localhost:8000/v3`.

**Beta testers:** two Hermes paths. **[Beta quick path (Hermes)](#beta-quick-path-hermes)** uses a cloud model to install the Dev Kit, then switches Hermes to local OVMS. **[Beta path: Muse Glimmer, then Dev Kit](#beta-path-muse-glimmer-then-dev-kit)** installs Hermes, runs OVMS prerequisites, starts Muse Glimmer, then installs the Dev Kit from Hermes. Engineers and manual PowerShell flows are under **[Manual path](#manual-path-powershell)** and **[Reference](#reference)**.

---

## Beta quick path (Hermes)

Goal: on a **clean Windows PC**, use **Hermes** and these skills to install the Dev Kit, bring up OVMS with the **large agent model**, and switch Hermes to **local** inference.

| Approx. time | What |
|--------------|------|
| ~15 min | Install Hermes + **cloud** model (so Hermes can run skills) |
| ~10 min | Clone Dev Kit repo, unpack **agent-skills**, register skills in Hermes |
| hours | Dev Kit install (elevated; approve UAC + Hermes prompts) |
| ~1–3 h | OVMS + agent model download (first time) |
| ~5 min | Provider config + restart Hermes → local **Qwen3.6-35B-A3B** |

**Hardware:** Intel® Core™ Ultra (Series 3) with **≥ 64 GB RAM** recommended for the large local agent model. Details: [Recommended hardware](docs/recommended-hardware.md).

### Install Hermes (standard user PowerShell)

```powershell
irm https://hermes-agent.nousresearch.com/install.ps1 | iex
```

When the wizard asks:

| Prompt | Choose |
|--------|--------|
| How would you like to set up Hermes? | **1. Quick Setup** |
| Browser opens | Minimize it; return to PowerShell |
| Waiting for approval | **Ctrl+C** to continue |
| Terminal backend | **7** Keep current (local) |
| Connect a messaging platform? | **2** Skip |
| Start the gateway now after install? | **2** No |
| Start the gateway automatically? | **2** No |

Exit Hermes (**Ctrl+C**) when the installer finishes.

### Cloud model for Hermes (during beta setup)

Hermes needs a **cloud** provider to drive install/OVMS skills before local OVMS is ready. Example: [NVIDIA Build](https://build.nvidia.com/) (free tier with NVIDIA developer account, no card required for API key flow).

1. Sign in → open a capable model (e.g. **nemotron-3-ultra-550b-a55b**).
2. Account (top right) → **API Keys** → **Generate** → copy the key to Notepad.

In PowerShell:

```powershell
hermes model
```

| Prompt | Value |
|--------|--------|
| Provider | **13. Nvidia NIM** |
| NVIDIA_API_KEY | paste your key |
| Base URL | press **Enter** (default) |
| Default model | **31.** `nvidia/nemotron-3-ultra-550b-a55b` (or your chosen model) |

You will switch to **local OVMS** at the end of this guide.

### Dev Kit repo + agent-skills layout

Skills expect **`agent-skills`** beside **`Windows_Software_Installation`** in the same root (example: `aipc-devkit-install`).

**Caution:** Try to keep the download directory path short. OVMS may fail if the directory path is too long.

```powershell
cd $env:USERPROFILE\Downloads
git clone https://github.com/intel/aipc-devkit-install
```

1. Copy **`devkit4.0-agent-skills.zip`** into the same folder (e.g. `Downloads`).
2. **Unblock** the zip (Properties → **Unblock**) if Windows blocked it.
3. Extract the zip, then place the folder so the tree looks like:

```text
C:\Users\<you>\Downloads\aipc-devkit-install\
  agent-skills\          ← rename from devkit4.0-agent-skills
  Windows_Software_Installation\
    WingetGUI_Installer\
    OVMS\
```

Example rename (adjust paths):

```powershell
cd $env:USERPROFILE\Downloads\aipc-devkit-install
Expand-Archive -LiteralPath "$env:USERPROFILE\Downloads\devkit4.0-agent-skills.zip" -DestinationPath . -Force
Rename-Item -LiteralPath .\devkit4.0-agent-skills -NewName agent-skills
Get-ChildItem -Path .\agent-skills -Recurse -Filter *.ps1 | Unblock-File
```

Set a variable for the rest of the beta path (adjust if your clone lives elsewhere):

```powershell
$DevKitRoot = "$env:USERPROFILE\Downloads\aipc-devkit-install"
$AgentSkills = Join-Path $DevKitRoot 'agent-skills'
$PortableSkills = Join-Path $AgentSkills 'skills'
```

### Register Intel skills in Hermes

Hermes loads skills from **`~/.hermes/skills/`** and from extra folders you list under **`skills.external_dirs`** in **`config.yaml`**. That is the [documented way](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills) to use this pack **without copying** each skill into `.hermes/skills`.

**1. Open Hermes config** (native Windows often uses AppData, not `%USERPROFILE%\.hermes`):

```powershell
hermes config edit   # opens config.yaml in your editor (official path)
```

If you prefer to open the file directly, try (one of these usually exists):

```powershell
notepad "$env:LOCALAPPDATA\hermes\config.yaml"
# or
notepad "$env:USERPROFILE\.hermes\config.yaml"
```

**2. Add the portable skills directory** (forward slashes are fine in YAML). Point **`external_dirs`** at **`agent-skills/skills`**, the folder that contains **`software-development`**. Do not point it at `software-development` itself.

```yaml
skills:
  external_dirs: [C:/Users/<you>/Downloads/aipc-devkit-install/agent-skills/skills]
```

Example (PowerShell → YAML path):

```powershell
($PortableSkills -replace '\\','/')
```

Paste that path into **`external_dirs`** (replace the example path, or append to an existing `external_dirs` array in your file). If **`skills:`** already exists in your config, add or extend **`external_dirs`** under it—do not create a second top-level **`skills`** key.

**3. Save the config file** and close the editor. Hermes does not need to be running for this step (you only edited **`config.yaml`** via **`hermes config edit`** or Notepad).

In **PowerShell**, confirm the path was saved (**`hermes config get`** requires a dotted key—it does not dump the whole file):

```powershell
hermes config get skills.external_dirs
```

**4. Confirm registration**

Start Hermes from **`agent-skills`** (first time since config edit, or after you exited following the Hermes installer—do not run slash commands in plain PowerShell):

```powershell
cd $AgentSkills   # or your path to agent-skills
hermes
```

At the **`hermes>`** prompt (inside the CLI), run:

```text
/skills list
```

You should see Intel skill IDs such as **`intel-devkit-verify`** under the category **`software-development`**.

### Hermes conversation (copy in order)

**Important:**

- When you are using the skills, Hermes may ask for permission to perform steps. Please approve. Denying or timing out can send the agent down unintended paths and look like a bug.
- When Hermes finishes a skill, look at what it says to run **next**. Don’t treat every red item as a failed install—often it’s just telling you the next skill in the path.

Continue in the **same Hermes session** from **Confirm registration** above (you already started **`hermes`** from **`agent-skills`**). Type or paste the prompts below at the **`hermes>`** prompt in order. For a new line without sending the message, use **Shift+Enter** (on Windows Terminal, **Ctrl+Enter** or **Ctrl+J** if **Shift+Enter** does not work).

**1. Verify only**

```text
Use the intel-devkit-verify skill only. Explain the result. Do not run any other skill. Do not tell me to run .ps1 files by path.
```

**2. Dev Kit install**

```text
Use the intel-devkit-install skill only. Do not run any other skill. Do not tell me to run .ps1 files by path.
```

Install may run **hours** in a separate Administrator window.

**3. OVMS + agent model**

```text
Install OVMS and get it ready for agent use.
```

**4. Hermes → local OVMS**

```text
Configure Hermes to use OVMS as the inference provider.
```

When Hermes confirms local setup, **Ctrl+C** to exit, then in **PowerShell** switch the **provider** to local OVMS:

```powershell
hermes config set model.provider custom
hermes config set model.base_url http://localhost:8000/v3
hermes config set model.default "OpenVINO/Qwen3.6-35B-A3B-int4-ov"
hermes
```

**Success:** the prompt should show **OpenVINO/Qwen3.6-35B-A3B-int4-ov**, and chat should hit OVMS on port **8000** (not NIM).

This concludes the required steps for the beta test. Please report your findings to the development team.

### Beta flow (skills)

```text
intel-devkit-verify
    → intel-devkit-install (if needed; UAC + poll)
    → intel-devkit-verify
    → intel-ovms-agentic-setup (-Profile agent)
    → intel-agent-provider-config (optional in JSON but recommended)
    → restart Hermes → local chat
```

Say **`user_message`** only. Follow **`next_skill`** when the user's request includes that step, and do not say the skill id. Do not paste `scripts\windows\*.ps1` paths to users. See [Agent skill output](docs/agent-skill-output.md).

### Beta troubleshooting

| Issue | See |
|-------|-----|
| Install / Setup_1 failures | [Troubleshooting](docs/troubleshooting.md) |
| Admin install vs user OVMS | [Admin vs standard user](docs/admin-vs-user-runtime.md) |
| Hermes UAC install loop | [Hermes install elevation](docs/hermes-install-elevation.md) |
| Verify says re-install but GenAI is OK | Pull latest **agent-skills** (OVMS-only gap routes to OVMS setup, not reinstall) |
| **`/skills list`** does not show `intel-devkit-*` | Fix **`skills.external_dirs`** in **`config.yaml`**, exit and start **`hermes`** again; run **`hermes config get skills.external_dirs`** |

---

## Beta path: Muse Glimmer, then Dev Kit

Goal: on a **clean Windows PC**, install **Hermes**, run the OVMS prerequisites script, run the Muse Glimmer setup script, restart Hermes, then install the Dev Kit with **`/intel-devkit-install`**.

| Approx. time | What |
|--------------|------|
| ~15 min | Install Hermes |
| ~10 min | Clone the Dev Kit repo and unpack **agent-skills** |
| ~10 min | OVMS prerequisites (Administrator) |
| ~1–3 h | Muse Glimmer download and Hermes config |
| hours | Dev Kit install from Hermes |

**Hardware:** Intel® Core™ Ultra (Series 3) with **≥ 64 GB RAM** recommended for Muse Glimmer. Details: [Recommended hardware](docs/recommended-hardware.md).

Use a **standard user** for Hermes and for the Muse Glimmer script. Use an **Administrator** PowerShell window only for OVMS prerequisites. The Dev Kit install asks for Administrator through the Windows UAC prompt.

### 1. Install Hermes

Install Hermes with **[Install Hermes (standard user PowerShell)](#install-hermes-standard-user-powershell)** above. Skip **[Cloud model for Hermes](#cloud-model-for-hermes-during-beta-setup)**. This path uses Muse Glimmer on OVMS, not NVIDIA NIM.

### 2. Lay out the repo

Follow **[Dev Kit repo + agent-skills layout](#dev-kit-repo--agent-skills-layout)** above. Both scripts below read `Windows_Software_Installation\OVMS` from that clone. The full Dev Kit installer has not run yet.

### 3. OVMS prerequisites

Open **PowerShell as Administrator**. This installs the VC++ x64 redistributable, Git, and winget if they are missing, and unblocks the OVMS scripts. It does not download OVMS or Muse Glimmer.

```powershell
$DevKitRoot = "$env:USERPROFILE\Downloads\aipc-devkit-install"
cd (Join-Path $DevKitRoot 'Windows_Software_Installation\OVMS')
.\Setup_OVMS_Prerequisites.ps1 -Target GPU
```

Adjust `$DevKitRoot` if the clone lives elsewhere. Close the Administrator window when the script finishes.

### 4. Muse Glimmer

Open a **standard user** PowerShell window.

```powershell
$DevKitRoot = "$env:USERPROFILE\Downloads\aipc-devkit-install"
$AgentSkills = Join-Path $DevKitRoot 'agent-skills'
cd $AgentSkills
.\scripts\windows\setup-hermes-muse-glimmer.ps1
```

Answer **yes** to download Muse Glimmer and start OVMS on port **8000**. Answer **yes** again when the script asks to change Hermes. Leave the OVMS window open. The script points Hermes at `http://localhost:8000/v3`, sets the model to **OpenVINO/Muse-Glimmer-30B-int4-ov**, and adds `agent-skills/skills` to `skills.external_dirs`.

### 5. Restart Hermes

Exit any open Hermes session, then start it again:

```powershell
hermes
```

At the **`hermes>`** prompt, run:

```text
/skills list
```

The prompt should show **OpenVINO/Muse-Glimmer-30B-int4-ov**. **`intel-devkit-install`** should be listed under **`software-development`**.

### 6. Install the Dev Kit

In that Hermes session:

```text
/intel-devkit-install
```

Approve permission prompts. Click **Yes** on the Windows UAC prompt. Install may run **hours** in a separate Administrator window. Leave Hermes running as the standard user.

### This path

```text
Install Hermes
    → Setup_OVMS_Prerequisites.ps1 (Administrator, -Target GPU)
    → setup-hermes-muse-glimmer.ps1 (standard user)
    → restart Hermes
    → /intel-devkit-install
```

**Success:** Hermes is using **OpenVINO/Muse-Glimmer-30B-int4-ov** on port **8000**, and the Dev Kit install completes. Report findings to the development team.

---

## What you get

- **Verify** — Dev Kit state, OpenVINO GenAI, OVMS readiness (read-only JSON).
- **Install** — Setup_1 + GenAI path (approval + Admin; Hermes uses **-Elevate** + job poll).
- **OVMS setup** — Smoke (**0.8B**) or **agent** (**35B A3B**) profile.
- **Provider config** — Stage Hermes/OpenClaw for `http://localhost:8000/v3` (manual switch / new chat).
- **Smoke report** — Chat completion against the local endpoint.
- **Continue coding assistant** — same OVMS Qwen3.6 35B model on **`http://localhost:8000/v3`** + merge Continue config ([skill](skills/software-development/openvino-coding-assistant/SKILL.md)).

---

## Manual path (PowerShell)

For labs without Hermes, run invokers from **`agent-skills`**:

| Step | Command |
|------|---------|
| Verify | `.\scripts\windows\invoke-devkit-verify.ps1` |
| Install (Admin) | `.\scripts\windows\invoke-devkit-install.ps1 -Approve` |
| Install (Hermes user + UAC) | `.\scripts\windows\invoke-devkit-install.ps1 -Approve -Elevate` then poll **-WaitInstallJob** |
| OVMS agent | `.\scripts\windows\invoke-ovms-agentic-setup.ps1 -Approve -Pull -Profile agent` |
| Hermes provider | `.\scripts\windows\configure-hermes-ovms.ps1 -Approve` |
| Smoke | `.\scripts\windows\endpoint-smoke-test.ps1` |
| Continue + Qwen3.6 35B | `.\scripts\windows\invoke-openvino-coding-assistant-setup.ps1 -Approve -Pull -Apply` |

**OVMS is not installed by Setup_1/2 alone** — run OVMS setup after GenAI is present. Only **install** needs elevation; run verify/OVMS/configure as **standard user** when possible ([admin-vs-user-runtime.md](docs/admin-vs-user-runtime.md)).

---

## Reference

### Models

| Use | Model |
|-----|--------|
| Verification / smoke | `OpenVINO/Qwen3.5-0.8B-int4-ov` |
| Hermes / OpenClaw local agent | `OpenVINO/Qwen3.6-35B-A3B-int4-ov` |
| VS Code Continue | `OpenVINO/Qwen3.6-35B-A3B-int4-ov` on port **8000** → API id **`Qwen3.6-35B-A3B`** |

Use the exact name from `GET http://localhost:8000/v3/models` after OVMS starts.

### Skill IDs

| Skill ID | Purpose |
|----------|---------|
| `intel-devkit-verify` | Read-only environment check |
| `intel-devkit-install` | Dev Kit install (approval required) |
| `intel-ovms-agentic-setup` | OVMS verify or agent profile |
| `intel-agent-provider-config` | Hermes / OpenClaw local provider staging |
| `intel-endpoint-smoke-test-report` | Endpoint smoke test |
| `openvino-coding-assistant` | VS Code Continue + Qwen3.6 35B (:8000) |

Cards: [`skill-cards/`](skill-cards/). Portable definitions: [`skills/`](skills/).

### Environment variables (non-default layouts)

| Variable | Purpose |
|----------|---------|
| **`AIPC_DEVKIT_INSTALL_ROOT`** | Installer repo root (contains `Windows_Software_Installation\`) |
| **`AIPC_OVMS_ROOT`** | Folder with **`ovms.exe`** |
| **`AIPC_DEVKIT_WORKING_DIR`** | `openvino_genai` parent (default `C:\Intel`) |

Full list and discovery order: [Implementation status — conventions](docs/implementation-status.md). OVMS-only slice: `fetch-devkit-ovms-slice.ps1` (see [Troubleshooting](docs/troubleshooting.md)).

### Other agents

Cursor, Claude Code, Gemini CLI, OpenCode, Goose, OpenClaw: add [`skills/`](skills/) to the host’s skills path. [Agent Skills compatibility](docs/agent-skills-compatibility.md).

### Approvals

Mutating or network skills require **`-Approve`**. Provider config is **staged** for review; **`-Apply`** is not automatic for Hermes—use **`local_provider_handoff`** / **`hermes model`**.

---

## For engineers and contributors

[Implementation status](docs/implementation-status.md) · [M1 completion](docs/M1-COMPLETION.md) · [Planning](docs/planning/)

Intel, Intel Core, and Intel Core Ultra are trademarks of Intel Corporation or its subsidiaries.
