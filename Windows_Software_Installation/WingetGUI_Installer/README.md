# Winget GUI Installer for AI PC Development

A user-friendly graphical interface for installing and managing Windows packages using winget, specifically designed for AI PC development environments.

## Overview

This tool provides a modern Windows Forms GUI for:
- ✅ **Package Installation**: Browse and install curated AI development tools
- ✅ **Package Uninstallation**: Remove packages with comprehensive tracking
- ✅ **Unified Interface**: Single GUI for both install and uninstall operations
- ✅ **Progress Tracking**: Real-time installation progress with detailed logging
- ✅ **Error Handling**: Robust error reporting and retry mechanisms

## Quick Start

### GUI Mode (Recommended)
```powershell
# Navigate to the installer directory
cd "Windows_Software_Installation\WingetGUI_Installer\EnvSetup"

# Launch the unified GUI
powershell.exe -ExecutionPolicy Bypass -File ".\Env_Setup.ps1" gui
```

### Command Line Mode
```powershell
# Install packages via command line
powershell.exe -ExecutionPolicy Bypass -File ".\Env_Setup.ps1"
```

## Features

### 🎯 **AI PC Development Focus**
Pre-configured package collections for:
- Development tools (Git, Visual Studio Code, etc.)
- AI/ML frameworks (Python, Conda, PyTorch, etc.)
- System utilities (Windows Terminal, PowerToys, etc.)
- Developer productivity tools

### 🚀 **Enhanced User Experience**
- **Modern GUI**: Clean Windows Forms interface
- **Batch Operations**: Install/uninstall multiple packages at once
- **Progress Tracking**: Real-time progress bars and status updates
- **Smart Exit Code Handling**: Properly handles already-installed/uninstalled packages
- **Comprehensive Logging**: Detailed logs for troubleshooting

### 🔧 **Advanced Package Management**
- **JSON Configuration**: Easy customization of package lists
- **Uninstall Tracking**: Maintains history of uninstalled packages
- **Dependency Handling**: Proper handling of package dependencies
- **Error Recovery**: Robust error handling with detailed reporting

## Integration with Intel AI PC Training

This winget installer complements the existing Intel AI PC training materials by providing:

1. **Standardized Environment Setup**: Ensures consistent development environments across all training participants
2. **GUI-Based Package Management**: More accessible than command-line tools for diverse user skill levels
3. **AI Development Focus**: Curated package selections specifically for AI PC development workflows
4. **Integration Ready**: Designed to work alongside existing Intel training scripts and materials

## File Structure

```
WingetGUI_Installer/
├── EnvSetup/
│   ├── Env_Setup.ps1              # Main installer script with GUI
│   ├── README.md                  # Detailed technical documentation
│   ├── JSON/
│   │   └── install/
│   │       ├── applications.json  # GUI applications
│   │       └── packages.json      # Development packages
│   └── Public/
│       ├── Append-ToJson.ps1      # JSON management utilities
│       ├── Pre_Req.ps1            # Prerequisites checker
│       ├── Run_Once_Eula.ps1      # EULA acceptance
│       └── Write_ToLog.ps1        # Logging utilities
```

## Usage Examples

### Install AI Development Stack
1. Launch GUI: `.\Env_Setup.ps1 gui`
2. Select "Install Packages" 
3. Choose from curated AI development tools
4. Click "Install Selected" and monitor progress

### Remove Unused Packages
1. Launch GUI: `.\Env_Setup.ps1 gui`
2. Select "Uninstall Packages"
3. View installed packages and select for removal
4. Confirm uninstallation with automatic tracking cleanup

## Technical Requirements

- **Windows 10/11**: Windows PowerShell 5.1 or PowerShell 7+
- **Winget**: Windows Package Manager (installed by default on Windows 11)
- **Internet Connection**: Required for package downloads
- **Administrator Rights**: May be required for some package installations

## Advanced Configuration

See the detailed [technical documentation](EnvSetup/README.md) for:
- Custom package JSON configuration
- Command-line parameters and options
- Exit code reference and troubleshooting
- Integration with automated workflows

## Contributing to Intel AI PC Training

This tool is part of the Intel AI PC developer training initiative. For contributions or issues:

1. Follow the existing code patterns and PowerShell best practices
2. Test thoroughly on different Windows versions
3. Update documentation for any new features
4. Ensure compatibility with existing Intel training workflows

---

*Part of the Intel AI PC Developer Training Materials*
