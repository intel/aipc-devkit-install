<#
.SYNOPSIS
    Internal helpers for installation operations.

.DESCRIPTION
    Contains Test-InstallationSuccess (winget exit code mapping) and
    Install-ExternalApplication (download + run external installer).
#>

function Test-InstallationSuccess {
    [CmdletBinding()]
    param(
        [int]$exit_code,
        [string]$app_name,
        [string]$log_file
    )

    switch ($exit_code) {
        0 {
            Write-ToLog -message "Successfully installed $app_name" -log_file $log_file
            return $true
        }
        -1978335189 {
            Write-ToLog -message "Application $app_name is already installed" -log_file $log_file
            return $true
        }
        -1978335188 {
            Write-ToLog -message "No applicable installer found for $app_name" -log_file $log_file
            return $false
        }
        -1978335186 {
            Write-ToLog -message "Installation of $app_name was blocked by policy" -log_file $log_file
            return $false
        }
        -1978335210 {
            Write-ToLog -message "Package $app_name not found in the source" -log_file $log_file
            return $false
        }
        -1978335212 {
            Write-ToLog -message "Package $app_name is already installed (alternative code)" -log_file $log_file
            return $true
        }
        -1978335181 {
            Write-ToLog -message "Application $app_name completed successfully but a reboot is required" -log_file $log_file
            return $true
        }
        -1978335182 {
            Write-ToLog -message "Application $app_name installation completed with restart required" -log_file $log_file
            return $true
        }
        87 {
            Write-ToLog -message "Application $app_name completed with exit code 87 (parameter incorrect) - likely already installed" -log_file $log_file
            return $true
        }
        3010 {
            Write-ToLog -message "Application $app_name successfully installed (reboot required)" -log_file $log_file
            return $true
        }
        1 {
            Write-ToLog -message "Application $app_name completed with exit code 1 (success with warnings or already installed)" -log_file $log_file
            return $true
        }
        default {
            Write-ToLog -message "Failed to install $app_name. Exit code: $exit_code" -log_file $log_file
            return $false
        }
    }
}

function Install-ExternalApplication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$app,

        [Parameter(Mandatory=$true)]
        [string]$log_file,

        [Parameter(Mandatory=$true)]
        [string]$uninstall_json_file
    )

    $appDisplayName = if ($app.friendly_name) { $app.friendly_name } else { $app.name }

    Write-ToLog -message "Installing external application $appDisplayName" -log_file $log_file

    if (-not $app.name -or -not $app.source) {
        Write-ToLog -message "Error: External application $appDisplayName is missing required properties (name or source)" -log_file $log_file
        return $false
    }

    $temp_dir = Join-Path $env:TEMP "EnvSetup_Downloads"
    if (-not (Test-Path $temp_dir)) {
        New-Item -ItemType Directory -Path $temp_dir -Force | Out-Null
    }

    try {
        $installer_path = Join-Path $temp_dir "$($app.name)_installer$(Split-Path $app.source -Extension)"
        try {
            Write-ToLog -message "Downloading $appDisplayName from $($app.source)" -log_file $log_file
            Invoke-WebRequest -Uri $app.source -OutFile $installer_path -UseBasicParsing
            Write-ToLog -message "Downloaded installer for $appDisplayName to $installer_path" -log_file $log_file
        }
        catch {
            Write-ToLog -message "Failed to download installer for $appDisplayName`: $_" -log_file $log_file
            return $false
        }

        $arguments = @()
        if ($app.install_flags) {
            $arguments = $app.install_flags -split '\s+'
        } elseif ($app.install_args) {
            $arguments = $app.install_args -split '\s+'
        }

        Write-ToLog -message "Running installer for $appDisplayName with arguments: $($arguments -join ' ')" -log_file $log_file
        $process = Start-Process -FilePath $installer_path -ArgumentList $arguments -PassThru -Wait -NoNewWindow
        $exit_code = $process.ExitCode

        $success = ($exit_code -eq 0)
        Write-ToLog -message "Installation of $appDisplayName completed with exit code $exit_code" -log_file $log_file

        if ($success -or $exit_code -eq 1603) {
            $trackingApp = [PSCustomObject]@{
                name            = if ($app.name) { $app.name } else { $appDisplayName }
                friendly_name   = if ($app.friendly_name) { $app.friendly_name } else { $appDisplayName }
                version         = if ($app.version) { $app.version } else { "Latest" }
                uninstall_command = if ($app.PSObject.Properties.Name -contains "uninstall_command" -and $app.uninstall_command) { $app.uninstall_command } else { "" }
                installed_on    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                last_updated    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
            if ($exit_code -eq 1603) {
                $trackingApp | Add-Member -MemberType NoteProperty -Name "installation_status" -Value "already_installed"
                Write-ToLog -message "$appDisplayName appears to be already installed. Adding to tracking file anyway." -log_file $log_file
                $success = $true
            }
            if (-not [string]::IsNullOrWhiteSpace($uninstall_json_file)) {
                $retryCount = 0
                $maxRetries = 3
                $success_append = $false
                while ($retryCount -lt $maxRetries -and -not $success_append) {
                    try {
                        if ($retryCount -gt 0) {
                            Start-Sleep -Milliseconds (100 * $retryCount)
                        }
                        Append-ToJson -jsonFilePath $uninstall_json_file -section "external_applications" -newObject $trackingApp
                        $success_append = $true
                        Write-ToLog -message "Added/updated $appDisplayName in tracking file for uninstallation" -log_file $log_file
                    }
                    catch {
                        $retryCount++
                        Write-ToLog -message "Retry $retryCount/$maxRetries`: Failed to update tracking file for $appDisplayName`: $_" -log_file $log_file
                        if ($retryCount -eq $maxRetries) {
                            Write-ToLog -message "Failed to add $appDisplayName to tracking file after $maxRetries attempts" -log_file $log_file
                        }
                    }
                }
            }
        }

        return $success
    }
    catch {
        Write-ToLog -message "Error during installation of $appDisplayName`: $_" -log_file $log_file
        return $false
    }
}
