# Windows Software Installation for AI PC Development

Comprehensive tools for setting up AI PC development applications and environments on Windows, including GUI-based package management and automated repository downloaders.

## 🚀 Quick Start

### Prerequisites
- Windows 11 with PowerShell 5.1 or PowerShell Core
- Internet connection
- Administrative privileges (required--will attempt to auto-elevate)

### Step 1: Set Execution Policy
Run once from an elevated PowerShell prompt:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
```

### Step 2: GUI Package Manager (Recommended)
Use this for interactive install and uninstall:

```powershell
cd "Windows_Software_Installation\WingetGUI_Installer"
.\Setup_1.ps1 gui
```

### Step 3 (Optional): Command Line Package Installation
Use this for scripted/silent flow:

```powershell
cd "Windows_Software_Installation\WingetGUI_Installer"
.\Setup_1.ps1 install
.\Setup_1.ps1 uninstall
```

If execution policy still blocks scripts, run with explicit policy parameter:

```powershell
powershell.exe -ExecutionPolicy RemoteSigned -File ".\Setup_1.ps1" gui
powershell.exe -ExecutionPolicy RemoteSigned -File ".\Setup_1.ps1" install
```

### ⚠️ Important: Uninstall Requires Manual Intervention
**Uninstall is NOT completely silent.** Many applications do not support fully automated silent uninstallation, even with command-line flags. You may encounter:
- **Interactive prompts** from application uninstallers requiring user confirmation
- **Dialog boxes** asking to confirm removal
- **Restart requirements** for some applications
- **Per-application uninstall experiences** that cannot be suppressed

**Recommendation:** Monitor the uninstall process and be prepared to click "OK" or "Confirm" buttons when prompted. The system logs uninstall operations to `C:\temp\logs\uninstall\uninstall.txt` and also copies a snapshot to your desktop as `uninstall_logs.txt`.

---

## 🛠️ Available Tools

### 🎯 Winget GUI Installer
**Modern graphical package manager for AI development tools**

**Features:**
- ✅ **Unified Interface**: Single GUI for install/uninstall operations
- ✅ **AI Development Focus**: Curated package collections for AI/ML development
- ✅ **Progress Tracking**: Real-time installation progress with detailed logging
- ✅ **Smart Tracking**: Maintains history of installed packages for easy removal
- ✅ **Bidirectional Compatibility**: Install via GUI or command line, uninstall via either method
- ✅ **Error Handling**: Robust error reporting and retry mechanisms
- ✅ **Post-Install Commands**: Execute custom commands after app installation
- ✅ **Persistent Environment Variables**: Set and cleanup system/user environment variables
- ✅ **Automatic Cleanup**: Environment variables removed on uninstall

**Usage:**
```powershell
# GUI Mode (Interactive)
.\Setup_1.ps1 gui
# Or if execution policy blocks: powershell.exe -ExecutionPolicy RemoteSigned -File ".\Setup_1.ps1" gui

# Command Line Mode (Silent)
.\Setup_1.ps1 install
# Or if execution policy blocks: powershell.exe -ExecutionPolicy RemoteSigned -File ".\Setup_1.ps1" install

# Uninstall Mode
.\Setup_1.ps1 uninstall
```

### 📦 Repository Downloader
**Automated download and setup of AI/ML repositories**

**Features:**
- ✅ **Parallel Downloads**: Downloads up to 5 repositories simultaneously  
- ✅ **Retry Logic**: Automatic retry with exponential backoff (2s, 4s, 8s delays)
- ✅ **Progress Tracking**: Real-time download progress and completion status
- ✅ **Smart Skipping**: Skips existing directories and downloaded files
- ✅ **Automatic Extraction**: Extracts ZIP files and organizes into proper directories
- ✅ **Resume Capability**: Can be run multiple times safely

**Current AI Repositories:**
1. **openvino_notebooks** - OpenVINO notebooks (latest branch ZIP)
2. **openvino_genai** - OpenVINO GenAI Windows package
3. **AI-PC-Samples** - Intel AI PC Samples repository
4. **Microsoft-Build2025-Samples** - Intel Microsoft Build 2025 sample repository

---

## 📋 Detailed Usage Guide

### Winget GUI Installer

#### System Requirements
- **Windows 10/11**: Windows PowerShell 5.1 or PowerShell 7+
- **Winget**: Windows Package Manager (installed by default on Windows 11)
- **Internet Connection**: Required for package downloads
- **Administrator Rights**: May be required for some package installations

#### Step-by-Step Usage

1. **Verify Winget Installation**:
   ```powershell
   winget --version
   ```
   Should show version 1.10.X or higher

2. **Launch GUI**:
   ```powershell
   cd "WingetGUI_Installer"
   
   # If execution policy allows scripts:
   .\Setup_1.ps1 gui
   
   # If execution policy blocks scripts:
   powershell.exe -ExecutionPolicy RemoteSigned -File ".\Setup_1.ps1" gui
   ```

4. **Install Software**:
   - Click "Install Software"
   - Select desired packages from the list
   - Click "Install Selected"
   - Monitor real-time progress

5. **Uninstall Software**:
   - Click "Uninstall Software" 
   - Select packages to remove
   - **Be ready to interact with uninstall dialogs** - not all apps support completely silent uninstall
   - Monitor progress and respond to any prompts
   - Confirm uninstallation
   - Tracking file automatically updated
   - Environment variables automatically removed from system registry

#### Package Categories
- **Winget Applications**: Visual Studio Code, Visual Studio Community 2026 Edition, Python 3.12, Clink, Git for Windows, CMake, uv, Vulkan SDK, Node.js LTS, Foundry Local, Ollama
- **External Applications**: Continue (VS Code Extension), npm (Node Package Manager), Intel AI Playground, NuGet Installation

### Repository Downloader

#### Parameters
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `DevKitWorkingDir` | String | `C:\Intel` | Target directory for downloads |
| `MaxRetries` | Integer | `3` | Maximum retry attempts per download |

#### Directory Structure After Download
```
C:\Intel\
├── openvino_notebooks\
├── openvino_genai\
├── AI-PC-Samples\
└── Microsoft-Build2025-Samples\
```

#### Adding New Repositories

1. **Open `Setup_2.ps1`** and locate the `$repos` array
2. **Add your repository**:
   ```powershell
   $repos = @(
       # ... existing repos ...
       @{ Name = "your_repo_name"; Uri = "https://github.com/owner/repo/archive/refs/heads/main.zip"; File = "repo.zip" }
   )
   ```

3. **Common URL Patterns**:
   - **Main Branch**: `https://github.com/owner/repo/archive/refs/heads/main.zip`
   - **Specific Branch**: `https://github.com/owner/repo/archive/refs/heads/branch-name.zip`
   - **Tagged Release**: `https://github.com/owner/repo/archive/refs/tags/v1.0.0.zip`
   - **Release Asset**: `https://github.com/owner/repo/releases/download/v1.0.0/filename.zip`

---

## 🔧 Advanced Configuration

### Winget Package Configuration

The GUI installer uses JSON configuration files for package management:

#### Global Install and Uninstall Flags
Both `global_install_flags` and `global_uninstall_flags` are defined at the top of `applications.json`. They apply to **every** package unless a per-app override is present. This is the **single source of truth** for these flags — `uninstall.json` copies them from here at creation time, and `Append-ToJson.ps1` reads from here whenever it initialises a new `uninstall.json`.

```json
{
  "global_install_flags": "--silent --accept-package-agreements --accept-source-agreements --disable-interactivity --force",
  "global_uninstall_flags": "--purge --accept-source-agreements --silent --disable-interactivity --force",
  "winget_applications": [ ... ]
}
```

To change how **all** apps are uninstalled, edit `global_uninstall_flags` here. No other files need to be touched.

#### Adding Winget Applications
```json
{
  "id": "Microsoft.VisualStudioCode",
  "friendly_name": "Visual Studio Code", 
  "summary": "Code editor",
  "override_flags": null,
  "install_location": null,
  "version": null,
  "version_check": "code --version",
  "dependencies": null,
  "skip_install": "no"
}
```

#### Per-App Uninstall Override Flags
Use `uninstall_override_flags` on a specific entry to **replace** the global uninstall flags for that app. This is useful for applications whose uninstallers use a different silent flag convention.

Note: these flags are applied only when the local winget build supports uninstall `--override`; otherwise the framework logs this and continues with global uninstall flags.

**Example — Vulkan SDK (NSIS installer uses `/S`):**
```json
{
  "id": "KhronosGroup.VulkanSDK",
  "friendly_name": "Vulkan SDK",
  "summary": "Next-generation graphics and compute API",
  "override_flags": null,
  "skip_install": "no",
  "uninstall_override_flags": "/S"
}
```

| Installer Type | Silent Uninstall Flag | Notes |
|---|---|---|
| MSI / WiX (e.g. CMake) | Global flags (`--silent`) | Reliable — winget maps to `/quiet` |
| NSIS EXE (e.g. Vulkan SDK) | `/S` via `uninstall_override_flags` | Must override; global flags insufficient |
| Inno Setup EXE | `/VERYSILENT /SUPPRESSMSGBOXES` | Override if needed |
| Custom EXE | Vendor-specific | Set `uninstall_command` on external apps |

#### Adding External Applications  
```json
{
  "name": "custom_app",
  "friendly_name": "Custom Application",
  "summary": "Custom application description",
  "source": "https://download.url/installer.exe",
  "install_flags": "--silent --accept-eula",
  "download_location": ".\\Downloads\\CustomApp",
  "uninstall_command": "C:\\Path\\To\\uninstaller.exe --silent",
  "dependencies": [],
  "skip_install": "no"
}
```

### Post-Installation Configuration

#### Post-Install Commands
Execute arbitrary commands after an application installs successfully. Commands are executed in sequence via PowerShell.

**Example - NuGet Installation Steps:**
```json
{
   "name": "nuget-installation",
   "friendly_name": "NuGet Installation",
  "summary": "Complete final setup and configuration",
   "install_command": "echo NuGet installation steps",
  "post_install_commands": [
    "dotnet nuget locals all --clear",
      "if (-not ((dotnet nuget list source | Out-String) -match '(?im)^\\s*\\d+\\.\\s+nuget\\.org\\b')) { dotnet nuget add source https://api.nuget.org/v3/index.json -n nuget.org } else { Write-Host 'NuGet source nuget.org already configured. Skipping add source step.' }",
    "dotnet nuget list source"
  ],
  "skip_install": "no"
}
```

**Supported for:**
- Winget applications (any field)
- External applications (any field)

**Execution Context:**
- Commands run after successful installation
- Executed via PowerShell in the current user context
- All output is logged to the installation log file

#### Persistent Environment Variables
Set environment variables that survive system reboot and user logouts (Machine scope) or persist for the user profile (User scope).

**Example - Ollama with Vulkan Support:**
```json
{
  "id": "Ollama.Ollama",
  "friendly_name": "Ollama",
  "summary": "Run local LLMs with Ollama",
  "override_flags": null,
  "skip_install": "no",
  "post_install_environment_variables": {
    "OLLAMA_VULKAN": "1"
  }
}
```

**Variable Scope Behavior:**
- **Installation**: Sets in Machine scope (system-wide, requires admin)
  - Falls back to User scope if Machine scope fails
  - Also sets Process scope for immediate session availability
- **Uninstallation**: Removes from both Machine and User scopes (whichever exists)
  - Cleans up environment registry entries
  - Preserves other environment variables

**Multiple Variables Example:**
```json
{
  "post_install_environment_variables": {
    "VARIABLE_ONE": "value1",
    "VARIABLE_TWO": "value2",
    "VARIABLE_THREE": "value3"
  }
}
```

**Verification After Installation:**
```powershell
# Check Machine scope
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" -Name "OLLAMA_VULKAN"

# Check User scope
Get-ItemProperty -Path "HKCU:\Environment" -Name "OLLAMA_VULKAN"

# Check current session (Process scope)
$env:OLLAMA_VULKAN
```

**Verification After Uninstallation:**
```powershell
# Should return nothing if successfully removed
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" -Name "OLLAMA_VULKAN" -ErrorAction SilentlyContinue
Get-ItemProperty -Path "HKCU:\Environment" -Name "OLLAMA_VULKAN" -ErrorAction SilentlyContinue
```

### File Structure
```
Windows_Software_Installation/
├── README.md                              # This file
└── WingetGUI_Installer/
   ├── Setup_1.ps1                        # Main installer script (GUI/CLI package manager)
   ├── Setup_2.ps1                        # Repository downloader script
    ├── JSON/
    │   ├── install/
    │   │   └── applications.json          # Package definitions
    │   └── uninstall/
    │       └── uninstall.json             # Installed package tracking
    ├── logs/                              # Installation logs
    └── Public/                            # Core functionality modules
        ├── GUI.ps1                        # GUI interface
        ├── Install.ps1                    # Installation & post-install functions
        ├── Uninstall.ps1                  # Uninstallation functions (with env var cleanup)
        ├── Append-ToJson.ps1              # JSON management (reads global_uninstall_flags from applications.json)
        └── Write_ToLog.ps1                # Logging utilities
```

### Installation and Uninstallation Workflow

#### Installation Sequence
1. **Application Installation**
   - Winget: `winget install` with configured flags
   - External: Download installer and execute with flags or direct `install_command`
   
2. **Success Verification** (via `Test-InstallationSuccess`)
   - Check exit codes (0, 3010, 1641 are success)
   - Log success/failure status

3. **Post-Installation Actions** (via `Invoke-PostInstallActions`)
   - Execute `post_install_commands` if defined
   - Apply `post_install_environment_variables` if defined

4. **Tracking Update**
   - Write installation details to `uninstall.json` for later removal

#### Uninstallation Sequence
1. **Application Uninstallation**
   - Winget: `winget uninstall` with flags resolved in priority order:
     1. Per-app `uninstall_override_flags` (takes precedence if set)
     2. `global_uninstall_flags` from `uninstall.json` (sourced from `applications.json`)
     3. Hardcoded fallback if JSON is unavailable
    - External: Resolve app from `applications.json` and execute its `uninstall_command`
       - If `uninstall_command` is missing/empty, uninstall is marked failed and tracking is retained

2. **Success Verification** (via `Test-UninstallationSuccess`)
   - Check exit codes
   - Log success/failure status

3. **Environment Variable Cleanup** (via `Remove-PersistentEnvironmentVariables`)
   - Remove variables from Machine scope (admin required)
   - Fallback to User scope if Machine scope not available
   - Log all removal operations

4. **Tracking Update**
   - Remove application from `uninstall.json`
   - Delete file if all apps removed

---

## 🛠️ Troubleshooting

### Common Issues

#### Scripts Blocked by Microsoft (Mark of the Web - MOTW)

**Error You Will See:**
```
.\Setup_1.ps1 : File C:\Users\...\Setup_1.ps1 cannot be loaded because running scripts is disabled on 
this system. For more information, see about_Execution_Policies at https://go.microsoft.com/fwlink/?LinkID=135170.
```

Or the script may hang/fail silently when trying to execute, even though the execution policy appears to be set correctly.

**Why This Happens (MOTW Explanation):**
When you download files from the internet (via browser, email, or GitHub), Windows automatically applies a security attribute called the "Mark of the Web" (MOTW). This is stored as a file stream property (`Zone.Identifier = 3`) that indicates the file came from an untrusted zone. Even if you set the execution policy to `RemoteSigned`, Windows still **blocks execution** of files with the MOTW attribute as a security precaution.

**Solution - Unblock Downloaded Files:**

Run this PowerShell command to unblock all `.ps1` files in the Windows_Software_Installation folder:

```powershell
Get-ChildItem -Path "Windows_Software_Installation" -Recurse -Include "*.ps1" | Unblock-File
```

Then verify it worked:
```powershell
Get-ChildItem -Path "Windows_Software_Installation" -Recurse -Include "*.ps1" | Get-Item -Stream Zone.Identifier -ErrorAction SilentlyContinue
```
(This command should return nothing if files are successfully unblocked)

**Alternative - Unblock Files Individually:**
```powershell
Unblock-File -Path "Windows_Software_Installation\WingetGUI_Installer\Setup_1.ps1"
Unblock-File -Path "Windows_Software_Installation\WingetGUI_Installer\Setup_2.ps1"
```

**Note:** This issue is most common if you downloaded the repository as a ZIP file from GitHub or email. If you cloned via Git, the MOTW attribute is typically not applied.

#### Repository Downloader
- **Download Failures**: Check internet connection and verify URLs are accessible
- **Extraction Errors**: Ensure sufficient disk space and file permissions
- **Permission Errors**: Run PowerShell as Administrator

#### Winget GUI Installer
- **"Package not found" during uninstall**: Package was already uninstalled by another method (system will recognize this as success)
- **GUI doesn't show packages for uninstall**: No packages installed through this system yet
- **Script hangs on startup**: Check for UAC dialog waiting for user response
- **Installation shows as failed but package is installed**: Check logs for specific exit codes
- **Environment variables not persisting**: Verify installation completed successfully; restart PowerShell or system to see changes
- **Environment variable not removed on uninstall**: Check application logs for scope (Machine vs User); admin privileges may be required for Machine scope removal

### Exit Code Reference

#### Installation Exit Codes
- **0**: Successful installation
- **-1978335212**: Already installed (treated as success)
- **-1978335209**: Version not found (treated as failure)  
- **-1978335210**: Package not found (treated as failure)

#### Uninstall Exit Codes
- **0**: Successfully uninstalled
- **1**: Package not found (treated as success - goal achieved)
- **-1978335212**: Package not in installed list (treated as success)
- **-1978335210**: Package not found (treated as success - goal achieved)

### Performance Notes
- **Parallel Downloads**: Up to 5 simultaneous downloads for repositories
- **Memory Usage**: ~1MB buffer per download stream
- **Retry Strategy**: Exponential backoff (2s, 4s, 8s delays)
- **Bidirectional Compatibility**: Install via any method, uninstall via any method

---

## 📞 Support

For technical assistance or feature requests:

- **Repository Issues**: Check individual repository documentation
- **GUI Installer Issues**: Check logs in `WingetGUI_Installer\logs\`
- **Feature Requests**: Contact development team

## 📄 License

MIT License

Copyright (c) 2025 Intel

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
