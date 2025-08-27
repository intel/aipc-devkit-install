<#
.SYNOPSIS
    GUI module for the Environment Setup Tool.

.DESCRIPTION
    This module provides GUI functions for the Environment Setup Tool,
    including package selection, installation, and uninstallation interfaces.

.NOTES
    This is part of the Environment Setup tool for developers.
    Authors: 
    - Vijay (vijay.chandrashekar@intel.com)
    - Ram (vaithi.s.ramadoss@intel.com)
    - Ben (benjamin.j.odom@intel.com)
#>

# Load required .NET assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

<#
    Displays the main GUI for the Environment Setup Tool.
#>
function Show-MainGUI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $applications,
        [string]$install_log_file,
        [string]$json_uninstall_file_path
    )
    
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
            
            # Create uninstall_json_file if it doesn't exist
            if (-not [string]::IsNullOrWhiteSpace($json_uninstall_file_path)) {
                $uninstallDir = Split-Path -Path $json_uninstall_file_path -Parent
                if (-not (Test-Path -Path $uninstallDir)) {
                    New-Item -Path $uninstallDir -ItemType Directory -Force | Out-Null
                }
                
                if (-not (Test-Path -Path $json_uninstall_file_path)) {
                    $json_structure = @{
                        "winget_applications" = @()
                        "external_applications" = @()
                    }
                    $json_structure | ConvertTo-Json | Set-Content -Path $json_uninstall_file_path
                }
            }
            
            $installResults = Install-SelectedPackages -selectedPackages $selectedPackages -log_file $install_log_file -uninstall_json_file $json_uninstall_file_path
            
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
            $uninstallResults = Uninstall-SelectedPackages -selectedPackages $selectedPackages -log_file $install_log_file -json_uninstall_file_path $json_uninstall_file_path
            Show-UninstallResults -uninstallResults $uninstallResults
        }
        $mainForm.Close()
    })
    
    $btnExit.Add_Click({ $mainForm.Close() })
    
    # Show the form
    [void] $mainForm.ShowDialog()
}

<#
    Displays the installation results summary.
#>
function Show-InstallResults {
    [CmdletBinding()]
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

<#
    Displays a GUI for selecting packages to install.
#>
function Show-PackageSelectionGUI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $applications,
        [string]$install_log_file
    )
    
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
        # Check if skip_install is defined and not set to "yes"
        $row.Check = if ($null -ne $app.skip_install) { $app.skip_install -ne "yes" } else { $true }
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
        # Check if skip_install is defined and not set to "yes"
        $row.Check = if ($null -ne $app.skip_install) { $app.skip_install -ne "yes" } else { $true }
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
        
        $cnt = @($selectedRows).Count
        $pkgWord = if ($cnt -eq 1) { 'package' } else { 'packages' }
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "You are about to install $cnt $pkgWord. Continue?",
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

<#
    Displays a GUI for selecting packages to uninstall.
#>
function Show-UninstallGUI {
    [CmdletBinding()]
    param(
        [string]$json_uninstall_file_path
    )
    
    # Check if uninstall.json exists
    if (-not (Test-Path -Path $json_uninstall_file_path)) {
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
        [System.Windows.Forms.MessageBox]::Show(
            "No applications are currently tracked for uninstallation.",
            'Environment Setup - No Applications to Uninstall',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return $null
    }
    
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
            # For winget apps, use 'id' field (e.g., "Microsoft.VisualStudioCode")
            $row.Id = if ($app.id) { $app.id } else { $app.name }
            # Use friendly_name if available, otherwise fall back to id or name
            $row.FriendlyName = if ($app.friendly_name) { $app.friendly_name } elseif ($app.id) { $app.id } else { $app.name }
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
            # For external apps, use 'name' field
            $row.Id = $app.name
            # Use friendly_name if available, otherwise fall back to name
            $row.FriendlyName = if ($app.friendly_name) { $app.friendly_name } else { $app.name }
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

<#
    Displays a summary of uninstallation results.
#>
function Show-UninstallResults {
    [CmdletBinding()]
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

# Functions are automatically available when the script is sourced
# No need to export members since this is not a module
