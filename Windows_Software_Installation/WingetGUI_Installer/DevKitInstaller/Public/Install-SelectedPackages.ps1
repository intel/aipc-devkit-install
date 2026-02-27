<#
.SYNOPSIS
    Installs a list of selected packages (winget and external).

.DESCRIPTION
    Iterates through selectedPackages, merges properties from the full
    applications JSON, then installs via winget or external installer.
    Tracks every successful install in the uninstall JSON.
#>

function Install-SelectedPackages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$selectedPackages,

        [Parameter(Mandatory=$true)]
        [string]$log_file,

        [Parameter(Mandatory=$true)]
        [string]$uninstall_json_file
    )

    $results        = @()
    $installedCount = 0
    $failedCount    = 0
    $skippedCount   = 0
    $failedPackages = @()

    # Reload the original JSON so we can merge in all properties (like override_flags)
    $jsonPath = (Get-DevKitConfig).JsonInstallFile
    $allWingetApps = @()
    if ($jsonPath -and (Test-Path $jsonPath)) {
        $allAppsJson   = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
        $allWingetApps = $allAppsJson.winget_applications
    }

    foreach ($app in $selectedPackages) {
        # Merge missing properties from the full JSON entry
        $fullApp = $null
        if ($app.PSObject.Properties["id"]) {
            $fullApp = $allWingetApps | Where-Object { $_.id -eq $app.id }
        } elseif ($app.PSObject.Properties["name"]) {
            $fullApp = $allWingetApps | Where-Object { $_.id -eq $app.name }
        }
        if ($fullApp) {
            foreach ($prop in $fullApp.PSObject.Properties) {
                if (-not $app.PSObject.Properties[$prop.Name]) {
                    $app | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
                }
            }
        }

        $appType = if ($app.PSObject.Properties["id"]) { "winget" } elseif ($app.PSObject.Properties["source"]) { "external" } else { "unknown" }
        $appName = if ($app.friendly_name) { $app.friendly_name } elseif ($app.name) { $app.name } elseif ($app.id) { $app.id } else { "UnknownApp" }

        # Resolve override flags (clean — no dead branches)
        $overrideFlags = $null
        if ($app.PSObject.Properties["override_flags"] -and $null -ne $app.override_flags) {
            $overrideFlags = $app.override_flags
        } elseif ($app.PSObject.Properties["OverrideFlags"] -and $null -ne $app.OverrideFlags) {
            $overrideFlags = $app.OverrideFlags
        }

        $result = @{ name = $appName; type = $appType; status = "skipped"; message = "" }

        if ($appType -eq "winget") {
            try {
                Write-ToLog -message "Installing winget app: $appName" -log_file $log_file
                $wingetArgs = @("install", "--id", $app.id, "--accept-source-agreements", "--accept-package-agreements", "-h")

                if ($overrideFlags) {
                    Write-ToLog -message ("override_flags for " + $appName + ": " + $overrideFlags) -log_file $log_file
                    $wingetArgs += "--override"
                    $wingetArgs += "`"$overrideFlags`""
                } elseif ($app.install_args) {
                    $wingetArgs += $app.install_args
                }

                $process   = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -PassThru -Wait -NoNewWindow
                $exit_code = $process.ExitCode
                $success   = Test-InstallationSuccess -exit_code $exit_code -app_name $appName -log_file $log_file

                if ($success) {
                    $installedCount++
                    $trackingApp = [PSCustomObject]@{
                        id            = if ($app.id) { $app.id } elseif ($app.name) { $app.name } else { $appName }
                        name          = if ($app.name) { $app.name } elseif ($app.id) { $app.id } else { $appName }
                        friendly_name = if ($app.friendly_name) { $app.friendly_name } else { $appName }
                        version       = if ($app.version) { $app.version } else { "Latest" }
                        installed_on  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                        last_updated  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    }
                    Append-ToJson -jsonFilePath $uninstall_json_file -section "winget_applications" -newObject $trackingApp
                    $result.status  = "success"
                    $result.message = "Installed and tracked."
                } else {
                    $failedCount++
                    $failedPackages += $appName
                    $result.status  = "failed"
                    $result.message = "Install failed."
                }
            }
            catch {
                $failedCount++
                $failedPackages += $appName
                Write-ToLog -message ("Exception during winget install for ${appName}: " + ($_ | Out-String)) -log_file $log_file
                $result.status  = "error"
                $result.message = $_.Exception.Message
            }
        }
        elseif ($appType -eq "external") {
            $success = Install-ExternalApplication -app $app -log_file $log_file -uninstall_json_file $uninstall_json_file
            if ($success) {
                $installedCount++
                $result.status  = "success"
                $result.message = "Installed and tracked."
            } else {
                $failedCount++
                $failedPackages += $appName
                $result.status  = "failed"
                $result.message = "Install failed."
            }
        }
        else {
            $skippedCount++
            $result.status  = "skipped"
            $result.message = "Unknown app type."
        }

        $results += $result
    }

    $summary = @{
        TotalPackages      = $selectedPackages.Count
        SuccessfulInstalls = $installedCount
        FailedInstalls     = $failedCount
        SkippedInstalls    = $skippedCount
        FailedPackages     = if ($failedPackages -and $failedPackages.Count -gt 0) { $failedPackages -join ", " } else { "None" }
    }

    Write-Host "Install Summary: Total: $($summary.TotalPackages), Installed: $($summary.SuccessfulInstalls), Failed: $($summary.FailedInstalls), Skipped: $($summary.SkippedInstalls), FailedPackages: $($summary.FailedPackages)" -ForegroundColor Green
    Write-ToLog -message "Install Summary: Total: $($summary.TotalPackages), Installed: $($summary.SuccessfulInstalls), Failed: $($summary.FailedInstalls), Skipped: $($summary.SkippedInstalls), FailedPackages: $($summary.FailedPackages)" -log_file $log_file

    return $summary
}
