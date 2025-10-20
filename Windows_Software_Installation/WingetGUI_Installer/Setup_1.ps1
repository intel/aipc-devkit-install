# This script is designed to set up a development environment on Windows using winget.
# It installs or updates a list of applications, including Visual Studio, Python, and others.
# It also sets the execution policy to Unrestricted to allow script execution.
# **********************************************#
# IMPORTANT: This script must be run from an elevated PowerShell prompt.
# Usage:
# If execution policy prevents scripts from running, use:
# powershell.exe -ExecutionPolicy RemoteSigned -File ".\Setup_1.ps1" install
# powershell.exe -ExecutionPolicy RemoteSigned -File ".\Setup_1.ps1" gui
# Or set policy first: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
# ./Setup_1.ps1 install -> Installs software (command line mode)
# ./Setup_1.ps1 gui -> Shows GUI for interactive package selection and installation/uninstallation
# ./Setup_1.ps1 uninstall -> Uninstalls software
# ***************************************** #
<#
.SYNOPSIS
    Setup script for development environment installation using winget.

.DESCRIPTION
    This script automates the installation of development tools and software
    using the Windows Package Manager (winget). It supports both GUI and command-line
    modes for installation and uninstallation.

.PARAMETER command
    Specifies the operation mode: 'install', 'gui', or 'uninstall'.
    
.EXAMPLE
    .\Setup_1.ps1 gui
    Launches the graphical interface for interactive software selection.
    
.EXAMPLE
    .\Setup_1.ps1 install
    Installs all software defined in the applications.json file.
    
.EXAMPLE
    .\Setup_1.ps1 uninstall
    Uninstalls previously installed software tracked in uninstall.json.

.NOTES
    Requires Administrator privileges to run.
    Authors: 
    - Vijay (vijay.chandrashekar@intel.com)
    - Ram (vaithi.s.ramadoss@intel.com)
    - Ben (benjamin.j.odom@intel.com)
#>
param(
    [Parameter(Position=0)]
    [string]$command # Accepts a command parameter: install, gui, or uninstall
)


# ===================== GENERIC IMPORTANT INSTALLATION WARNING =====================
Write-Host "=======================================================================================" -ForegroundColor Yellow
Write-Host "*** IMPORTANT ACTION REQUIRED: If you have any existing applications already installed," -ForegroundColor White -BackgroundColor DarkRed
Write-Host "please uninstall them first and then use this utility to install. Installing the same " -ForegroundColor White -BackgroundColor DarkRed
Write-Host "application in two different ways may cause conflicts and the application may not work as" -ForegroundColor White -BackgroundColor DarkRed
Write-Host "expected. User discretion is mandatory. ***" -ForegroundColor White -BackgroundColor DarkRed
Write-Host ""
Write-Host ""
Write-Host "*** Recommended System Requirements:  This SDK will work best on systems that contain  " -ForegroundColor White -BackgroundColor Blue
Write-Host ""Intel`u{00AE} Core`u{2122} Ultra processors and Intel Arc`u{2122}" GPUs, it will work on other products but " -ForegroundColor White -BackgroundColor Blue
Write-Host "not all features will be supported. ***" -ForegroundColor White -BackgroundColor Blue
Write-Host "=======================================================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host ""
Write-Host "Waiting 5 seconds for you to review this warning..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Ensure execution policy allows script execution (do this first)
try {
    $currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
    if ($currentPolicy -eq "Restricted" -or $currentPolicy -eq "AllSigned") {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Write-Host "Updated execution policy from $currentPolicy to RemoteSigned for CurrentUser" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Warning: Could not set execution policy: $_" -ForegroundColor Yellow
}

# Process command parameters - handle both dash and no-dash formats
if ($command -match "^-{1,2}(\w+)$") {
    $command = $matches[1]  # Extract the command name without dashes
}

Write-Host "Running in mode: $command" -ForegroundColor Cyan

<#
    Global variables
#>
# If external = $true, this means the script is for the customer, meaning they must accept the EULA pop-up
# If external = $false, this means it is "internal", the user will NOT have to accept the EULA pop-up
# By switching this to false YOU acknowledge that this script will NOT be provided toward customers to be used on their own personal machines
$Global:external = $false # Indicates whether the script is for external use, affecting EULA acceptance
$task_name = "AIPCCloud ENV Setup" # Name of the scheduled task for environment setup

<#
    Administrator privilege checking
#>
function Test-Administrator {
# Check for at least 100GB free disk space before proceeding
function Test-FreeDiskSpace {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$false)]
        [int]$minGB = 100
    )
    $drive = (Get-Location).Path.Substring(0,1)
    $freeSpaceGB = [math]::Round((Get-PSDrive -Name $drive).Free/1GB,2)
    Write-Host "=============================================================" -ForegroundColor Yellow
    Write-Host "Disk space available on $($drive): $freeSpaceGB GB" -ForegroundColor Magenta
    if ($freeSpaceGB -lt $minGB) {
        Write-Host "!!! RECOMMENDED: At least $minGB GB of free disk space for smooth installation !!!" -ForegroundColor Red -BackgroundColor Yellow
        Write-Host "Only $freeSpaceGB GB available. You may proceed, but issues may occur if space runs out." -ForegroundColor Yellow
        Write-Host "Waiting 5 seconds for you to review this warning..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    } else {
        Write-Host "You have adequate disk space to continue installation." -ForegroundColor Green
    }
    Write-Host "=============================================================" -ForegroundColor Yellow

}

# Run disk space check before any installation or GUI mode
if ($command -eq 'install' -or $command -eq 'gui') {
    Test-FreeDiskSpace
}
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-AdminPrivileges {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$commandToRun = ""
    )
    
    if (-not (Test-Administrator)) {
        Add-Type -AssemblyName System.Windows.Forms
        $result = [System.Windows.Forms.MessageBox]::Show(
            "This application requires administrator privileges to install software.`n`nWould you like to restart as administrator?",
            'Administrator Required',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        
        if ($result -eq 'Yes') {
            # Restart as administrator
            $scriptPath = $PSCommandPath
            if (-not $scriptPath) {
                $scriptPath = $MyInvocation.MyCommand.Path
            }
            
            $argumentList = if ($commandToRun) { "-ExecutionPolicy RemoteSigned -File `"$scriptPath`" $commandToRun" } else { "-ExecutionPolicy RemoteSigned -File `"$scriptPath`"" }
            Start-Process -FilePath "powershell.exe" -ArgumentList $argumentList -Verb RunAs
        }
        
        # Exit current instance
        exit
    }
}

Set-Location -Path $PSScriptRoot # Sets the current directory to the script's location
$logs_dir = "C:\temp\logs" # Directory for storing log files
$json_dir = ".\json" # Directory for storing JSON files

# Ensure C:\temp directory exists
if (-not (Test-Path -Path "C:\temp")) {
    New-Item -Path "C:\temp" -ItemType Directory -Force | Out-Null
    Write-Host "Created C:\temp directory for logs" -ForegroundColor Yellow
}

# Source helper scripts
. ".\Public\Write_ToLog.ps1" # Sources a script for logging messages
. ".\Public\Append-ToJson.ps1" # Sources a script for appending data to JSON files
. ".\Public\Pre_Req.ps1" # Sources a script for checking pre-requisites
. ".\Public\GUI.ps1" # Sources GUI functions
. ".\Public\Install.ps1" # Sources installation functions
. ".\Public\Uninstall.ps1" # Sources uninstallation functions

<#
    Initializes logs for installation
#>
function Initialize-Directory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$location
    )
    
    if (-not (Test-Path -Path $location)) {
        New-Item -Path $location -ItemType Directory | Out-Null # Creates a directory if it doesn't exist
    }
}


<#
    Creates a file at the given location
#>
function New-File {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$location
    )
    
    if (-not (Test-Path -Path $location)) {
        New-Item -Path $location -ItemType File | Out-Null # Creates a file if it doesn't exist
    }
}


<#
    Calls script for user to accept EULA agreements for ALL software this script installs
    Returns true if they accept, false otherwise
#>
function Confirm-Eula {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    # Source Script
    $run_once = ".\Public\Run_Once_Eula.ps1" # Path to the EULA acceptance script
    & $run_once # Executes the EULA acceptance script
    return $? # Returns the exit status of the EULA script
}

try {

    # Check for administrator privileges for GUI, install, and uninstall commands
    if ($command -eq "gui" -or $command -eq "install" -or $command -eq "uninstall") {
        Request-AdminPrivileges -commandToRun $command
    }

    # Log directory structure
    $install_logs_dir = "$logs_dir\install" # Directory for installation logs
    $uninstall_logs_dir = "$logs_dir\uninstall" # Directory for uninstallation logs
    $error_logs_dir = "$logs_dir\error" # Directory for error logs

    # Logs text file locations
    $install_log_file = "$install_logs_dir\install_log.txt" # File for installation logs
    $uninstall_log_file = "$uninstall_logs_dir\uninstall.txt" # File for uninstallation logs
    $error_log_file = "$error_logs_dir\error_log.txt" # File for error logs

    # Json file structure
    $json_install_dir = "$json_dir\install" # Directory for installation JSON files
    $json_uninstall_dir = "$json_dir\uninstall" # Directory for uninstallation JSON files
    $json_install_file_path = "$json_install_dir\applications.json" # Path to the applications JSON file
    $json_uninstall_file_path = "$json_uninstall_dir\uninstall.json" # Path to the uninstallation JSON file

    # ============================== Reading JSON and organizing items =====================

    # Read items from applications.json 

    if ($command -eq "gui") {
        # GUI mode for interactive package selection
        
        # Setup logging directories and files for both install and uninstall operations
        Initialize-Directory $install_logs_dir
        Initialize-Directory $error_logs_dir
        Initialize-Directory $uninstall_logs_dir
        New-File $install_log_file
        New-File $error_log_file
        New-File $uninstall_log_file

        # Setup uninstall json file
        Initialize-Directory $json_uninstall_dir

        # Check for pre-requisites
        $pre_req = Check-PreReq
        if (-not $pre_req) {
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.MessageBox]::Show(
                "Pre-requisites not met. Please ensure winget is available.",
                'Environment Setup - Error',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            exit 1
        }

        # If running externally, have user agree to EULA pop-up
        if ($Global:external) {
            if (-not (Confirm-Eula)) {
                Add-Type -AssemblyName System.Windows.Forms
                [System.Windows.Forms.MessageBox]::Show(
                    "EULA not accepted. Installation cancelled.",
                    'Environment Setup',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
                exit 1
            }
            else {
                $host_name = hostname
                Write-ToLog -message "Hostname: $host_name has accepted the EULA Agreement" -log_file $install_log_file
            }
        }

        $applications = Get-Content -Path $json_install_file_path -Raw | ConvertFrom-Json

        # Prep winget so no hanging
        winget list --accept-source-agreements > $null 2>&1

        # Show main GUI menu
        Show-MainGUI -applications $applications -install_log_file $install_log_file -json_uninstall_file_path $json_uninstall_file_path
    }
    elseif ($command -eq "install") {

        # Setup logging directories and files
        Initialize-Directory $install_logs_dir
        Initialize-Directory $error_logs_dir
        New-File $install_log_file
        New-File $error_log_file

        # Create JSON directory for uninstall files if it doesn't exist
        Initialize-Directory $json_uninstall_dir
        New-File $json_uninstall_file_path

        # Create the base JSON structure in the uninstall file
        $json_structure = @{
            "winget_applications" = @()
            "external_applications" = @()
        }
        $json_structure | ConvertTo-Json | Set-Content -Path $json_uninstall_file_path

        # Check for pre-requisites
        $pre_req = Check-PreReq # Calls a function to check pre-requisites
        if ($pre_req) {
            Write-ToLog -message "All pre-requisites complete. Installing." -log_file $install_log_file
        }
        else {
            Write-ToLog -message "Pre-requisites not met. Exiting." -log_file $install_log_file
            Write-Host "Pre-requisites not met. Exiting." -ForegroundColor Red
            exit 1 # Exits the script if pre-requisites are not met
        }

        # If running externally, have user agree to EULA pop-up
        if ($Global:external) {
          
            if (-not (Confirm-Eula)) {
                Write-Host "Eula not accepted. Exiting." -ForegroundColor Red
                Write-ToLog -message "Eula not accepted. Exiting." -log_file $install_log_file
                exit 1 # Exits the script if EULA is not accepted
            }
            else {
                Write-Host "Eula accepted. Proceeding." -ForegroundColor Green
                $host_name = hostname
                Write-ToLog -message "Hostname: $host_name has accepted the EULA Agreement" -log_file $install_log_file
            }
        }

        # Debug JSON file path
        Write-Host "Debug: Loading JSON from path: $json_install_file_path" -ForegroundColor Magenta
        if (Test-Path -Path $json_install_file_path) {
            Write-Host "Debug: JSON file exists" -ForegroundColor Magenta
            try {
                $applications = Get-Content -Path $json_install_file_path -Raw | ConvertFrom-Json # Reads and parses the JSON file
                Write-Host "Debug: JSON file loaded successfully" -ForegroundColor Magenta
                
                # Print out which items are going to be downloaded (skip_install != yes)
                $toInstall = $applications.winget_applications | Where-Object { -not $_.skip_install -or $_.skip_install.ToString().ToLower() -ne 'yes' }
                Write-Host "Preparing to install the following applications:" -ForegroundColor Yellow
                foreach ($app in $toInstall) {
                    $app_id = if ($app.id) { $app.id } else { $app.name }
                    $friendly_name = if ($app.friendly_name) { $app.friendly_name } else { $app_id }
                    Write-Host "- $friendly_name ($app_id) - Source: Winget" -ForegroundColor Green
                    if ($null -ne $app.dependencies) {
                        Write-Host "  Dependencies:" -ForegroundColor Blue
                        foreach ($dep in $app.dependencies) {
                            Write-Host "    - $($dep.name) v$($dep.version)" -ForegroundColor Blue
                        }
                    }
                }
            } catch {
                Write-Host "Debug: Error loading JSON file: $_" -ForegroundColor Red
                Write-Host "Current directory: $(Get-Location)" -ForegroundColor Magenta
                Write-Host "JSON file path: $json_install_file_path" -ForegroundColor Magenta
                exit 1
            }
        } else {
            Write-Host "Debug: JSON file does not exist at path: $json_install_file_path" -ForegroundColor Red
            Write-Host "Current directory: $(Get-Location)" -ForegroundColor Magenta
            Write-Host "Checking parent directories..." -ForegroundColor Magenta
            $alternativePath = "$PSScriptRoot\..\JSON\install\applications.json"
            if (Test-Path -Path $alternativePath) {
                Write-Host "Found JSON at alternative path: $alternativePath" -ForegroundColor Green
                $json_install_file_path = $alternativePath
                $applications = Get-Content -Path $json_install_file_path -Raw | ConvertFrom-Json
                
                # Print out which items are going to be downloaded
                Write-Host "Preparing to install the following applications:" -ForegroundColor Yellow
                foreach ($app in $applications.winget_applications) {
                    $app_id = if ($app.id) { $app.id } else { $app.name }
                    $friendly_name = if ($app.friendly_name) { $app.friendly_name } else { $app_id }
                    Write-Host "- $friendly_name ($app_id) - Source: Winget" -ForegroundColor Green
                    if ($null -ne $app.dependencies) {
                        Write-Host "  Dependencies:" -ForegroundColor Blue
                        foreach ($dep in $app.dependencies) {
                            Write-Host "    - $($dep.name) v$($dep.version)" -ForegroundColor Blue
                        }
                    }
                }
            } else {
                Write-Host "Alternative path also not found. Exiting." -ForegroundColor Red
                exit 1
            }
        }

        $toInstallExternal = $applications.external_applications | Where-Object { -not $_.skip_install -or $_.skip_install.ToString().ToLower() -ne 'yes' }
        Write-Host "Additional external applications" -ForegroundColor Yellow
        foreach ($app in $toInstallExternal) {
            $friendly_name = if ($app.friendly_name) { $app.friendly_name } else { $app.name }
            Write-Host "- $friendly_name ($($app.name)) - Source: External" -ForegroundColor Green
            if ($null -ne $app.dependencies) {
                Write-Host "  Dependencies:" -ForegroundColor Blue
                foreach ($dep in $app.dependencies) {
                    Write-Host "    - $($dep.name) v$($dep.version)" -ForegroundColor Blue
                }
            }
        }

        # Prep winget so no hanging
        winget list --accept-source-agreements > $null 2>&1 # Prepares winget by accepting source agreements

        # Get installed packages to check dependencies
        $winget_list = Get-WinGetPackage # Retrieves the list of installed winget packages

        # Check dependencies
        foreach ($app in $applications.winget_applications) {
            if ($null -ne $app.dependencies) {
                foreach ($dep in $app.dependencies) {
                    $depName = $dep.name
                    
                    # Check if dependency is already in the list of applications to install
                    $dependencyApp = $applications.winget_applications | Where-Object { 
                        ($_.id -match $depName) -or ($_.name -match $depName) -or ($_.friendly_name -match $depName)
                    }

                    if ($null -eq $dependencyApp) {
                        # Check if dependency is already installed on the system
                        $isInstalled = $winget_list | Where-Object { $_.Name -match $depName }

                        if ($null -eq $isInstalled) {
                            Write-Host "Dependency $depName required for $app_id is not installed and not in the install list. Skipping $app_id" -ForegroundColor Yellow
                            # Remove the application from the list if its dependency can't be met
                            $applications.winget_applications = $applications.winget_applications | Where-Object { 
                                ($_.id -ne $app_id) -and ($_.name -ne $app_id)
                            }
                        } 
                    }
                }
            }
        }

    # Invoke the installation process (per-app tracking, pass loaded app arrays)
    # Install winget applications
    if ($applications.winget_applications) {
        $wingetToInstall = $applications.winget_applications | Where-Object { -not $_.skip_install -or $_.skip_install.ToString().ToLower() -ne 'yes' }
        if ($wingetToInstall.Count -gt 0) {
            Install-SelectedPackages -selectedPackages $wingetToInstall -log_file $install_log_file -uninstall_json_file $json_uninstall_file_path
        }
    }

    # Install external applications
    if ($applications.external_applications) {
        $externalToInstall = $applications.external_applications | Where-Object { -not $_.skip_install -or $_.skip_install.ToString().ToLower() -ne 'yes' }
        if ($externalToInstall.Count -gt 0) {
            Install-SelectedPackages -selectedPackages $externalToInstall -log_file $install_log_file -uninstall_json_file $json_uninstall_file_path
        }
    }

        # Copy install logs to desktop
        $username = [Environment]::UserName
        Copy-Item -Path $install_log_file -Destination "C:\Users\$username\Desktop\install_logs.txt" # Copies the install log to the user's desktop

        # Check if uninstall.json was created and show summary
        if (Test-Path -Path $json_uninstall_file_path) {
            Write-Host "Uninstall.json created successfully at: $json_uninstall_file_path" -ForegroundColor Green
            $uninstallData = Get-Content -Path $json_uninstall_file_path -Raw | ConvertFrom-Json
            $wingetCount = if ($uninstallData.winget_applications) { $uninstallData.winget_applications.Count } else { 0 }
            $externalCount = if ($uninstallData.external_applications) { $uninstallData.external_applications.Count } else { 0 }
            Write-Host "Tracked for uninstall: $wingetCount winget apps, $externalCount external apps" -ForegroundColor Yellow
        } else {
            Write-Host "Warning: Uninstall.json was not created!" -ForegroundColor Red
        }

        if (-not $Global:external) {
            # Check if the scheduled task exists before trying to unregister it
            try {
                $existingTask = Get-ScheduledTask -TaskName $task_name -ErrorAction SilentlyContinue
                if ($existingTask) {
                    Unregister-ScheduledTask -TaskName $task_name -Confirm:$false
                    Write-ToLog -message "Successfully unregistered scheduled task: $task_name" -log_file $install_log_file
                } else {
                    Write-ToLog -message "Scheduled task '$task_name' not found - nothing to unregister" -log_file $install_log_file
                }
            }
            catch {
                Write-ToLog -message "Failed to unregister scheduled task: $($_.Exception.Message)" -log_file $install_log_file
                Write-Host "Warning: Could not unregister scheduled task '$task_name'" -ForegroundColor Yellow
            }
        }
    }
    elseif ($command -eq "uninstall") {
        Write-Host "Running in mode: uninstall" -ForegroundColor Yellow
        
        # Setup uninstall logs
        Initialize-Directory $uninstall_logs_dir
        New-File $uninstall_log_file
        Write-ToLog -message "Starting uninstall process" -log_file $uninstall_log_file
        
        if (-not (Test-Path -Path $json_uninstall_file_path)) {
            $errorMessage = "No uninstall file found at: $json_uninstall_file_path. Please run installer first to create tracking file."
            Write-Host $errorMessage -ForegroundColor Red
            Write-ToLog -message $errorMessage -log_file $uninstall_log_file
            Write-Host "Would you like to create an empty uninstall file to proceed? (y/n)" -ForegroundColor Yellow
            $choice = Read-Host
            
            if ($choice -eq "y") {
                try {
                    # Create directory if it doesn't exist
                    $uninstallDir = Split-Path -Path $json_uninstall_file_path -Parent
                    if (-not (Test-Path -Path $uninstallDir)) {
                        New-Item -Path $uninstallDir -ItemType Directory -Force | Out-Null
                        Write-Host "Created directory: $uninstallDir" -ForegroundColor Green
                    }
                    
                    # Create empty uninstall JSON file
                    $emptyJson = @{
                        "winget_applications" = @()
                        "external_applications" = @()
                    }
                    $emptyJson | ConvertTo-Json -Depth 4 | Set-Content -Path $json_uninstall_file_path -Force
                    Write-Host "Created empty uninstall file at: $json_uninstall_file_path" -ForegroundColor Green
                    Write-ToLog -message "Created empty uninstall file" -log_file $uninstall_log_file
                }
                catch {
                    Write-Host "Failed to create uninstall file: $_" -ForegroundColor Red
                    Write-ToLog -message "Failed to create uninstall file: $_" -log_file $uninstall_log_file
                    exit 1
                }
            }
            else {
                Write-Host "Uninstall operation cancelled" -ForegroundColor Yellow
                exit 0
            }
        }
        
        # Invoke the batch uninstallation process
        Invoke-BatchUninstall -json_uninstall_file_path $json_uninstall_file_path -uninstall_log_file $uninstall_log_file
        
        Write-Host "Uninstallation process completed. Check $uninstall_log_file for details." -ForegroundColor Green
    }
    else {
        $help_str = 
        @"
            Usage:
                .\Setup_1.ps1 gui
                  or
                .\Setup_1.ps1 -gui
                  or
                .\Setup_1.ps1 --gui
                    Shows a Windows Forms interface for interactive package selection and installation/uninstallation
                
                .\Setup_1.ps1 install
                  or
                .\Setup_1.ps1 -install
                  or
                .\Setup_1.ps1 --install
                    Installs all software specified in applications.json, checking for dependencies
                
                .\Setup_1.ps1 uninstall
                  or
                .\Setup_1.ps1 -uninstall
                  or
                .\Setup_1.ps1 --uninstall
                    Uninstalls all software specified in uninstall.json
"@
        Write-Host $help_str -ForegroundColor Red # Displays usage instructions if the command is invalid
    }
}
catch {
    Write-ToLog -message $_.Exception.Message -log_file $error_log_file # Logs any exceptions that occur
    Write-Host "$($_.Exception.Message)" -ForegroundColor Red # Displays the exception message
    Write-Host "An error occurred during installation. See error log files" -ForegroundColor Red # Informs the user of an error
    #Write-Host $Error[0].ScriptStackTrace # Optionally displays the script stack trace
}
