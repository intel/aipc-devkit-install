# Agent Skills for Intel AI PC Developer Kit

Windows **Agent Skills** for the Intel AI PC Dev Kit. The main step is to install the Dev Kit. Optional skills can verify the stack, run **OpenVINO Model Server (OVMS)**, and connect **Hermes** or other [Agent Skills](https://agentskills.io/home) hosts to local inference at `http://localhost:8000/v3`.

Two ways to install the Dev Kit with Hermes:

- **[Quick path](#quick-path)** — for Hermes users who already have an inference provider configured.
- **[Bootstrap path](#bootstrap-path)** — for a new Hermes setup. Muse Glimmer on OVMS becomes the inference provider, then **`/intel-devkit-install`** installs the Dev Kit.

Optional skills are under **[Other capabilities](#other-capabilities)**. PowerShell steps for a setup without Hermes are in **[Manual path](#manual-path-powershell)**. Model names, skill IDs, and other details are in **[Reference](#reference)**.

---

## Quick path

For Hermes users who already have an inference provider configured. The path includes cloning the Dev Kit repo, registering the skills in Hermes, and installing the Dev Kit.

| Approx. time | What |
|--------------|------|
| ~10 min | Clone the Dev Kit repo and register skills in Hermes |
| hours | Dev Kit install (elevated; approve UAC + Hermes prompts) |

To do so, please follow:

If Hermes is not installed, or no inference provider is configured yet, use [Install Hermes](#install-hermes-standard-user-powershell) and [Cloud model for Hermes](#cloud-model-for-hermes) first. Otherwise continue at [Clone the Dev Kit repo](#clone-the-dev-kit-repo).

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

### Cloud model for Hermes

Hermes needs a **cloud** provider to run the install skill before a local model is available. Example: [NVIDIA Build](https://build.nvidia.com/) (free tier with NVIDIA developer account, no card required for API key flow).

1. Sign in → open a capable model (e.g. **nemotron-3-ultra-550b-a55b**).
2. Account (top right) → **API Keys** → **Generate** → copy the key to Notepad.

In PowerShell:

```powershell
hermes model
```

| Prompt | Value |
|--------|--------|
| Provider | **Nvidia NIM** |
| NVIDIA_API_KEY | paste your key |
| Base URL | press **Enter** (default) |
| Default model | `nvidia/nemotron-3-ultra-550b-a55b` (or your chosen model) |

Switching Hermes to a local model later is optional. See [Other capabilities](#other-capabilities).

### Clone the Dev Kit repo

Skills expect **`agent-skills`** beside **`Windows_Software_Installation`** in the same root. The clone already has that layout.

**Caution:** Try to keep the download directory path short. OVMS may fail if the directory path is too long.

```powershell
cd $env:USERPROFILE\Downloads
git clone https://github.com/intel/aipc-devkit-install
```

```text
C:\Users\<you>\Downloads\aipc-devkit-install\
  agent-skills\
  Windows_Software_Installation\
    WingetGUI_Installer\
    OVMS\
```

**Note:** `<you>` is a placeholder for your Windows user name, the folder under `C:\Users\`. Replace it with that name, for example `C:\Users\jane\Downloads\...`. Do not type the characters `<you>`.

Set a variable for the rest of this path (adjust if your clone lives elsewhere):

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

**2. Add the portable skills directory** (forward slashes are fine in YAML). Point **`external_dirs`** at **`agent-skills/skills`**, the folder that contains **`software-development`**. Do not point it at `software-development` itself. In the example below, `<you>` is again your Windows user name, not text to copy as-is.

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

You should see **`intel-devkit-install`** under the category **`software-development`**.

### Install the Dev Kit

Continue in the **same Hermes session**.

At the **`hermes>`** prompt:

```text
/intel-devkit-install
```

**Important:** Read and approve each Hermes permission prompt. Read the Windows UAC prompt and click **Yes** only if it is this Dev Kit install. Do not approve without reading. Denying or timing out a prompt can send the agent down unintended paths. Install may run **hours** in a separate Administrator window. Leave Hermes running as the standard user.

**Success:** the Dev Kit install completes.

### This path

```text
Hermes with an inference provider already configured
    → clone the Dev Kit repo
    → register skills
    → /intel-devkit-install
```

---

## Bootstrap path

For a new Hermes setup without an inference provider configured. The path includes installing Hermes, cloning the Dev Kit repo, running the OVMS prerequisites, starting Muse Glimmer on OVMS, restarting Hermes, and installing the Dev Kit.

| Approx. time | What |
|--------------|------|
| ~15 min | Install Hermes |
| ~10 min | Clone the Dev Kit repo |
| ~10 min | OVMS prerequisites (Administrator) |
| ~1–3 h | Muse Glimmer download and Hermes config |
| hours | Dev Kit install from Hermes |

**Hardware:** Intel® Core™ Ultra (Series 3) with **≥ 64 GB RAM** recommended for Muse Glimmer. Details: [Recommended hardware](docs/recommended-hardware.md).

Use a **standard user** for Hermes and for the Muse Glimmer script. Use an **Administrator** PowerShell window only for OVMS prerequisites. The Dev Kit install asks for Administrator through the Windows UAC prompt.

To do so, please follow:

### 1. Install Hermes

Install Hermes with **[Install Hermes (standard user PowerShell)](#install-hermes-standard-user-powershell)** above. Skip **[Cloud model for Hermes](#cloud-model-for-hermes)**. This path uses Muse Glimmer on OVMS, not NVIDIA NIM.

### 2. Clone the repo

Follow **[Clone the Dev Kit repo](#clone-the-dev-kit-repo)** above. Both scripts below read `Windows_Software_Installation\OVMS` from that clone. The full Dev Kit installer has not run yet.

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

**Important:** Read and approve each Hermes permission prompt. Read the Windows UAC prompt and click **Yes** only if it is this Dev Kit install. Do not approve without reading. Denying or timing out a prompt can send the agent down unintended paths. Install may run **hours** in a separate Administrator window. Leave Hermes running as the standard user.

### This path

```text
Install Hermes
    → Setup_OVMS_Prerequisites.ps1 (Administrator, -Target GPU)
    → setup-hermes-muse-glimmer.ps1 (standard user)
    → restart Hermes
    → /intel-devkit-install
```

**Success:** the Dev Kit install completes. Hermes is using **OpenVINO/Muse-Glimmer-30B-int4-ov** on port **8000**.

---

## Troubleshooting

| Issue | See |
|-------|-----|
| Install / Setup_1 failures | [Troubleshooting](docs/troubleshooting.md) |
| Admin install vs user OVMS | [Admin vs standard user](docs/admin-vs-user-runtime.md) |
| Hermes UAC install loop | [Hermes install elevation](docs/hermes-install-elevation.md) |
| Verify says re-install but GenAI is OK | Pull latest **agent-skills** (OVMS-only gap routes to OVMS setup, not reinstall) |
| **`/skills list`** does not show `intel-devkit-*` | Fix **`skills.external_dirs`** in **`config.yaml`**, exit and start **`hermes`** again; run **`hermes config get skills.external_dirs`** |

---

## Other capabilities

These skills are optional. Run any of them on its own. None of them are required before **`/intel-devkit-install`**.

| Capability | Command | What it does |
|------------|---------|----------------|
| Check the machine | `/intel-devkit-verify` | Read-only check of the Dev Kit, OpenVINO GenAI, and OVMS readiness |
| OVMS and the large agent model | `/intel-ovms-agentic-setup` | Install OVMS and **Qwen3.6-35B-A3B**. First download is about **1–3 h**. **≥ 64 GB RAM** recommended. [Recommended hardware](docs/recommended-hardware.md) |
| Point Hermes at local OVMS | `/intel-agent-provider-config` | Stage Hermes for `http://localhost:8000/v3` |
| Endpoint smoke test | `/intel-endpoint-smoke-test-report` | Chat completion against the local endpoint |
| VS Code Continue | `/openvino-coding-assistant` | Continue on the OVMS model already at `http://localhost:8000/v3` (Muse-Glimmer or Qwen3.6) |

### Point Hermes at local OVMS

When Hermes should use the local agent model, run **`/intel-agent-provider-config`**, then switch the provider in **PowerShell**:

```powershell
hermes config set model.provider custom
hermes config set model.base_url http://localhost:8000/v3
hermes config set model.default "OpenVINO/Qwen3.6-35B-A3B-int4-ov"
hermes
```

**Success:** the prompt should show **OpenVINO/Qwen3.6-35B-A3B-int4-ov**, and chat should hit OVMS on port **8000**.

---

## Manual path (PowerShell)

For labs without Hermes, run invokers from **`agent-skills`**:

| Step | Command |
|------|---------|
| Install (Admin) | `.\scripts\windows\invoke-devkit-install.ps1 -Approve` |
| Install (Hermes user + UAC) | `.\scripts\windows\invoke-devkit-install.ps1 -Approve -Elevate` then poll **-WaitInstallJob** |
| Verify (optional) | `.\scripts\windows\invoke-devkit-verify.ps1` |
| OVMS agent (optional) | `.\scripts\windows\invoke-ovms-agentic-setup.ps1 -Approve -Pull -Profile agent` |
| Hermes provider (optional) | `.\scripts\windows\configure-hermes-ovms.ps1 -Approve` |
| Smoke (optional) | `.\scripts\windows\endpoint-smoke-test.ps1` |
| Continue (optional) | `.\scripts\windows\invoke-openvino-coding-assistant-setup.ps1 -Approve -Apply` (add `-Pull` only when neither Muse-Glimmer nor Qwen3.6 is on port 8000) |

**OVMS is not installed by Setup_1/2 alone** — run OVMS setup after GenAI is present. Only **install** needs elevation; run verify/OVMS/configure as **standard user** when possible ([admin-vs-user-runtime.md](docs/admin-vs-user-runtime.md)).

---

## Reference

### Models

| Use | Model |
|-----|--------|
| Verification / smoke | `OpenVINO/Qwen3.5-0.8B-int4-ov` |
| Hermes / OpenClaw local agent | `OpenVINO/Qwen3.6-35B-A3B-int4-ov` |
| VS Code Continue | Muse-Glimmer or `OpenVINO/Qwen3.6-35B-A3B-int4-ov`, whichever `GET /v3/models` already lists on port **8000** |

Use the exact name from `GET http://localhost:8000/v3/models` after OVMS starts.

### Skill IDs

| Skill ID | Purpose |
|----------|---------|
| `intel-devkit-install` | Dev Kit install (primary; approval required) |
| `intel-devkit-verify` | Optional read-only environment check |
| `intel-ovms-agentic-setup` | Optional OVMS verify or agent profile |
| `intel-agent-provider-config` | Optional Hermes / OpenClaw local provider staging |
| `intel-endpoint-smoke-test-report` | Optional endpoint smoke test |
| `openvino-coding-assistant` | Optional VS Code Continue on the model already on port 8000 (Muse-Glimmer or Qwen3.6) |

Cards: [`skill-cards/`](skill-cards/). Portable definitions: [`skills/`](skills/).

### Environment variables (non-default layouts)

| Variable | Purpose |
|----------|---------|
| **`AIPC_DEVKIT_INSTALL_ROOT`** | Installer repo root (contains `Windows_Software_Installation\`) |
| **`AIPC_OVMS_ROOT`** | Folder with **`ovms.exe`** |
| **`AIPC_DEVKIT_WORKING_DIR`** | `openvino_genai` parent (default `C:\Intel`) |

OVMS-only slice: `fetch-devkit-ovms-slice.ps1` (see [Troubleshooting](docs/troubleshooting.md)).

### Other agents

Cursor, Claude Code, Gemini CLI, OpenCode, Goose, OpenClaw: add [`skills/`](skills/) to the host’s skills path. [Agent Skills compatibility](docs/agent-skills-compatibility.md).

### Approvals

Mutating or network skills require **`-Approve`**. Provider config is **staged** for review; **`-Apply`** is not automatic for Hermes—use **`local_provider_handoff`** / **`hermes model`**.

---

Intel, Intel Core, and Intel Core Ultra are trademarks of Intel Corporation or its subsidiaries.
