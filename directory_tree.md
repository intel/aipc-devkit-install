# Project Directory Structure

```
training.developer.aipc/
├── .gitignore
├── .vscode/
│   └── settings.json
├── Linux_Driver_Setup/
│   ├── build-static-installer.sh
│   ├── LICENSE
│   ├── README.md
│   ├── Dynamic/
│   │   └── setup-drivers.sh
│   └── Utilities/
│       ├── compatibility_check_README.md
│       ├── compatibility_check.sh
│       └── verify_connectivity.sh
├── Linux_Software_Installation/
│   ├── SETUP-SOFTWARE-README.md
│   └── setup-software.sh
├── README.md
├── Windows_Software_Installation/
│   ├── Llamacpp_compilation.md
│   ├── README.md
│   ├── setup_software.ps1
│   └── WingetGUI_Installer/
│       ├── README.md
│       └── EnvSetup/
│           ├── Env_Setup.ps1
│           ├── GUI_REFACTORING.md
│           ├── README.md
│           ├── JSON/
│           │   └── install/
│           │       └── applications.json
│           ├── Private/
│           │   └── readme-pictures/
│           │       ├── oneapi_version.png
│           │       └── winget-search.png
│           └── Public/
│               ├── Append-ToJson.ps1
│               ├── GUI.ps1
│               ├── Install.ps1
│               ├── Pre_Req.ps1
│               ├── Run_Once_Eula.ps1
│               ├── Uninstall.ps1
│               └── Write_ToLog.ps1
└── directory_tree.md
```

## Key Components

### Windows Software Installation

The Windows Software Installation directory contains scripts for installing software on Windows systems:

- `setup_software.ps1`: Main script for setting up software on Windows
- `WingetGUI_Installer/`: GUI application for installing software via Winget

#### WingetGUI_Installer Structure

The WingetGUI_Installer application is organized as follows:

- `EnvSetup/`: Main directory for the environment setup tool
  - `Env_Setup.ps1`: Main script that orchestrates the installation/uninstallation process
  - `Public/`: Contains modular PowerShell scripts that are sourced by the main script
    - `Install.ps1`: Contains all installation-related functions
    - `Uninstall.ps1`: Contains all uninstallation-related functions
    - `GUI.ps1`: Contains GUI-related functions
    - Other utility scripts for logging, JSON handling, etc.
  - `JSON/install/`: Contains JSON configuration files defining what to install
  - `Private/`: Contains private resources like images for documentation

### Linux Software Installation

The Linux Software Installation directory contains scripts for installing software on Linux systems:

- `setup-software.sh`: Main script for setting up software on Linux

### Linux Driver Setup

The Linux Driver Setup directory contains scripts for setting up drivers on Linux systems:

- `build-static-installer.sh`: Script for building static installers
- `Dynamic/`: Contains dynamic setup scripts
- `Utilities/`: Contains utility scripts for compatibility checking and connectivity verification
