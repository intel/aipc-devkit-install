# This script is designed to set up a development environment on Windows using winget.
# It installs or updates a list of applications, including Visual Studio, Python, and others.
# It also sets the execution policy to Unrestricted to allow script execution.
# **********************************************#
# IMPORTANT: This script must be run from an elevated PowerShell prompt.
# Usage:
# Set-ExecutionPolicy -ExecutionPolicy Unrestricted LocalMachine
# ./Env_Setup.ps1 install -> Installs software (command line mode)
# ./Env_Setup.ps1 gui -> Shows GUI for interactive package selection and installation/uninstallation
# ./Env_Setup.ps1 uninstall -> Uninstalls software
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
    .\Env_Setup.ps1 gui
    Launches the graphical interface for interactive software selection.
    
.EXAMPLE
    .\Env_Setup.ps1 install
    Installs all software defined in the applications.json file.
    
.EXAMPLE
    .\Env_Setup.ps1 uninstall
    Uninstalls previously installed software tracked in uninstall.json.

.NOTES
    Requires Administrator privileges to run.
    Authors: 
    - Vijay (vijay.chandrashekar@intel.com)
    - Ram (vaithi.s.ramadoss@intel.com)
    - Ben (benjamin.j.odom@intel.com)
#>
param(
    [string]$command # Accepts a command parameter: install, gui, or uninstall
)
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
    Write-Host "Disk space available on $($drive): $freeSpaceGB GB" -ForegroundColor Magenta
    if ($freeSpaceGB -lt $minGB) {
        Write-Host "ERROR: At least $minGB GB of free disk space is required. Only $freeSpaceGB GB available." -ForegroundColor Red
        exit 1
    } else {
        Write-Host "You have adequate disk space to continue installation." -ForegroundColor Green
    }
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
            
            $argumentList = if ($commandToRun) { "-ExecutionPolicy Bypass -File `"$scriptPath`" $commandToRun" } else { "-ExecutionPolicy Bypass -File `"$scriptPath`"" }
            Start-Process -FilePath "powershell.exe" -ArgumentList $argumentList -Verb RunAs
        }
        
        # Exit current instance
        exit
    }
}

Set-Location -Path $PSScriptRoot # Sets the current directory to the script's location
$logs_dir = ".\logs" # Directory for storing log files
$json_dir = ".\json" # Directory for storing JSON files

# Source helper scripts
. ".\Public\Write_ToLog.ps1" # Sources a script for logging messages
. ".\Public\Append-ToJson.ps1" # Sources a script for appending data to JSON files
. ".\Public\Pre_Req.ps1" # Sources a script for checking pre-requisites

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

<#
    Checks if winget installation was successful based on exit code
#>
function Test-InstallationSuccess {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)]
        [int]$exitCode
    )
    # Winget exit codes: 
    # 0 = success
    # -1978335212 = already installed (APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED)
    # -1978335209 = version not found (APPINSTALLER_CLI_ERROR_NO_APPLICABLE_INSTALLER)
    # -1978335210 = package not found (APPINSTALLER_CLI_ERROR_PACKAGE_NOT_FOUND)
    # Other negative codes = various failures
    
    switch ($exitCode) {
        0 { return $true }                    # Success
        -1978335212 { return $true }          # Already installed - consider success
        -1978335209 { return $false }         # Version not found - failure
        -1978335210 { return $false }         # Package not found - failure
        default { 
            if ($exitCode -eq 0) { return $true }
            else { return $false }            # Any other non-zero code is failure
        }
    }
}

<#
    Checks if winget uninstallation was successful based on exit code
#>
function Test-UninstallationSuccess {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)]
        [int]$exitCode
    )
    # Winget uninstall exit codes:
    # 0 = successfully uninstalled
    # 1 = package not found (could mean already uninstalled or never installed)
    # -1978335210 = package not found (APPINSTALLER_CLI_ERROR_PACKAGE_NOT_FOUND)
    # -1978335212 = package already processed/not in installed list (APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED)
    
    switch ($exitCode) {
        0 { return $true }                    # Successfully uninstalled
        1 { return $true }                    # Package not found (already uninstalled/never installed - goal achieved)
        -1978335210 { return $true }          # Package not found (already uninstalled/never installed - goal achieved)
        -1978335212 { return $true }          # Package not in installed list (already uninstalled - goal achieved)
        default { return $false }             # Any other exit code indicates failure
    }
}

<#
    GUI Functions for interactive package selection
#>
function Show-MainGUI {
    param(
        [Parameter(Mandatory)]
        $applications,
        [string]$install_log_file,
        [string]$json_uninstall_file_path
    )
    
    # Load UI types
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    # Create the main form
    $mainForm = New-Object System.Windows.Forms.Form
    $mainForm.Text = 'Environment Setup - Main Menu'
    $mainForm.Size = New-Object System.Drawing.Size(500, 300)
    $mainForm.StartPosition = 'CenterScreen'
    $mainForm.FormBorderStyle = 'FixedDialog'
    $mainForm.MaximizeBox = $false
    
    # Title label
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = 'Environment Setup Tool'
    $lblTitle.Font = New-Object System.Drawing.Font('Arial', 16, [System.Drawing.FontStyle]::Bold)
    $lblTitle.Size = New-Object System.Drawing.Size(400, 30)
    $lblTitle.Location = New-Object System.Drawing.Point(50, 30)
    $lblTitle.TextAlign = 'MiddleCenter'
    
    # Description label
    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text = 'Choose an action to perform:'
    $lblDesc.Size = New-Object System.Drawing.Size(400, 20)
    $lblDesc.Location = New-Object System.Drawing.Point(50, 80)
    $lblDesc.TextAlign = 'MiddleCenter'
    
    # Install button
    $btnInstall = New-Object System.Windows.Forms.Button
    $btnInstall.Text = 'Install Software'
    $btnInstall.Size = New-Object System.Drawing.Size(150, 40)
    $btnInstall.Location = New-Object System.Drawing.Point(80, 120)
    $btnInstall.Font = New-Object System.Drawing.Font('Arial', 10)
    
    # Uninstall button
    $btnUninstall = New-Object System.Windows.Forms.Button
    $btnUninstall.Text = 'Uninstall Software'
    $btnUninstall.Size = New-Object System.Drawing.Size(150, 40)
    $btnUninstall.Location = New-Object System.Drawing.Point(270, 120)
    $btnUninstall.Font = New-Object System.Drawing.Font('Arial', 10)
    
    # Exit button
    $btnExit = New-Object System.Windows.Forms.Button
    $btnExit.Text = 'Exit'
    $btnExit.Size = New-Object System.Drawing.Size(100, 30)
    $btnExit.Location = New-Object System.Drawing.Point(200, 200)
    
    # Add controls to form
    $mainForm.Controls.AddRange(@($lblTitle, $lblDesc, $btnInstall, $btnUninstall, $btnExit))
    
    # Button event handlers
    $btnInstall.Add_Click({
        $mainForm.Hide()
        $selectedPackages = Show-PackageSelectionGUI -applications $applications -install_log_file $install_log_file
        
        if ($selectedPackages) {
            Write-Host "Installing selected packages..." -ForegroundColor Green
            $installResults = Install-SelectedPackages -selectedPackages $selectedPackages -applications $applications -install_log_file $install_log_file -json_uninstall_file_path $json_uninstall_file_path
            
            # Copy install logs to desktop
            $username = [Environment]::UserName
            Copy-Item -Path $install_log_file -Destination "C:\Users\$username\Desktop\install_logs.txt"
            
            Show-InstallResults -installResults $installResults
        }
        $mainForm.Close()
    })
    
    $btnUninstall.Add_Click({
        $mainForm.Hide()
        $selectedPackages = Show-UninstallGUI -json_uninstall_file_path $json_uninstall_file_path
        
        if ($selectedPackages) {
            Write-Host "Uninstalling selected packages..." -ForegroundColor Yellow
            $uninstallResults = Uninstall-SelectedPackages -selectedPackages $selectedPackages -json_uninstall_file_path $json_uninstall_file_path
            Show-UninstallResults -uninstallResults $uninstallResults
        }
        $mainForm.Close()
    })
    
    $btnExit.Add_Click({ $mainForm.Close() })
    
    # Show the form
    [void] $mainForm.ShowDialog()
}

function Show-InstallResults {
    param($installResults)
    
    # Create detailed result message
    $resultMessage = "Installation Summary:`n"
    $resultMessage += "Total packages: $($installResults.TotalPackages)`n"
    $resultMessage += "Successfully installed: $($installResults.SuccessfulInstalls)`n"
    $resultMessage += "Failed installations: $($installResults.FailedInstalls)`n"
    
    if ($installResults.FailedInstalls -gt 0) {
        $resultMessage += "`nFailed packages:`n"
        foreach ($failedPkg in $installResults.FailedPackages) {
            $resultMessage += "- $failedPkg`n"
        }
    }
    
    $resultMessage += "`nCheck the install logs on your desktop for details."
    
    # Choose appropriate icon and title based on results
    if ($installResults.FailedInstalls -eq 0) {
        $icon = [System.Windows.Forms.MessageBoxIcon]::Information
        $title = 'Environment Setup - Installation Completed Successfully'
    } elseif ($installResults.SuccessfulInstalls -eq 0) {
        $icon = [System.Windows.Forms.MessageBoxIcon]::Error
        $title = 'Environment Setup - Installation Failed'
    } else {
        $icon = [System.Windows.Forms.MessageBoxIcon]::Warning
        $title = 'Environment Setup - Installation Completed with Errors'
    }
    
    [System.Windows.Forms.MessageBox]::Show(
        $resultMessage,
        $title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $icon
    )
}

function Show-PackageSelectionGUI {
    param(
        [Parameter(Mandatory)]
        $applications,
        [string]$install_log_file
    )
    
    # Load UI types
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    # Build a DataTable for the DataGridView
    $dt = New-Object System.Data.DataTable
    $dt.Columns.Add('Check', [bool]) | Out-Null
    $dt.Columns.Add('Id', [string]) | Out-Null
    $dt.Columns.Add('FriendlyName', [string]) | Out-Null
    $dt.Columns.Add('Summary', [string]) | Out-Null
    $dt.Columns.Add('Version', [string]) | Out-Null
    $dt.Columns.Add('Type', [string]) | Out-Null
    
    # Add winget applications
    foreach ($app in $applications.winget_applications) {
        if ($null -eq $app) { continue }
        
        $row = $dt.NewRow()
        $row.Check = $false
        $row.Id = if ($null -ne $app.id -and $app.id -ne '') { $app.id } else { $app.name }
        $row.FriendlyName = if ($null -ne $app.friendly_name -and $app.friendly_name -ne '') { $app.friendly_name } else { $app.name }
        $row.Summary = if ($null -ne $app.summary -and $app.summary -ne '') { $app.summary } else { "No description available" }
        $row.Version = if ($null -ne $app.version -and $app.version -ne '') { $app.version } else { "Latest" }
        $row.Type = "Winget"
        $dt.Rows.Add($row)
    }
    
    # Add external applications
    foreach ($app in $applications.external_applications) {
        if ($null -eq $app) { continue }
        
        $row = $dt.NewRow()
        $row.Check = $false
        $row.Id = $app.name
        $row.FriendlyName = if ($null -ne $app.friendly_name -and $app.friendly_name -ne '') { $app.friendly_name } else { $app.name }
        $row.Summary = if ($null -ne $app.summary -and $app.summary -ne '') { $app.summary } else { "External application" }
        $row.Version = "External"
        $row.Type = "External"
        $dt.Rows.Add($row)
    }
    
    # Create the form
    $frm = New-Object System.Windows.Forms.Form
    $frm.Text = 'Environment Setup - Select Software to Install'
    $frm.Size = New-Object System.Drawing.Size(1000, 600)
    $frm.StartPosition = 'CenterScreen'
    $frm.FormBorderStyle = 'Sizable'
    
    # DataGridView
    $dg = New-Object System.Windows.Forms.DataGridView
    $dg.AutoGenerateColumns = $true
    $dg.DataSource = $dt
    $dg.Dock = 'Fill'
    $dg.AutoSizeColumnsMode = 'AllCells'
    $dg.AllowUserToAddRows = $false
    $dg.AllowUserToDeleteRows = $false
    $dg.SelectionMode = 'FullRowSelect'
    
    # Configure columns
    $dg.Refresh()
    if ($dg.Columns.Count -gt 0) {
        $dg.Columns[0].HeaderText = 'Install?'
        $dg.Columns[0].Width = 70
        
        if ($dg.Columns.Count -gt 1) { 
            $dg.Columns[1].HeaderText = 'Package ID'
            $dg.Columns[1].ReadOnly = $true
            $dg.Columns[1].Width = 200
        }
        if ($dg.Columns.Count -gt 2) { 
            $dg.Columns[2].HeaderText = 'Name'
            $dg.Columns[2].ReadOnly = $true
            $dg.Columns[2].Width = 200
        }
        if ($dg.Columns.Count -gt 3) { 
            $dg.Columns[3].HeaderText = 'Description'
            $dg.Columns[3].ReadOnly = $true
            $dg.Columns[3].Width = 300
        }
        if ($dg.Columns.Count -gt 4) { 
            $dg.Columns[4].HeaderText = 'Version'
            $dg.Columns[4].ReadOnly = $true
            $dg.Columns[4].Width = 100
        }
        if ($dg.Columns.Count -gt 5) { 
            $dg.Columns[5].HeaderText = 'Type'
            $dg.Columns[5].ReadOnly = $true
            $dg.Columns[5].Width = 80
        }
    }
    
    # Bottom panel with buttons
    $pan = New-Object System.Windows.Forms.Panel
    $pan.Dock = 'Bottom'
    $pan.Height = 50
    
    $btnSelectAll = New-Object System.Windows.Forms.Button
    $btnSelectAll.Text = 'Select All'
    $btnSelectAll.Width = 80
    $btnSelectAll.Location = New-Object System.Drawing.Point(10, 10)
    
    $btnClearAll = New-Object System.Windows.Forms.Button
    $btnClearAll.Text = 'Clear All'
    $btnClearAll.Width = 80
    $btnClearAll.Location = New-Object System.Drawing.Point(100, 10)
    
    $btnInstall = New-Object System.Windows.Forms.Button
    $btnInstall.Text = 'Install Selected'
    $btnInstall.Width = 120
    $btnInstall.Location = New-Object System.Drawing.Point(190, 10)
    
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Close'
    $btnCancel.Width = 80
    $btnCancel.Location = New-Object System.Drawing.Point(320, 10)
    
    $pan.Controls.AddRange(@($btnSelectAll, $btnClearAll, $btnInstall, $btnCancel))
    $frm.Controls.AddRange(@($dg, $pan))
    
    # Button event handlers
    $btnSelectAll.Add_Click({
        foreach ($row in $dt.Rows) {
            $row.Check = $true
        }
    })
    
    $btnClearAll.Add_Click({
        foreach ($row in $dt.Rows) {
            $row.Check = $false
        }
    })
    
    $btnInstall.Add_Click({
        $selectedRows = $dt | Where-Object { $_.Check }
        
        if (-not $selectedRows) {
            [System.Windows.Forms.MessageBox]::Show(
                'No packages selected.',
                'Environment Setup',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            return
        }
        
        $cnt = $selectedRows.Count
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "You are about to install $cnt package(s). Continue?",
            'Environment Setup - Confirm Installation',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        
        if ($confirm -ne 'Yes') { return }
        
        # Close the form and return selected packages
        $script:selectedPackages = $selectedRows
        $frm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $frm.Close()
    })
    
    $btnCancel.Add_Click({ $frm.Close() })
    
    # Show the form
    $result = $frm.ShowDialog()
    
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $script:selectedPackages
    }
    
    return $null
}

function Show-UninstallGUI {
    param(
        [string]$json_uninstall_file_path
    )
    
    # Check if uninstall.json exists
    if (-not (Test-Path -Path $json_uninstall_file_path)) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "No uninstall.json file found. No applications have been tracked for uninstallation.",
            'Environment Setup - No Applications to Uninstall',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return $null
    }
    
    # Load uninstall data
    $uninstallData = Get-Content -Path $json_uninstall_file_path -Raw | ConvertFrom-Json
    
    # Check if there are any applications to uninstall
    $totalApps = 0
    if ($uninstallData.winget_applications -and $uninstallData.winget_applications.Count) { 
        $totalApps += $uninstallData.winget_applications.Count 
    }
    if ($uninstallData.external_applications -and $uninstallData.external_applications.Count) { 
        $totalApps += $uninstallData.external_applications.Count 
    }
    
    if ($totalApps -eq 0) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "No applications are currently tracked for uninstallation.",
            'Environment Setup - No Applications to Uninstall',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return $null
    }
    
    # Load UI types
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    # Build a DataTable for the DataGridView
    $dt = New-Object System.Data.DataTable
    $dt.Columns.Add('Check', [bool]) | Out-Null
    $dt.Columns.Add('Id', [string]) | Out-Null
    $dt.Columns.Add('FriendlyName', [string]) | Out-Null
    $dt.Columns.Add('Version', [string]) | Out-Null
    $dt.Columns.Add('Type', [string]) | Out-Null
    
    # Add winget applications from uninstall.json
    if ($uninstallData.winget_applications -and $uninstallData.winget_applications.Count -gt 0) {
        foreach ($app in $uninstallData.winget_applications) {
            $row = $dt.NewRow()
            $row.Check = $false
            $row.Id = $app.name
            $row.FriendlyName = $app.name  # Use name as friendly name for installed apps
            $row.Version = if ($app.version) { $app.version } else { "Latest" }
            $row.Type = "Winget"
            $dt.Rows.Add($row)
        }
    }
    
    # Add external applications from uninstall.json
    if ($uninstallData.external_applications -and $uninstallData.external_applications.Count -gt 0) {
        foreach ($app in $uninstallData.external_applications) {
            $row = $dt.NewRow()
            $row.Check = $false
            $row.Id = $app.name
            $row.FriendlyName = $app.name
            $row.Version = "External"
            $row.Type = "External"
            $dt.Rows.Add($row)
        }
    }
    
    # Create the form
    $frm = New-Object System.Windows.Forms.Form
    $frm.Text = 'Environment Setup - Select Software to Uninstall'
    $frm.Size = New-Object System.Drawing.Size(900, 500)
    $frm.StartPosition = 'CenterScreen'
    $frm.FormBorderStyle = 'Sizable'
    
    # DataGridView
    $dg = New-Object System.Windows.Forms.DataGridView
    $dg.AutoGenerateColumns = $true
    $dg.DataSource = $dt
    $dg.Dock = 'Fill'
    $dg.AutoSizeColumnsMode = 'AllCells'
    $dg.AllowUserToAddRows = $false
    $dg.AllowUserToDeleteRows = $false
    $dg.SelectionMode = 'FullRowSelect'
    
    # Configure columns
    $dg.Refresh()
    if ($dg.Columns.Count -gt 0) {
        $dg.Columns[0].HeaderText = 'Uninstall?'
        $dg.Columns[0].Width = 70
        
        if ($dg.Columns.Count -gt 1) { 
            $dg.Columns[1].HeaderText = 'Package ID'
            $dg.Columns[1].ReadOnly = $true
            $dg.Columns[1].Width = 200
        }
        if ($dg.Columns.Count -gt 2) { 
            $dg.Columns[2].HeaderText = 'Name'
            $dg.Columns[2].ReadOnly = $true
            $dg.Columns[2].Width = 200
        }
        if ($dg.Columns.Count -gt 3) { 
            $dg.Columns[3].HeaderText = 'Version'
            $dg.Columns[3].ReadOnly = $true
            $dg.Columns[3].Width = 100
        }
        if ($dg.Columns.Count -gt 4) { 
            $dg.Columns[4].HeaderText = 'Type'
            $dg.Columns[4].ReadOnly = $true
            $dg.Columns[4].Width = 80
        }
    }
    
    # Bottom panel with buttons
    $pan = New-Object System.Windows.Forms.Panel
    $pan.Dock = 'Bottom'
    $pan.Height = 50
    
    $btnSelectAll = New-Object System.Windows.Forms.Button
    $btnSelectAll.Text = 'Select All'
    $btnSelectAll.Width = 80
    $btnSelectAll.Location = New-Object System.Drawing.Point(10, 10)
    
    $btnClearAll = New-Object System.Windows.Forms.Button
    $btnClearAll.Text = 'Clear All'
    $btnClearAll.Width = 80
    $btnClearAll.Location = New-Object System.Drawing.Point(100, 10)
    
    $btnUninstall = New-Object System.Windows.Forms.Button
    $btnUninstall.Text = 'Uninstall Selected'
    $btnUninstall.Width = 120
    $btnUninstall.Location = New-Object System.Drawing.Point(190, 10)
    
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Cancel'
    $btnCancel.Width = 80
    $btnCancel.Location = New-Object System.Drawing.Point(320, 10)
    
    $pan.Controls.AddRange(@($btnSelectAll, $btnClearAll, $btnUninstall, $btnCancel))
    $frm.Controls.AddRange(@($dg, $pan))
    
    # Button event handlers
    $btnSelectAll.Add_Click({
        foreach ($row in $dt.Rows) {
            $row.Check = $true
        }
    })
    
    $btnClearAll.Add_Click({
        foreach ($row in $dt.Rows) {
            $row.Check = $false
        }
    })
    
    $btnUninstall.Add_Click({
        $selectedRows = $dt | Where-Object { $_.Check }
        
        if (-not $selectedRows) {
            [System.Windows.Forms.MessageBox]::Show(
                'No packages selected.',
                'Environment Setup',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            return
        }
        
        $cnt = $selectedRows.Count
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "You are about to uninstall $cnt package(s). This action cannot be undone. Continue?",
            'Environment Setup - Confirm Uninstallation',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        
        if ($confirm -ne 'Yes') { return }
        
        # Close the form and return selected packages
        $script:selectedUninstallPackages = $selectedRows
        $frm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $frm.Close()
    })
    
    $btnCancel.Add_Click({ $frm.Close() })
    
    # Show the form
    $result = $frm.ShowDialog()
    
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $script:selectedUninstallPackages
    }
    
    return $null
}

function Uninstall-SelectedPackages {
    param(
        [Parameter(Mandatory)]
        $selectedPackages,
        [string]$json_uninstall_file_path
    )
    
    $uninstallResults = @{
        TotalPackages = $selectedPackages.Count
        SuccessfulUninstalls = 0
        FailedUninstalls = 0
        FailedPackages = @()
    }
    
    # Load the uninstall data
    $uninstallData = Get-Content -Path $json_uninstall_file_path -Raw | ConvertFrom-Json
    
    foreach ($selectedPkg in $selectedPackages) {
        if ($selectedPkg.Type -eq "Winget") {
            # Find the winget application in uninstall.json
            $app = $uninstallData.winget_applications | Where-Object { $_.name -eq $selectedPkg.Id }
            
            if ($app) {
                $success = Uninstall-WingetApplication -app $app
                if ($success) {
                    $uninstallResults.SuccessfulUninstalls++
                    # Remove from uninstall.json
                    $uninstallData.winget_applications = $uninstallData.winget_applications | Where-Object { $_.name -ne $selectedPkg.Id }
                } else {
                    $uninstallResults.FailedUninstalls++
                    $uninstallResults.FailedPackages += $selectedPkg.FriendlyName
                }
            }
        }
        elseif ($selectedPkg.Type -eq "External") {
            # Find the external application in uninstall.json
            $app = $uninstallData.external_applications | Where-Object { $_.name -eq $selectedPkg.Id }
            
            if ($app) {
                $success = Uninstall-ExternalApplication -app $app
                if ($success) {
                    $uninstallResults.SuccessfulUninstalls++
                    # Remove from uninstall.json
                    $uninstallData.external_applications = $uninstallData.external_applications | Where-Object { $_.name -ne $selectedPkg.Id }
                } else {
                    $uninstallResults.FailedUninstalls++
                    $uninstallResults.FailedPackages += $selectedPkg.FriendlyName
                }
            }
        }
    }
    
    # Update the uninstall.json file
    # Ensure arrays are never null
    if (-not $uninstallData.winget_applications) {
        $uninstallData.winget_applications = @()
    }
    if (-not $uninstallData.external_applications) {
        $uninstallData.external_applications = @()
    }
    
    $uninstallData | ConvertTo-Json -Depth 10 | Set-Content -Path $json_uninstall_file_path
    
    return $uninstallResults
}

function Uninstall-WingetApplication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$app
    )
    
    # Construct arguments for winget uninstallation
    $arguments = @(
        "uninstall", 
        "--purge", 
        "--accept-source-agreements", 
        "--silent", 
        "--disable-interactivity",
        "--force"
    )
    
    if ($app.name) {
        $arguments += @("--id", $app.name)
    }
    if ($app.version) {
        $arguments += @("-v", $app.version)
    }
    
    Write-Host "Uninstalling $($app.name)..." -ForegroundColor Yellow
    
    $process = Start-Process -FilePath winget -ArgumentList $arguments -PassThru -Wait -NoNewWindow
    $process.WaitForExit() 
    $exit_code = $process.ExitCode
    
    if (Test-UninstallationSuccess -exitCode $exit_code) {
        if ($exit_code -eq 0) {
            Write-Host "Successfully uninstalled: $($app.name)" -ForegroundColor Green
        } else {
            Write-Host "Package $($app.name) was already uninstalled or not found (goal achieved)" -ForegroundColor Green
        }
        return $true
    } else {
        Write-Host "Failed to uninstall $($app.name) (exit code: $exit_code)" -ForegroundColor Red
        return $false
    }
}

function Uninstall-ExternalApplication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$app
    )
    
    if ($app.uninstall_command) {
        $regex = "([a-zA-Z]:.*.exe)(.*)"
        if ($app.uninstall_command -match $regex) {
            $command = $matches[1]
            $arguments_unsplit = $matches[2]
            $arguments_split = $arguments_unsplit -split '\s+' | Where-Object { $_ -ne "" }

            Write-Host "Uninstalling $($app.name)..." -ForegroundColor Yellow
            $process = Start-Process -FilePath $command -ArgumentList $arguments_split -PassThru -Wait -NoNewWindow
            $process.WaitForExit()
            $exit_code = $process.ExitCode
            
            if ($exit_code -eq 0) {
                Write-Host "Successfully uninstalled: $($app.name)" -ForegroundColor Green
                return $true
            } else {
                Write-Host "Failed to uninstall $($app.name) (exit code: $exit_code)" -ForegroundColor Red
                return $false
            }
        }
    }
    
    Write-Host "No uninstall command available for $($app.name)" -ForegroundColor Yellow
    return $false
}

function Show-UninstallResults {
    param($uninstallResults)
    
    # Create detailed result message
    $resultMessage = "Uninstallation Summary:`n"
    $resultMessage += "Total packages: $($uninstallResults.TotalPackages)`n"
    $resultMessage += "Successfully uninstalled: $($uninstallResults.SuccessfulUninstalls)`n"
    $resultMessage += "Failed uninstallations: $($uninstallResults.FailedUninstalls)`n"
    
    if ($uninstallResults.FailedUninstalls -gt 0) {
        $resultMessage += "`nFailed packages:`n"
        foreach ($failedPkg in $uninstallResults.FailedPackages) {
            $resultMessage += "- $failedPkg`n"
        }
    }
    
    # Choose appropriate icon and title based on results
    if ($uninstallResults.FailedUninstalls -eq 0) {
        $icon = [System.Windows.Forms.MessageBoxIcon]::Information
        $title = 'Environment Setup - Uninstallation Completed Successfully'
    } elseif ($uninstallResults.SuccessfulUninstalls -eq 0) {
        $icon = [System.Windows.Forms.MessageBoxIcon]::Error
        $title = 'Environment Setup - Uninstallation Failed'
    } else {
        $icon = [System.Windows.Forms.MessageBoxIcon]::Warning
        $title = 'Environment Setup - Uninstallation Completed with Errors'
    }
    
    [System.Windows.Forms.MessageBox]::Show(
        $resultMessage,
        $title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $icon
    )
}

function Install-SelectedPackages {
    param(
        [Parameter(Mandatory)]
        $selectedPackages,
        [Parameter(Mandatory)]
        $applications,
        [string]$install_log_file,
        [string]$json_uninstall_file_path
    )
    
    $installationResults = @{
        TotalPackages = $selectedPackages.Count
        SuccessfulInstalls = 0
        FailedInstalls = 0
        FailedPackages = @()
    }
    
    foreach ($selectedPkg in $selectedPackages) {
        if ($selectedPkg.Type -eq "Winget") {
            # Find the full application object
            $app = $applications.winget_applications | Where-Object { 
                ($_.id -eq $selectedPkg.Id) -or ($_.name -eq $selectedPkg.Id)
            }
            
            if ($app) {
                $result = Install-WingetApplication -app $app -applications $applications -install_log_file $install_log_file -json_uninstall_file_path $json_uninstall_file_path
                if ($result) {
                    $installationResults.SuccessfulInstalls++
                } else {
                    $installationResults.FailedInstalls++
                    $installationResults.FailedPackages += $selectedPkg.FriendlyName
                }
            }
        }
        elseif ($selectedPkg.Type -eq "External") {
            # Find the external application object
            $app = $applications.external_applications | Where-Object { $_.name -eq $selectedPkg.Id }
            
            if ($app) {
                $result = Install-ExternalApplication -app $app -install_log_file $install_log_file -json_uninstall_file_path $json_uninstall_file_path
                if ($result) {
                    $installationResults.SuccessfulInstalls++
                } else {
                    $installationResults.FailedInstalls++
                    $installationResults.FailedPackages += $selectedPkg.FriendlyName
                }
            }
        }
    }
    
    return $installationResults
}

function Install-WingetApplication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$app,
        
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$applications,
        
        [Parameter(Mandatory=$true)]
        [string]$install_log_file,
        
        [Parameter(Mandatory=$true)]
        [string]$json_uninstall_file_path
    )
    
    $app_id = if ($app.id) { $app.id } else { $app.name }
    $global_install_flags = $applications.global_install_flags

    # Construct arguments for winget installation
    $arguments = @("install")
    $arguments += @("$global_install_flags")
    if ($app_id) {
        $arguments += @("--id $app_id")
    }
    if ($app.version) {
        $arguments += @("-v $($app.version)")
    }
    if ($app.install_location) {
        $arguments += @("-l $($app.install_location)")
    }
    if ($app.override_flags) {
        $arguments += @("--override `"$($app.override_flags)`"")
    }

    Write-ToLog -message "Installing $app_id" -log_file $install_log_file
    Write-Host "Installing $app_id..." -ForegroundColor Yellow
    
    $process = Start-Process -FilePath winget -ArgumentList $arguments -NoNewWindow -PassThru -Wait
    $process.WaitForExit()
    $exit_code = $process.ExitCode
    Write-ToLog -message "$app_id finished installing with exit code: $exit_code" -log_file $install_log_file

    # Only add to uninstall list if installation was successful
    if (Test-InstallationSuccess -exitCode $exit_code) {
        # Add to installed list and append immediately for real-time tracking
        $appData = @{
            name    = $app_id
            version = $app.version
        }
        
        # Include uninstall override flags if they exist
        if ($app.uninstall_override_flags) {
            $appData.uninstall_override_flags = $app.uninstall_override_flags
        }
        
        $data = @{
            winget_applications   = @($appData)
            external_applications = @()
        }

        AppendToJson -json_location $json_uninstall_file_path -data $data
        Write-ToLog -message "$app_id successfully installed and added to uninstall list" -log_file $install_log_file
        Write-Host "Successfully installed: $app_id" -ForegroundColor Green
        return $true
    } else {
        Write-ToLog -message "$app_id installation failed with exit code $exit_code - not added to uninstall list" -log_file $install_log_file
        Write-Host "Failed to install $app_id (exit code: $exit_code)" -ForegroundColor Red
        return $false
    }
}

function Install-ExternalApplication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$app,
        
        [Parameter(Mandatory=$true)]
        [string]$install_log_file,
        
        [Parameter(Mandatory=$true)]
        [string]$json_uninstall_file_path
    )
    
    $file_name = $app.name + ".exe"
        
    if (-not (Test-Path -Path $app.download_location)) {
        New-Item -Path $app.download_location -ItemType Directory # Creates the download directory if it doesn't exist
    }

    $arguments = @("-L", $app.source, "-o", "$($app.download_location)\$file_name") # Constructs arguments for downloading external applications
       
    Write-ToLog -message "Installing $($app.name)" -log_file $install_log_file
    Write-Host "Downloading $($app.name)..." -ForegroundColor Yellow
    
    $process = Start-Process -FilePath "curl.exe" -ArgumentList "$arguments" -PassThru -NoNewWindow -Wait
    $process.WaitForExit()

    $arguments = @("$($app.install_flags)") # Constructs arguments for installing external applications
    $exec_path = "$($app.download_location)\$file_name"
    
    Write-Host "Installing $($app.name)..." -ForegroundColor Yellow
    $process = Start-Process -FilePath $exec_path -ArgumentList $arguments -PassThru -Wait -NoNewWindow
    $process.WaitForExit()
    $exit_code = $process.ExitCode

    Write-ToLog -message "Finished installing $($app.name) with exit code $exit_code" -log_file $install_log_file

    # Only add to uninstall list if installation was successful (exit code 0)
    if ($exit_code -eq 0) {
        # Add to installed list and append immediately for real-time tracking
        $data = @{
            winget_applications   = @()
            external_applications = @(@{
                name              = $app.name
                download_location = $app.download_location
                uninstall_command = $app.uninstall_command
            })
        }

        AppendToJson -json_location $json_uninstall_file_path -data $data
        Write-ToLog -message "$($app.name) successfully installed and added to uninstall list" -log_file $install_log_file
        Write-Host "Successfully installed: $($app.name)" -ForegroundColor Green
        return $true
    } else {
        Write-ToLog -message "$($app.name) installation failed with exit code $exit_code - not added to uninstall list" -log_file $install_log_file
        Write-Host "Failed to install $($app.name) (exit code: $exit_code)" -ForegroundColor Red
        return $false
    }
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

        # Setup uninstall json file
        Initialize-Directory $json_uninstall_dir


        # Check for pre-requsites
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

        $applications = Get-Content -Path $json_install_file_path -Raw | ConvertFrom-Json # Reads and parses the JSON file

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

        Write-Host "Additional external applications" -ForegroundColor Yellow
        foreach ($app in $applications.external_applications) {
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

        $winget_list = Get-WinGetPackage # Retrieves the list of installed winget packages


        # Initialize lists to track installed applications
        $data = @{
            winget_applications   = @() # List to track installed winget applications
            external_applications = @() # List to track installed external applications
        }

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

        # Download each winget application, skipping those with skip_install = 'yes'
        foreach ($app in $applications.winget_applications) {
            if ($null -eq $app) { continue }
            
            if ($app.skip_install -eq 'yes') {
                Write-Host "Skipping $($app.friendly_name) ($($app.id)) due to skip_install flag." -ForegroundColor Yellow
                continue
            }
            $app_id = if ($app.id) { $app.id } else { $app.name }
            $global_install_flags = $applications.global_install_flags

            # Construct arguments for winget installation
            $arguments = @("install")
            $arguments += @("$global_install_flags")
            if ($app_id) {
                $arguments += @("--id $app_id")
            }
            if ($app.version) {
                $arguments += @("-v $($app.version)")
            }
            if ($app.install_location) {
                $arguments += @("-l $($app.install_location)")
            }
            if ($app.override_flags) {
                $arguments += @("--override `"$($app.override_flags)`"")
            }

            Write-ToLog -message "Installing $app_id" -log_file $install_log_file
            $process = Start-Process -FilePath winget -ArgumentList $arguments -NoNewWindow -PassThru -Wait
            $process.WaitForExit()
            $exit_code = $process.ExitCode
            Write-ToLog -message "$app_id finished installing with exit code: $exit_code" -log_file $install_log_file

            # Only add to uninstall list if installation was successful
            if (Test-InstallationSuccess -exitCode $exit_code) {
                # Add to installed list and append immediately for real-time tracking
                $appData = @{
                    name    = $app_id
                    version = $app.version
                }
                
                # Include uninstall override flags if they exist
                if ($app.uninstall_override_flags) {
                    $appData.uninstall_override_flags = $app.uninstall_override_flags
                }
                
                $data.winget_applications = @($appData)
                $data.external_applications = @()

                AppendToJson -json_location $json_uninstall_file_path -data $data
                Write-ToLog -message "$app_id successfully installed and added to uninstall list" -log_file $install_log_file
                Write-Host "Successfully installed and tracked: $app_id" -ForegroundColor Green
                Write-Host "Uninstall JSON location: $json_uninstall_file_path" -ForegroundColor Cyan
            } else {
                Write-ToLog -message "$app_id installation failed with exit code $exit_code - not added to uninstall list" -log_file $install_log_file
                Write-Host "Failed to install $app_id (exit code: $exit_code)" -ForegroundColor Red
            }
        }

        # Download external apps, skipping those with skip_install = 'yes'
        foreach ($app in $applications.external_applications) {
            if ($null -eq $app) { continue }
            
            if ($app.skip_install -eq 'yes') {
                Write-Host "Skipping $($app.friendly_name) ($($app.name)) due to skip_install flag." -ForegroundColor Yellow
                continue
            }
            $file_name = $app.name + ".exe"
                
            if (-not (Test-Path -Path $app.download_location)) {
                New-Item -Path $app.download_location -ItemType Directory # Creates the download directory if it doesn't exist
            }

            $arguments = @("-L", $app.source, "-o", "$($app.download_location)\$file_name") # Constructs arguments for downloading external applications
               
            Write-ToLog -message "Installing $($app.name)" -log_file $install_log_file
            $process = Start-Process -FilePath "curl.exe" -ArgumentList "$arguments" -PassThru -NoNewWindow -Wait
            $process.WaitForExit()

            $arguments = @("$($app.install_flags)") # Constructs arguments for installing external applications
            $exec_path = "$($app.download_location)\$file_name"
            $process = Start-Process -FilePath $exec_path -ArgumentList $arguments -PassThru -Wait -NoNewWindow
            $process.WaitForExit()
            $exit_code = $process.ExitCode

            Write-ToLog -message "Finished installing $($app.name) with exit code $exit_code" -log_file $install_log_file

            # Only add to uninstall list if installation was successful (exit code 0)
            if ($exit_code -eq 0) {
                # Add to installed list and append immediately for real-time tracking
                $data.winget_applications = @()
                $data.external_applications = @(@{
                    name              = $app.name
                    download_location = $app.download_location
                    uninstall_command = $app.uninstall_command
                })

                AppendToJson -json_location $json_uninstall_file_path -data $data
                Write-ToLog -message "$($app.name) successfully installed and added to uninstall list" -log_file $install_log_file
            } else {
                Write-ToLog -message "$($app.name) installation failed with exit code $exit_code - not added to uninstall list" -log_file $install_log_file
                Write-Host "Failed to install $($app.name) (exit code: $exit_code)" -ForegroundColor Red
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
        if (-not (Test-Path -Path $json_uninstall_file_path)) {
            Write-Host "No Uninstall file specified. Please run installer first" -ForegroundColor Red
            exit # Exits if the uninstall JSON file does not exist
        }

        # Setup uninstall logs
        Initialize-Directory $uninstall_logs_dir
        New-File $uninstall_log_file

        $applications = Get-Content -Path $json_uninstall_file_path -Raw | ConvertFrom-Json # Reads and parses the uninstall JSON file

        foreach ($app in $applications.winget_applications) {
            # Construct arguments for winget uninstallation with comprehensive silent flags
            $arguments = @(
                "uninstall", 
                "--purge", 
                "--accept-source-agreements", 
                "--silent", 
                "--disable-interactivity",
                "--force"  # Force uninstall without confirmation dialogs
                
            )
            if ($app.name) {
                $arguments += @("--id", $app.name)
            }
            if ($app.version) {
                $arguments += @("-v", $app.version)
            }
            
            # Add uninstall override flags if they exist for this application
            if ($app.uninstall_override_flags) {
                $arguments += @("--override", $app.uninstall_override_flags)
                Write-ToLog -message "Using custom uninstall override flags for $($app.name): $($app.uninstall_override_flags)" -log_file $uninstall_log_file
            }

            Write-ToLog -message "Uninstalling $($app.name)" -log_file $uninstall_log_file
            
            # Set comprehensive environment variables to suppress ALL UI elements
            $env:WINGET_DISABLE_INTERACTIVITY = "1"
            $env:WINGET_DISABLE_UPGRADE_PROMPTS = "1"
            $env:WINGET_DISABLE_CONFIRMATION = "1"
            $env:SILENT = "1"
            $env:QUIET = "1"
            
            $process = Start-Process -FilePath winget -ArgumentList $arguments -PassThru -Wait -NoNewWindow
            $process.WaitForExit() 
            $exit_code = $process.ExitCode
            Write-ToLog -message "Finished uninstalling $($app.name) with exit code $exit_code" -log_file $uninstall_log_file
        }

        foreach ($app in $applications.external_applications) {
            $regex = "([a-zA-Z]:.*.exe)(.*)" # Regex to match the uninstall command
            if ($app.uninstall_command -match $regex) {
                $command = $matches[1]
                $arguments_unsplit = $matches[2]
                $arguments_split = $arguments_unsplit -split '\s+' | Where-Object { $_ -ne "" } # Splits the arguments for the uninstall command

                Write-ToLog -message "Uninstalling $($app.name)" -log_file $uninstall_log_file
                $process = Start-Process -FilePath $command -ArgumentList $arguments_split -PassThru -Wait -NoNewWindow
                $process.WaitForExit()
                $exit_code = $process.ExitCode
                Write-ToLog -message "Uninstalled $($app.name) with exit code $exit_code" -log_file $uninstall_log_file
            }
        }

        # Remove JSON uninstall folder
        Remove-Item -Path $json_uninstall_dir -Recurse # Deletes the uninstall JSON directory
    }
    else {
        $help_str = 
        @"
            Usage:
                - gui
                    Shows a Windows Forms interface for interactive package selection and installation/uninstallation
                - install
                    Installs all software specified in applications.json, checking for dependencies
                - uninstall
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
