# Windows AI PC Environment Setup

This directory contains the core environment setup scripts for Windows AI PC development.

## Quick Start

### GUI Mode (Recommended)
```powershell
.\Env_Setup.ps1 gui
```

### Command Line Mode
```powershell
# Install packages
.\Env_Setup.ps1 install

# Uninstall packages  
.\Env_Setup.ps1 uninstall
```

## What's Included

- **`Env_Setup.ps1`** - Main setup script with GUI and command-line modes
- **`JSON/install/applications.json`** - Package configuration file
- **`JSON/uninstall/uninstall.json`** - Tracking file for installed packages
- **`Public/`** - Core functionality modules
- **`logs/`** - Installation and error logs

## Features

- ✅ **Modern GUI Interface** - Easy package selection and management
- ✅ **AI Development Focus** - Curated packages for AI/ML development
- ✅ **Smart Tracking** - Automatic tracking of installed packages
- ✅ **Robust Error Handling** - Comprehensive logging and retry logic
- ✅ **Bidirectional Compatibility** - Install/uninstall via GUI or command line

## Requirements

- Windows 10/11 with PowerShell 5.1+
- Windows Package Manager (winget) version 1.10.X or higher
- Administrator privileges (auto-requested when needed)
- Internet connection for package downloads

## For More Information

See the main [Windows_Software_Installation README](../README.md) for complete documentation, troubleshooting, and advanced configuration options.
