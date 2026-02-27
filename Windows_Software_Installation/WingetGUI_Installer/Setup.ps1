<#
.SYNOPSIS
    Entry point for the AI PC Dev Kit Environment Setup.

.DESCRIPTION
    Thin entry-point that imports the DevKitInstaller module, configures
    it, and delegates to the appropriate command (gui / install / uninstall).
    All business logic lives inside the module — this file only handles
    parameter parsing, path setup, and orchestration.

.PARAMETER command
    Specifies the operation mode: 'install', 'gui', or 'uninstall'.

.EXAMPLE
    .\Setup.ps1 gui
    Launches the graphical interface for interactive software selection.

.EXAMPLE
    .\Setup.ps1 install
    Installs all software from applications.json (command-line mode).

.EXAMPLE
    .\Setup.ps1 uninstall
    Uninstalls previously installed software tracked in uninstall.json.

.NOTES
    Requires Administrator privileges.
    Authors:
      - Vijay (vijay.chandrashekar@intel.com)
      - Ben   (benjamin.j.odom@intel.com)
#>
param(
    [Parameter(Position = 0)]
    [string]$command
)

# ===================== IMPORTANT INSTALLATION WARNING =====================
Write-Host "=======================================================================================" -ForegroundColor Yellow
Write-Host "*** IMPORTANT ACTION REQUIRED: If you have any existing applications already installed," -ForegroundColor White -BackgroundColor DarkRed
Write-Host "please uninstall them first and then use this utility to install. Installing the same " -ForegroundColor White -BackgroundColor DarkRed
Write-Host "application in two different ways may cause conflicts and the application may not work as" -ForegroundColor White -BackgroundColor DarkRed
Write-Host "expected. User discretion is mandatory. ***" -ForegroundColor White -BackgroundColor DarkRed
Write-Host ""
Write-Host ""
Write-Host "*** Recommended System Requirements:  This SDK will work best on systems that contain  " -ForegroundColor White -BackgroundColor Blue
Write-Host ("Intel$([char]0x00AE) Core$([char]0x2122) Ultra processors and Intel Arc$([char]0x2122) GPUs, it will work on other products but ") -ForegroundColor White -BackgroundColor Blue
Write-Host "not all features will be supported. ***" -ForegroundColor White -BackgroundColor Blue
Write-Host "=======================================================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host ""
Write-Host "Waiting 5 seconds for you to review this warning..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# ── Execution-policy guard ──────────────────────────────────────────────
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

# ── Normalise command parameter ─────────────────────────────────────────
if ($command -match "^-{1,2}(\w+)$") {
    $command = $matches[1]
}
Write-Host "Running in mode: $command" -ForegroundColor Cyan

# ── Configuration ───────────────────────────────────────────────────────
# If $ExternalMode is $true the EULA dialog is shown (customer-facing).
# Set to $false for internal / lab use (no EULA).
$ExternalMode = $false
$task_name    = "AIPCCloud ENV Setup"

# ── Resolve paths (all absolute) ────────────────────────────────────────
Set-Location -Path $PSScriptRoot

$logs_dir                = "C:\temp\logs"
$install_logs_dir        = "$logs_dir\install"
$uninstall_logs_dir      = "$logs_dir\uninstall"
$error_logs_dir          = "$logs_dir\error"

$install_log_file        = "$install_logs_dir\install_log.txt"
$uninstall_log_file      = "$uninstall_logs_dir\uninstall.txt"
$error_log_file          = "$error_logs_dir\error_log.txt"

$json_dir                = Join-Path $PSScriptRoot "JSON"
$json_install_file_path  = Join-Path $json_dir "install\applications.json"
$json_uninstall_dir      = Join-Path $json_dir "uninstall"
$json_uninstall_file_path = Join-Path $json_uninstall_dir "uninstall.json"

# Ensure C:\temp exists
if (-not (Test-Path -Path "C:\temp")) {
    New-Item -Path "C:\temp" -ItemType Directory -Force | Out-Null
    Write-Host "Created C:\temp directory for logs" -ForegroundColor Yellow
}

# ── Import the module ───────────────────────────────────────────────────
$modulePath = Join-Path $PSScriptRoot "DevKitInstaller"
Import-Module $modulePath -Force -ErrorAction Stop

# Tell the module where files live and which mode we are in
Set-DevKitConfig -ExternalMode $ExternalMode `
                 -JsonInstallFile $json_install_file_path `
                 -JsonUninstallFile $json_uninstall_file_path

# ── Local utility helpers (used only by this entry-point) ───────────────

function Initialize-Directory {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$location)
    if (-not (Test-Path -Path $location)) {
        New-Item -Path $location -ItemType Directory | Out-Null
    }
}

function New-File {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$location)
    if (-not (Test-Path -Path $location)) {
        New-Item -Path $location -ItemType File | Out-Null
    }
}

function Test-FreeDiskSpace {
    [CmdletBinding()]
    [OutputType([bool])]
    param([int]$minGB = 100)

    $drive       = (Get-Location).Path.Substring(0, 1)
    $freeSpaceGB = [math]::Round((Get-PSDrive -Name $drive).Free / 1GB, 2)

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

# ── Disk-space check (install / gui only) ───────────────────────────────
if ($command -eq 'install' -or $command -eq 'gui') {
    Test-FreeDiskSpace
}

# ── Orchestration ───────────────────────────────────────────────────────
try {
    # Admin elevation for all operational commands
    if ($command -eq "gui" -or $command -eq "install" -or $command -eq "uninstall") {
        Request-AdminPrivileges -commandToRun $command -ScriptPath $PSCommandPath
    }

    if ($command -eq "gui") {
        # -- GUI mode -------------------------------------------------------
        Initialize-Directory $install_logs_dir
        Initialize-Directory $error_logs_dir
        Initialize-Directory $uninstall_logs_dir
        New-File $install_log_file
        New-File $error_log_file
        New-File $uninstall_log_file
        Initialize-Directory $json_uninstall_dir

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

        if ($ExternalMode) {
            if (-not (Confirm-Eula)) {
                Add-Type -AssemblyName System.Windows.Forms
                [System.Windows.Forms.MessageBox]::Show(
                    "EULA not accepted. Installation cancelled.",
                    'Environment Setup',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
                exit 1
            } else {
                $host_name = hostname
                Write-ToLog -message "Hostname: $host_name has accepted the EULA Agreement" -log_file $install_log_file
            }
        }

        $applications = Get-Content -Path $json_install_file_path -Raw | ConvertFrom-Json
        winget list --accept-source-agreements > $null 2>&1

        Show-MainGUI -applications $applications `
                     -install_log_file $install_log_file `
                     -json_uninstall_file_path $json_uninstall_file_path
    }
    elseif ($command -eq "install") {
        # -- Install mode ---------------------------------------------------
        Initialize-Directory $install_logs_dir
        Initialize-Directory $error_logs_dir
        New-File $install_log_file
        New-File $error_log_file
        Initialize-Directory $json_uninstall_dir

        # Preserve existing uninstall tracking data
        if (-not (Test-Path -Path $json_uninstall_file_path)) {
            @{ winget_applications = @(); external_applications = @() } |
                ConvertTo-Json | Set-Content -Path $json_uninstall_file_path
        } else {
            try {
                $existingContent = Get-Content -Path $json_uninstall_file_path -Raw
                if ([string]::IsNullOrWhiteSpace($existingContent)) { throw "Empty file" }
                $null = $existingContent | ConvertFrom-Json
                Write-Host "Existing uninstall tracking file found and valid. Preserving previous data." -ForegroundColor Green
            } catch {
                Write-Host "Uninstall tracking file was corrupted or empty. Recreating." -ForegroundColor Yellow
                @{ winget_applications = @(); external_applications = @() } |
                    ConvertTo-Json | Set-Content -Path $json_uninstall_file_path
            }
        }

        # Pre-requisites
        $pre_req = Check-PreReq
        if ($pre_req) {
            Write-ToLog -message "All pre-requisites complete. Installing." -log_file $install_log_file
        } else {
            Write-ToLog -message "Pre-requisites not met. Exiting." -log_file $install_log_file
            Write-Host "Pre-requisites not met. Exiting." -ForegroundColor Red
            exit 1
        }

        # EULA (external mode only)
        if ($ExternalMode) {
            if (-not (Confirm-Eula)) {
                Write-Host "Eula not accepted. Exiting." -ForegroundColor Red
                Write-ToLog -message "Eula not accepted. Exiting." -log_file $install_log_file
                exit 1
            } else {
                Write-Host "Eula accepted. Proceeding." -ForegroundColor Green
                $host_name = hostname
                Write-ToLog -message "Hostname: $host_name has accepted the EULA Agreement" -log_file $install_log_file
            }
        }

        # Load applications JSON
        Write-Host "Debug: Loading JSON from path: $json_install_file_path" -ForegroundColor Magenta
        if (-not (Test-Path -Path $json_install_file_path)) {
            Write-Host "JSON file does not exist at path: $json_install_file_path" -ForegroundColor Red
            exit 1
        }

        $applications = Get-Content -Path $json_install_file_path -Raw | ConvertFrom-Json
        Write-Host "Debug: JSON file loaded successfully" -ForegroundColor Magenta

        # Show what will be installed
        $toInstall = $applications.winget_applications | Where-Object {
            -not $_.skip_install -or $_.skip_install.ToString().ToLower() -ne 'yes'
        }
        Write-Host "Preparing to install the following applications:" -ForegroundColor Yellow
        foreach ($app in $toInstall) {
            $app_id        = if ($app.id) { $app.id } else { $app.name }
            $friendly_name = if ($app.friendly_name) { $app.friendly_name } else { $app_id }
            Write-Host "- $friendly_name ($app_id) - Source: Winget" -ForegroundColor Green
            if ($null -ne $app.dependencies) {
                Write-Host "  Dependencies:" -ForegroundColor Blue
                foreach ($dep in $app.dependencies) {
                    Write-Host "    - $($dep.name) v$($dep.version)" -ForegroundColor Blue
                }
            }
        }

        $toInstallExternal = $applications.external_applications | Where-Object {
            -not $_.skip_install -or $_.skip_install.ToString().ToLower() -ne 'yes'
        }
        if ($toInstallExternal) {
            Write-Host "Additional external applications:" -ForegroundColor Yellow
            foreach ($app in $toInstallExternal) {
                $friendly_name = if ($app.friendly_name) { $app.friendly_name } else { $app.name }
                Write-Host "- $friendly_name ($($app.name)) - Source: External" -ForegroundColor Green
            }
        }

        # Prep winget
        winget list --accept-source-agreements > $null 2>&1

        # Dependency check
        $winget_list = Get-WinGetPackage
        foreach ($app in $applications.winget_applications) {
            if ($null -ne $app.dependencies) {
                $appIdentifier  = if ($app.id) { $app.id } else { $app.name }
                $appDisplayName = if ($app.friendly_name) { $app.friendly_name } else { $appIdentifier }
                foreach ($dep in $app.dependencies) {
                    $depName       = $dep.name
                    $dependencyApp = $applications.winget_applications | Where-Object {
                        ($_.id -match $depName) -or ($_.name -match $depName) -or ($_.friendly_name -match $depName)
                    }
                    if ($null -eq $dependencyApp) {
                        $isInstalled = $winget_list | Where-Object { $_.Name -match $depName }
                        if ($null -eq $isInstalled) {
                            Write-Host "Dependency $depName required for $appDisplayName is not installed and not in the install list. Skipping $appDisplayName" -ForegroundColor Yellow
                            $applications.winget_applications = $applications.winget_applications | Where-Object {
                                ($_.id -ne $appIdentifier) -and ($_.name -ne $appIdentifier)
                            }
                        }
                    }
                }
            }
        }

        # Install winget packages
        if ($applications.winget_applications) {
            $wingetToInstall = $applications.winget_applications | Where-Object {
                -not $_.skip_install -or $_.skip_install.ToString().ToLower() -ne 'yes'
            }
            if ($wingetToInstall.Count -gt 0) {
                Install-SelectedPackages -selectedPackages $wingetToInstall `
                                         -log_file $install_log_file `
                                         -uninstall_json_file $json_uninstall_file_path
            }
        }

        # Install external packages
        if ($applications.external_applications) {
            $externalToInstall = $applications.external_applications | Where-Object {
                -not $_.skip_install -or $_.skip_install.ToString().ToLower() -ne 'yes'
            }
            if ($externalToInstall.Count -gt 0) {
                Install-SelectedPackages -selectedPackages $externalToInstall `
                                         -log_file $install_log_file `
                                         -uninstall_json_file $json_uninstall_file_path
            }
        }

        # Copy logs to desktop
        $username = [Environment]::UserName
        Copy-Item -Path $install_log_file -Destination "C:\Users\$username\Desktop\install_logs.txt" -ErrorAction SilentlyContinue

        # Summary
        if (Test-Path -Path $json_uninstall_file_path) {
            Write-Host "Uninstall.json created successfully at: $json_uninstall_file_path" -ForegroundColor Green
            $uninstallData  = Get-Content -Path $json_uninstall_file_path -Raw | ConvertFrom-Json
            $wingetCount    = if ($uninstallData.winget_applications)   { $uninstallData.winget_applications.Count }   else { 0 }
            $externalCount  = if ($uninstallData.external_applications) { $uninstallData.external_applications.Count } else { 0 }
            Write-Host "Tracked for uninstall: $wingetCount winget apps, $externalCount external apps" -ForegroundColor Yellow
        } else {
            Write-Host "Warning: Uninstall.json was not created!" -ForegroundColor Red
        }

        # Clean up scheduled task (internal mode only)
        if (-not $ExternalMode) {
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
        # -- Uninstall mode -------------------------------------------------
        Write-Host "Running in mode: uninstall" -ForegroundColor Yellow

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
                    $uninstallDir = Split-Path -Path $json_uninstall_file_path -Parent
                    if (-not (Test-Path -Path $uninstallDir)) {
                        New-Item -Path $uninstallDir -ItemType Directory -Force | Out-Null
                    }
                    @{ winget_applications = @(); external_applications = @() } |
                        ConvertTo-Json -Depth 4 | Set-Content -Path $json_uninstall_file_path -Force
                    Write-Host "Created empty uninstall file at: $json_uninstall_file_path" -ForegroundColor Green
                }
                catch {
                    Write-Host "Failed to create uninstall file: $_" -ForegroundColor Red
                    exit 1
                }
            } else {
                Write-Host "Uninstall operation cancelled" -ForegroundColor Yellow
                exit 0
            }
        }

        Invoke-BatchUninstall -json_uninstall_file_path $json_uninstall_file_path `
                              -uninstall_log_file $uninstall_log_file

        Write-Host "Uninstallation process completed. Check $uninstall_log_file for details." -ForegroundColor Green
    }
    else {
        # -- Unknown / help -------------------------------------------------
        @"
Usage:
    .\Setup.ps1 gui         — Interactive GUI for package selection
    .\Setup.ps1 install     — Install all software from applications.json
    .\Setup.ps1 uninstall   — Uninstall tracked software from uninstall.json
"@ | Write-Host -ForegroundColor Red
    }
}
catch {
    Write-ToLog -message $_.Exception.Message -log_file $error_log_file
    Write-Host "$($_.Exception.Message)" -ForegroundColor Red
    Write-Host "An error occurred. See error log files for details." -ForegroundColor Red
}
