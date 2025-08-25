# GUI Module Refactoring

This folder contains the code for the Environment Setup Tool, which has been refactored to separate GUI components from the main script.

## Files

- `Env_Setup.ps1` - Main script for environment setup
- `Public/GUI.ps1` - All GUI-related functions extracted to a separate module
- `Public/Write_ToLog.ps1` - Logging utility
- `Public/Append-ToJson.ps1` - JSON manipulation utility
- `Public/Pre_Req.ps1` - Prerequisite checking utility
- `Public/Run_Once_Eula.ps1` - EULA agreement handling

## Structure Changes

The codebase has been reorganized to improve maintainability:

1. **Separation of Concerns**: All GUI code now resides in `Public/GUI.ps1`, making it easier to maintain both the core installation logic and the user interface separately.

2. **Improved Modularity**: The GUI module can be updated independently of the core logic.

3. **Better Testability**: Core installation/uninstallation functions can be tested without GUI dependencies.

## How It Works

The main `Env_Setup.ps1` script sources the GUI module using:

```powershell
. ".\Public\GUI.ps1" # Sources GUI functions
```

When running in GUI mode, it calls the appropriate GUI functions from the module. The installation/uninstallation logic remains in the main script but is called by the GUI when needed.

## Functions

### GUI.ps1 Functions

- `Show-MainGUI` - Displays the main menu with install/uninstall options
- `Show-PackageSelectionGUI` - Displays package selection interface
- `Show-InstallResults` - Shows installation results
- `Show-UninstallGUI` - Displays uninstall selection interface
- `Show-UninstallResults` - Shows uninstallation results

### Env_Setup.ps1 Functions (selected)

- `Install-SelectedPackages` - Installs selected packages
- `Uninstall-SelectedPackages` - Uninstalls selected packages
- `Install-WingetApplication` - Installs a single winget application
- `Install-ExternalApplication` - Installs a single external application
- `Uninstall-WingetApplication` - Uninstalls a single winget application
- `Uninstall-ExternalApplication` - Uninstalls a single external application

## Execution Flow

1. `Env_Setup.ps1` is run with a command parameter (`install`, `gui`, or `uninstall`)
2. For `gui` mode, `Show-MainGUI` is called from the GUI module
3. The GUI module calls back into `Env_Setup.ps1` functions to perform installation/uninstallation
4. Results are displayed using GUI module functions
