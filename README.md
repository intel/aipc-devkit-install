# AIPC Application Installer Version v2.0

## Introduction

Welcome to the AIPC Application Installer. This application is specifically designed to facilitate the setup of development tools, apps and environments for the Intel AIPC Developer engagements and events. It leverages the Microsoft package manager, winget, and can also download external applications using curl with additional configuration as listed below

**Note**:-  If you have any existing applications already installed, please uninstall them first and then use this utility to install. Installing the same application in two different ways may cause conflicts and the application may not work as expected. User discretion is mandatory.

**New in v2.0:**

- **Interactive GUI Mode**: Windows Forms interface
  
      Integrated Install: Visual interface for for visual package selection and installation
      Integrated Uninstall: Visual interface for visual package uninstall of previously installed packages
- **Enhanced JSON Structure**: Improved package descriptions with friendly names and summaries
- **Advanced Exit Code Handling**: Robust error detection and handling for both install and uninstall operations
- **Automatic Administrator Privileges**: Smart detection and elevation requests for all operations
- **Real-time Package Tracking**: Automatic tracking of installed packages for future uninstallation
- **Backward Compatibility**: Works with both new and legacy JSON formats

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

### Step 2: Run the First Setup Script
Navigate to the following directory and run the initial environment setup script:
```powershell
cd Windows_Software_Installation\WingetGUI_Installer
.\Setup_1.ps1 gui       #Install/Uninstall using GUI Mode
.\Setup_1.ps1 install       #Install using commandline
.\Setup_1.ps1 uninstall     #UnInstall using commandline
```
GUI Mode opens the Windows Forms interface for interactive package selection and installation/uninstallation.

### Step 3: Reboot the Machine
After completing the environment setup, reboot your machine to ensure all changes take effect and new environments are recognized.

### Step 4: Run the Second Setup Script
```powershell
cd Windows_Software_Installation\WingetGUI_Installer
.\Setup_2.ps1
```
This will pull a number of repositories and build the necessary environments to execute the samples.

## Options Internal vs External

Internal Mode

- Silent Operation: In internal mode, the script runs silently in the background, automatically accepting all license agreements.
  Module Installation: Installs the PowerShell module WingetClient and updates winget to the latest version 1.10.390.

External Mode
-Silent Operation but with User Interaction: In external mode, users must manually accept pop-up agreements before utilizing the application.

## Pre-requisites to run script


Administrator Privileges: Ensure the "powershell" terminal is running in admin mode.

- Example `Set-ExecutionPolicy -ExecutionPolicy Unrestricted LocalMachine`

- `winget` must be installed on computer with latest version 1.10.X or higher
  Winget Installation version verification use command: `winget --version`
  If not installed, execute
  Install-Module -Name Microsoft.WinGet.Client
  Repair-WinGetPackageManager -Force -Latest
- Ensure you have the latest version `1.10.X`

- For every application installed a corresponding entry is created in `JSON\uninstall\uninstall.json`, once you have winget installed execute the script using `.\Setup_1.ps1 install`



#### Global Install Flags

- `global_install_flags`
  - These are run for `winget`. The pre included ones are:
    - `--silent` Allows it to run in the background
    - `--accept-package-agreements` and `--accept-source-agreements` Allows it to run via task scheduler without having UAC pop ups
    - `--disable-interactivity` Another fallback to remove UAC agreements
    - `--force` Final check to ensure things resolve and install

### Applications JSON Structure
- **JSON Configuration**: [Windows_Software_Installation/WingetGUI_Installer/JSON/install/applications.json](./Windows_Software_Installation/WingetGUI_Installer/JSON/install/applications.json)
  
Winget Applications
Applications installed via the Windows package manager, with automatic dependency resolution:

  {
   
  
            "id": "Microsoft.VisualStudioCode",
            "friendly_name": "Visual Studio Code",
            "summary": "Code editor",
            "override_flags": null,
            "install_location": null,
            "version": null,
            "version_check": null,
            "dependencies": null,
            "skip_install": "no"
   }

External Applications
Applications not installed via the Windows package manager, requiring a URL for download via curl

    {
    "name": "one_api_base_toolkit",
    "source": "https://install_url/application.exe",
    "install_flags": "--some --exes --want --install --flags",
    "download_location": "C:\\Required\\download\\location",
    "uninstall_command": "C:\\Required\\download\\location\\uninstaller.exe",
    "dependencies": [
    {
    "name": "Optional Dependency"
    },
    {
    "name": "Visual Studio Code"
    },
    {
    "name": "C++ Redistribution"
    }
    ]
    }

Notes:-
Installation Order: The installation process executes from top to bottom. It is recommended to place external applications and items with dependencies last to ensure required software is installed first.
OneAPI Base Toolkit: This toolkit requires specific dependencies, including Visual Studio Community and .NET and C++ frameworks. For easy uninstallation, include the uninstall command, typically formatted as:
C:\Program Files (x86)\Intel\oneAPI\Installer\installer.exe -s --action remove --product-id intel.oneapi.win.basekit.product --product-ver 2025.0.1+44

"skip_install": "no" --indicates this is a mandatory install even if application is part of JSON, please set this to "yes" if you dont want this application to be installed by default.

To find the specific product version, execute:
.\installer.exe --list-products

#### Workflow Overview

1. Administrator Privileges Check: Verifies admin access.
2. Execution Policy Setting: Sets policy to Unrestricted.
3. Application List Reading: Reads from applications.json.
4. Log Directory Initialization: Prepares logging environment.
5. Application Identification: Determines applications for installation.
6. Installation and Logging: Installs applications and logs the process.
7. Uninstall JSON Creation: Generates a file for tracking installed applications.

**Applications Configuration**

**applications.json Overview**
The applications.json file configures applications for installation by the Setup_1.ps1 script, detailing Winget and external applications along with their installation parameters.

**VerifyInstall**

1. This script performs a basic command line version check with the specified tool.

- Global Install Flags: Default flags for all installations.
- Winget Applications: Array of Winget applications to be installed.
- External Applications: Array of external applications to be installed.

Adding New Applications to installer
To add an application, first verify its availability via winget:
Example:

#### Overview

- Reads application list from `applications.json`
- Installs Winget applications and external applications
- Logs installation process
- Creates an uninstall JSON file for tracking installed applications

#### Workflow

1. Checks for administrator privileges
2. Sets execution policy to Unrestricted
3. Reads application list from `applications.json`
4. Initializes log directory
5. Identifies applications that need to be installed
6. Installs each application and logs the process
7. Creates an uninstall JSON file for tracking installed applications

### applications.json

#### Overview

The `applications.json` file contains the configuration for applications to be installed by the `Setup_1.ps1` script. It includes a list of Winget applications and external applications, along with their installation parameters.

#### VerifyInstall

This script runs a basic command line version check with the specified tool

##### Root Object

- `global_install_flags` (string): Default flags for all installations
- `winget_applications` (array): List of Winget applications to be installed
- `external_applications` (array): List of external applications to be installed

 ## Opens/Issues

- Uninstall of Clink and Microsoft Visual Studio Installer does not have a silent and suppress window method, user interaction is required. There is no available solution with winget and will be resolved when the software vendor releases a patch.This is not a blocker and functionality of this installer is not hampered in anyway.
- If python is installed please make sure Python is added to the system's PATH environment variable. This step is manual and not part of installation

## Documentation

For detailed documentation, configuration guides, and troubleshooting:
- **Windows Installer Documentation**: [Windows_Software_Installation/README.md](./Windows_Software_Installation/README.md)

## Support

For technical assistance, configuration help, or feature requests:
- Contact: Ram (vaithi.s.ramadoss@intel.com) or Vijay (vijay.chandrashekar@intel.com)
- Full documentation: [Windows_Software_Installation/README.md](./Windows_Software_Installation/README.md)
