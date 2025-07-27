# AIPC Application Installer Version v1.1

## Introduction

Welcome to the AIPC Application Installer. This application is specifically designed to facilitate the setup of development tools, apps and environments for the Intel AIPC Developer engagements and events. It leverages the Microsoft package manager, winget, and can also download external applications using curl with additional configuration.For any assistance, please refer to the support documentation or contact our technical support team

## Options Internal vs External

Internal Mode

- Silent Operation: In internal mode, the script runs silently in the background, automatically accepting all license agreements.
  Module Installation: Installs the PowerShell module WingetClient and updates winget to the latest version 1.10.390.

External Mode
-Silent Operation but with User Interaction: In external mode, users must manually accept pop-up agreements before utilizing the application.

## How to run script

Pre-requisites
Administrator Privileges: Ensure the "powershell" terminal is running in admin mode.

- Step1 : `Set-ExecutionPolicy -ExecutionPolicy Unrestricted LocalMachine`

- Step2: `winget` must be installed on computer with latest version 1.10.X or higher
  Winget Installation version verification use command: `winget --version`
  If not installed, execute
  Install-Module -Name Microsoft.WinGet.Client
  Repair-WinGetPackageManager -Force -Latest
- Ensure you have the latest version `1.10.X`

### Install

- Once you have winget installed execute the script using `.\Env_Setup.ps1 install`
- For every application installed a corresponding entry is created in `JSON\uninstall\uninstall.json`.

### Uninstall

- Execute `.\Env_Setup.ps1 uninstall`

## JSON Structure

#### Global Install Flags

- `global_install_flags`
  - These are run for `winget`. The pre included ones are:
    - `--silent` Allows it to run in the background
    - `--accept-package-agreements` and `--accept-source-agreements` Allows it to run via task scheduler without having UAC pop ups
    - `--disable-interactivity` Another fallback to remove UAC agreements
    - `--force` Final check to ensure things resolve and install

### Applications

Winget Applications
Applications installed via the Windows package manager, with automatic dependency resolution:
{
"name": "Application name",
"override_flags": "optional",
"install_location": "--location C:\\Optional\\install\\location",
"version": "1.100.2",
"version_check": "application --version",
"dependencies": null
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
The applications.json file configures applications for installation by the EnvSetup.ps1 script, detailing Winget and external applications along with their installation parameters.

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

The `applications.json` file contains the configuration for applications to be installed by the `EnvSetup.ps1` script. It includes a list of Winget applications and external applications, along with their installation parameters.

#### VerifyInstall

This script runs a basic command line version check with the specified tool

##### Root Object

- `global_install_flags` (string): Default flags for all installations
- `winget_applications` (array): List of Winget applications to be installed
- `external_applications` (array): List of external applications to be installed

#### Adding applications

To add an application to the script, please follow the CCB process guidelines. Contact Ram(vaithi.s.ramadoss@intel.com) or Vijay(vijay.chandrashekar@intel.com) for more details

- Guidelines to request for a new application that needs to be installed:

  - `winget search git`
    !["Winget search picture"](./Private/readme-pictures/winget-search.png "Winget search")
  - You will want to take note of the `Id` and `Version`, if you care about the version
  - Please view the schema for the JSON in the JSON directory [here](./Public/JSON/README.md)

  ## Opens/Issues

- Uninstall of Clink and Microsoft Visual Studio Installer does not have a silent and suppress window method, user interaction is required. There is no available solution with winget and will be resolved when the software vendor releases a patch.This is not a blocker and functionality of this installer is not hampered in anyway.
