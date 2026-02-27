# Windows Software Installation for AI PC Development

Comprehensive tools for setting up AI PC development applications and environments on Windows, including GUI-based package management and automated repository downloaders.

## 🚀 Quick Start

### Prerequisites
- Windows 11 with PowerShell 5.1 or PowerShell Core
- Internet connection
- Administrative privileges (required--will attempt to auto-elevate)

### ⚠️ Important: Execution Policy Requirements
**This script must be run from an elevated PowerShell prompt.**

If you encounter execution policy errors preventing scripts from running, use one of these methods:

**Method 1 - Run with execution policy parameter (Recommended):**
```powershell
# For GUI mode
powershell.exe -ExecutionPolicy RemoteSigned -File ".\Setup.ps1" gui

# For command line install
powershell.exe -ExecutionPolicy RemoteSigned -File ".\Setup.ps1" install
```

### Step 1: GUI Package Manager (Recommended)
**Best for setting up complete AI development environments**
```powershell
# Navigate to the installer directory
cd "Windows_Software_Installation\WingetGUI_Installer"

# Launch the unified GUI
.\Setup.ps1 gui
```

### Step 2: Download AI Repositories and create environments
**Best for getting AI/ML code repositories**
```powershell
# Navigate to the installer directory
cd "Windows_Software_Installation\WingetGUI_Installer"

# Run with default settings (downloads to C:\Intel)
.\Setup_2.ps1

# Or specify custom directory
.\Setup_2.ps1 -DevKitWorkingDir "C:\MyAIProjects"
```

### Option 3: Command Line Package Installation
**Best for automated/scripted environments**
```powershell
cd "Windows_Software_Installation\WingetGUI_Installer"

# If execution policy allows scripts:
.\Setup.ps1 install

# If execution policy blocks scripts:
powershell.exe -ExecutionPolicy RemoteSigned -File ".\Setup.ps1" install

# Or uninstall
.\Setup.ps1 uninstall
```

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

**Usage:**
```powershell
# GUI Mode (Interactive)
.\Setup.ps1 gui
# Or if execution policy blocks: powershell.exe -ExecutionPolicy RemoteSigned -File ".\Setup.ps1" gui

# Command Line Mode (Silent)
.\Setup.ps1 install
# Or if execution policy blocks: powershell.exe -ExecutionPolicy RemoteSigned -File ".\Setup.ps1" install

# Uninstall Mode
.\Setup.ps1 uninstall
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
1. **OpenVINO Notebooks** - Jupyter notebooks for OpenVINO toolkit
2. **OpenVINO Build & Deploy** - Build and deployment examples  
3. **Ollama IPEX-LLM** - Ollama with Intel Extension for PyTorch
4. **OpenVINO GenAI** - Generative AI examples and tools
5. **WebNN Workshop** - Web Neural Network API workshop materials
6. **Open Model Zoo** - Pre-trained models collection

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
   .\Setup.ps1 gui
   
   # If execution policy blocks scripts:
   powershell.exe -ExecutionPolicy RemoteSigned -File ".\Setup.ps1" gui
   ```

4. **Install Software**:
   - Click "Install Software"
   - Select desired packages from the list
   - Click "Install Selected"
   - Monitor real-time progress

5. **Uninstall Software**:
   - Click "Uninstall Software" 
   - Select packages to remove
   - Confirm uninstallation
   - Tracking file automatically updated

#### Package Categories
- **Development Tools**: Git, Visual Studio Code, Visual Studio Community
- **AI/ML Frameworks**: Python, CMake, Vulkan SDK, Intel oneAPI
- **System Utilities**: Windows Terminal, PowerToys, Clink
- **Developer Productivity**: Chrome, Firefox, various IDEs

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
├── openvino_build_deploy\  
├── ollama-ipex-llm\
├── openvino_genai\
├── webnn_workshop\
└── open_model_zoo\
```

#### Adding New Repositories

1. **Open `get_repos.ps1`** and locate the `$repos` array (around line 74)
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

### File Structure
```
Windows_Software_Installation/
├── README.md                              # This file
└── WingetGUI_Installer/
    ├── Setup.ps1                          # Main entry point (GUI/CLI package manager)
    ├── Setup_1.ps1                        # Legacy entry point (kept for reference)
    ├── Setup_2.ps1                        # Repository downloader script
    ├── DevKitInstaller/                   # PowerShell module
    │   ├── DevKitInstaller.psd1           # Module manifest
    │   ├── DevKitInstaller.psm1           # Root module (auto-loads functions)
    │   ├── Private/                       # Internal helper functions
    │   │   ├── Write-ToLog.ps1            # Logging utility
    │   │   ├── JsonHelpers.ps1            # JSON append / remove helpers
    │   │   ├── InstallHelpers.ps1         # Install result checks, external installs
    │   │   ├── UninstallHelpers.ps1       # Uninstall result checks, winget/external
    │   │   └── GUIHelpers.ps1             # WPF assembly loading, data conversion
    │   └── Public/                        # Exported functions
    │       ├── Install-SelectedPackages.ps1
    │       ├── Uninstall-SelectedPackages.ps1
    │       ├── Show-GUI.ps1               # WPF dialogs (main menu, selection, results)
    │       ├── Test-Prerequisites.ps1     # Winget/NuGet/admin checks
    │       ├── Confirm-Eula.ps1           # EULA acceptance dialog
    │       └── Request-AdminPrivileges.ps1 # Elevation helpers
    ├── JSON/
    │   ├── install/
    │   │   └── applications.json          # Package definitions
    │   └── uninstall/
    │       └── uninstall.json             # Installed package tracking
    ├── logs/                              # Installation logs
    └── Public/                            # Legacy function files (kept for reference)
```

> **Note:** `Setup.ps1` imports the `DevKitInstaller` module via `Import-Module`,
> replacing the fragile dot-source chain used by the legacy `Setup_1.ps1`.
> All business logic lives in the module; `Setup.ps1` is a thin orchestrator.

---

## 🛠️ Troubleshooting

### Common Issues

#### Repository Downloader
- **Download Failures**: Check internet connection and verify URLs are accessible
- **Extraction Errors**: Ensure sufficient disk space and file permissions
- **Permission Errors**: Run PowerShell as Administrator

#### Winget GUI Installer
- **"Package not found" during uninstall**: Package was already uninstalled by another method (system will recognize this as success)
- **GUI doesn't show packages for uninstall**: No packages installed through this system yet
- **Script hangs on startup**: Check for UAC dialog waiting for user response
- **Installation shows as failed but package is installed**: Check logs for specific exit codes

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

This script collection is provided as-is for Intel AI Dev Kit setup. Individual repositories and packages have their own licenses.
