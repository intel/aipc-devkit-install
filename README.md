# AIPC Application Installer Version v2.0

## Introduction

Welcome to the AIPC Application Installer. This application is specifically designed to facilitate the setup of development tools, apps and environments for the Intel AIPC Developer engagements and events. It leverages the Microsoft package manager, winget, and can also download external applications using curl with additional configuration.

**New in v2.0:**
- **Interactive GUI Mode**: Windows Forms interface for visual package selection and installation
- **Integrated Uninstall GUI**: Visual interface for uninstalling previously installed packages
- **Enhanced JSON Structure**: Improved package descriptions with friendly names and summaries
- **Advanced Exit Code Handling**: Robust error detection and handling for both install and uninstall operations
- **Automatic Administrator Privileges**: Smart detection and elevation requests for all operations
- **Real-time Package Tracking**: Automatic tracking of installed packages for future uninstallation
- **Backward Compatibility**: Works with both new and legacy JSON formats

For any assistance, please refer to the support documentation or contact our technical support team.

## Quick Start

### Pre-requisites
- **Administrator Privileges**: The script will automatically check and request administrator privileges when needed
- **PowerShell Execution Policy**: Set to Unrestricted (the script will guide you)
- **Winget**: Must be installed with version 1.10.X or higher



### Step 1: Set Execution Policy
```powershell
Set-ExecutionPolicy -ExecutionPolicy Unrestricted LocalMachine
```

### Step 2: Run the Environment Setup Script
Navigate to the following directory and run the initial environment setup script:
```powershell
cd Windows_Software_Installation\WingetGUI_Installer\EnvSetup
.\Env_Setup.ps1 gui
```
This opens the Windows Forms interface for interactive package selection and installation/uninstallation.

### Step 3: Reboot the Machine
After completing the environment setup, reboot your machine to ensure all changes take effect and new environments are recognized.

### Step 4: Run the Main Setup Script
```powershell
cd Windows_Software_Installation
.\setup_software.ps1
```
This will pull a number of repositories and build the necessary environments to execute the samples.


## Documentation

For detailed documentation, configuration guides, and troubleshooting:
- **Windows Installer Documentation**: [Windows_Software_Installation/README.md](./Windows_Software_Installation/README.md)
- **JSON Configuration**: [Windows_Software_Installation/WingetGUI_Installer/EnvSetup/JSON/install/applications.json](./Windows_Software_Installation/WingetGUI_Installer/EnvSetup/JSON/install/applications.json)

## Key Features

### Smart Package Management
- **Automatic Tracking**: Installed packages are tracked for easy uninstallation
- **Duplicate Prevention**: Won't install already installed packages
- **Dependency Resolution**: Handles package dependencies automatically

### Enhanced User Experience
- **Visual Interface**: Windows Forms GUI for easy interaction
- **Detailed Feedback**: Clear success/failure messages with exit code information
- **Error Recovery**: Graceful handling of various installation scenarios

### Robust Operation
- **Exit Code Intelligence**: Recognizes various success/failure conditions
- **Administrator Handling**: Automatic privilege detection and elevation
- **Logging**: Comprehensive logging for troubleshooting


## Support

For technical assistance, configuration help, or feature requests:
- Contact: Ram (vaithi.s.ramadoss@intel.com) or Vijay (vijay.chandrashekar@intel.com)
- Full documentation: [Windows_Software_Installation/README.md](./Windows_Software_Installation/README.md)
