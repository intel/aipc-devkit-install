<#
.SYNOPSIS
    Uninstallation functions for GUI and batch modes.

.DESCRIPTION
    Uninstall-SelectedPackages  — used by the GUI to uninstall user-selected packages.
    Invoke-BatchUninstall       — used by the CLI 'uninstall' command.
#>

function Uninstall-SelectedPackages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$selectedPackages,

        [Parameter(Mandatory=$true)]
        [string]$log_file,

        [Parameter(Mandatory=$true)]
        [string]$json_uninstall_file_path
    )

    $results = @{
        TotalPackages        = $selectedPackages.Count
        SuccessfulUninstalls = 0
        FailedUninstalls     = 0
        FailedPackages       = @()
    }

    foreach ($package in $selectedPackages) {
        if ($package.Type -eq "Winget") {
            $app = [PSCustomObject]@{
                id            = $package.Id
                friendly_name = $package.FriendlyName
                version       = if ($package.Version -eq "Latest") { $null } else { $package.Version }
            }
            $section = "winget_applications"
            $id      = $package.Id
        } else {
            $app = [PSCustomObject]@{
                name          = $package.Id
                friendly_name = $package.FriendlyName
                version       = if ($package.Version -eq "Latest") { $null } else { $package.Version }
            }
            $section = "external_applications"
            $id      = $package.Id
        }

        # For external apps, look up full details (including uninstall_command)
        if ($package.Type -eq "External") {
            $uninstallJson = Get-Content -Path $json_uninstall_file_path -Raw | ConvertFrom-Json
            $originalApp   = $uninstallJson.external_applications | Where-Object { $_.name -eq $app.name } | Select-Object -First 1
            if ($originalApp) { $app = $originalApp }
        }

        try {
            if ($app.PSObject.Properties.Name -contains "uninstall_command") {
                $success = Uninstall-ExternalApplication -app $app -log_file $log_file
            } else {
                $success = Uninstall-WingetApplication -app $app -log_file $log_file
            }

            if ($success) {
                $results.SuccessfulUninstalls++
                Remove-FromJsonById -jsonFilePath $json_uninstall_file_path -section $section -id $id
            } else {
                $results.FailedUninstalls++
                $appName = if ($app.friendly_name) { $app.friendly_name } else { if ($app.id) { $app.id } else { $app.name } }
                $results.FailedPackages += $appName
            }
        }
        catch {
            $appIdentifier = if ($app.id) { $app.id } else { $app.name }
            Write-ToLog -message "Error uninstalling $appIdentifier`: $_" -log_file $log_file
            $results.FailedUninstalls++
            $appName = if ($app.friendly_name) { $app.friendly_name } else { $appIdentifier }
            $results.FailedPackages += $appName
        }
    }

    return $results
}

function Invoke-BatchUninstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$json_uninstall_file_path,

        [Parameter(Mandatory=$true)]
        [string]$uninstall_log_file
    )

    Write-Host "Starting batch uninstallation process..." -ForegroundColor Cyan
    Write-ToLog -message "Starting batch uninstallation from $json_uninstall_file_path" -log_file $uninstall_log_file

    if (-not (Test-Path -Path $json_uninstall_file_path)) {
        $errorMsg = "Uninstall JSON file not found at: $json_uninstall_file_path"
        Write-Host $errorMsg -ForegroundColor Red
        Write-ToLog -message $errorMsg -log_file $uninstall_log_file
        return
    }

    try {
        $applications = Get-Content -Path $json_uninstall_file_path -Raw | ConvertFrom-Json
        Write-Host "Successfully loaded uninstall data" -ForegroundColor Green
    }
    catch {
        $errorMsg = "Error reading uninstall JSON file: $_"
        Write-Host $errorMsg -ForegroundColor Red
        Write-ToLog -message $errorMsg -log_file $uninstall_log_file
        return
    }

    $successfulWingetUninstalls   = 0
    $failedWingetUninstalls       = 0
    $successfulExternalUninstalls = 0
    $failedExternalUninstalls     = 0

    # NOTE: Remove-FromJsonById is always available via the module — no need to dot-source

    # Uninstall winget applications
    if ($applications.winget_applications -and $applications.winget_applications.Count -gt 0) {
        Write-Host "Uninstalling $($applications.winget_applications.Count) winget applications..." -ForegroundColor Cyan
        Write-ToLog -message "Uninstalling $($applications.winget_applications.Count) winget applications" -log_file $uninstall_log_file

        foreach ($app in $applications.winget_applications) {
            $appName = if ($app.friendly_name) { $app.friendly_name } else { if ($app.id) { $app.id } else { $app.name } }
            Write-Host "Uninstalling winget application: $appName" -ForegroundColor Cyan

            $success = Uninstall-WingetApplication -app $app -log_file $uninstall_log_file
            if ($success) {
                $successfulWingetUninstalls++
                Remove-FromJsonById -jsonFilePath $json_uninstall_file_path -section "winget_applications" -id $app.id
                Write-Host "Successfully uninstalled and removed from tracking: $appName" -ForegroundColor Green
            } else {
                $failedWingetUninstalls++
                Write-Host "Failed to uninstall: $appName" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "No winget applications found to uninstall" -ForegroundColor Yellow
        Write-ToLog -message "No winget applications found to uninstall" -log_file $uninstall_log_file
    }

    # Uninstall external applications
    if ($applications.external_applications -and $applications.external_applications.Count -gt 0) {
        Write-Host "Uninstalling $($applications.external_applications.Count) external applications..." -ForegroundColor Cyan
        Write-ToLog -message "Uninstalling $($applications.external_applications.Count) external applications" -log_file $uninstall_log_file

        foreach ($app in $applications.external_applications) {
            $appName = if ($app.friendly_name) { $app.friendly_name } else { $app.name }
            Write-Host "Uninstalling external application: $appName" -ForegroundColor Cyan

            $success = Uninstall-ExternalApplication -app $app -log_file $uninstall_log_file
            if ($success) {
                $successfulExternalUninstalls++
                Remove-FromJsonById -jsonFilePath $json_uninstall_file_path -section "external_applications" -id $app.name
                Write-Host "Successfully uninstalled and removed from tracking: $appName" -ForegroundColor Green
            } else {
                $failedExternalUninstalls++
                Write-Host "Failed to uninstall: $appName" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "No external applications found to uninstall" -ForegroundColor Yellow
        Write-ToLog -message "No external applications found to uninstall" -log_file $uninstall_log_file
    }

    # Rewrite tracking file if it still exists (some uninstalls may have failed)
    if (Test-Path $json_uninstall_file_path) {
        try {
            $applications = Get-Content -Path $json_uninstall_file_path -Raw | ConvertFrom-Json
            $applications | ConvertTo-Json -Depth 4 | Set-Content -Path $json_uninstall_file_path -Force
            Write-Host "Updated uninstall tracking file" -ForegroundColor Green
            Write-ToLog -message "Updated uninstall tracking file" -log_file $uninstall_log_file
        }
        catch {
            Write-Host "Error updating uninstall tracking file: $_" -ForegroundColor Red
            Write-ToLog -message "Error updating uninstall tracking file: $_" -log_file $uninstall_log_file
        }
    } else {
        Write-Host "Uninstall tracking file removed (all apps uninstalled)." -ForegroundColor Green
        Write-ToLog -message "Uninstall tracking file removed (all apps uninstalled)." -log_file $uninstall_log_file
    }

    # Summary
    Write-Host "`nUninstallation Summary:" -ForegroundColor Yellow
    Write-Host "--------------------" -ForegroundColor Yellow
    Write-Host "Winget Applications: $successfulWingetUninstalls successful, $failedWingetUninstalls failed" -ForegroundColor White
    Write-Host "External Applications: $successfulExternalUninstalls successful, $failedExternalUninstalls failed" -ForegroundColor White
    Write-Host "Total: $($successfulWingetUninstalls + $successfulExternalUninstalls) successful, $($failedWingetUninstalls + $failedExternalUninstalls) failed" -ForegroundColor White

    Write-ToLog -message "Uninstallation Summary: $successfulWingetUninstalls winget apps successful, $failedWingetUninstalls failed" -log_file $uninstall_log_file
    Write-ToLog -message "Uninstallation Summary: $successfulExternalUninstalls external apps successful, $failedExternalUninstalls failed" -log_file $uninstall_log_file
}
