<#
.SYNOPSIS
    Internal helpers for uninstallation operations.

.DESCRIPTION
    Contains Test-UninstallationSuccess, Uninstall-WingetApplication,
    and Uninstall-ExternalApplication.
#>

function Test-UninstallationSuccess {
    [CmdletBinding()]
    param(
        [int]$exit_code,
        [string]$app_name,
        [string]$log_file
    )

    switch ($exit_code) {
        0 {
            Write-ToLog -message "Successfully uninstalled $app_name" -log_file $log_file
            return $true
        }
        -1978335189 {
            Write-ToLog -message "Application $app_name is not installed" -log_file $log_file
            return $true
        }
        -1978335188 {
            Write-ToLog -message "No applicable uninstaller found for $app_name" -log_file $log_file
            return $true
        }
        -1978335186 {
            Write-ToLog -message "Uninstallation of $app_name was blocked by policy" -log_file $log_file
            return $false
        }
        -1978335185 {
            Write-ToLog -message "No packages found to uninstall for $app_name" -log_file $log_file
            return $true
        }
        3010 {
            Write-ToLog -message "Successfully uninstalled $app_name (reboot required)" -log_file $log_file
            return $true
        }
        1641 {
            Write-ToLog -message "Successfully uninstalled $app_name (initiated reboot)" -log_file $log_file
            return $true
        }
        default {
            Write-ToLog -message "Uninstallation of $app_name completed with exit code: $exit_code" -log_file $log_file
            return $exit_code -eq 0
        }
    }
}

function Uninstall-WingetApplication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$app,

        [Parameter(Mandatory=$true)]
        [string]$log_file
    )

    if (-not $app -or (-not $app.id -and -not $app.name)) {
        Write-ToLog -message "Error: Invalid application object provided to Uninstall-WingetApplication. Must have id or name property." -log_file $log_file
        return $false
    }

    $appIdentifier  = if ($app.id) { $app.id } else { $app.name }
    $appDisplayName = if ($app.friendly_name) { $app.friendly_name } else { $appIdentifier }

    Write-ToLog -message "Uninstalling application: $appDisplayName $(if ($app.version) { "version $($app.version)" } else { "(any version)" })" -log_file $log_file

    $arguments = @(
        "uninstall",
        "--purge",
        "--accept-source-agreements",
        "--silent",
        "--disable-interactivity",
        "--force"
    )

    $arguments += @("--id", $appIdentifier)

    if ($app.version -and $app.version -ne "Latest" -and $app.version -ne "" -and $null -ne $app.version) {
        $arguments += @("-v", $app.version)
    }

    if ($app.uninstall_override_flags) {
        $arguments += @("--override", $app.uninstall_override_flags)
        Write-ToLog -message "Using custom uninstall override flags for ${appDisplayName}: $($app.uninstall_override_flags)" -log_file $log_file
    }

    Write-ToLog -message "Uninstalling $appDisplayName" -log_file $log_file

    # Suppress UI elements
    $env:WINGET_DISABLE_INTERACTIVITY   = "1"
    $env:WINGET_DISABLE_UPGRADE_PROMPTS = "1"
    $env:WINGET_DISABLE_CONFIRMATION    = "1"
    $env:SILENT = "1"
    $env:QUIET  = "1"

    $commandStr = "winget $($arguments -join ' ')"
    Write-ToLog -message "Executing command: $commandStr" -log_file $log_file

    try {
        $process   = Start-Process -FilePath winget -ArgumentList $arguments -PassThru -Wait -NoNewWindow
        $exit_code = $process.ExitCode
        return Test-UninstallationSuccess -exit_code $exit_code -app_name $appDisplayName -log_file $log_file
    }
    catch {
        Write-ToLog -message "Error during uninstallation of ${appDisplayName}: $_" -log_file $log_file
        return $false
    }
}

function Uninstall-ExternalApplication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$app,

        [Parameter(Mandatory=$true)]
        [string]$log_file
    )

    $appDisplayName = if ($app.friendly_name) { $app.friendly_name } else { $app.name }

    if (-not $app -or -not $app.name) {
        Write-ToLog -message "Error: Invalid application object for external application" -log_file $log_file
        return $false
    }

    if (-not $app.uninstall_command) {
        Write-ToLog -message "Warning: No uninstall command provided for $appDisplayName. Considering it already uninstalled." -log_file $log_file
        return $true
    }

    Write-ToLog -message "Uninstalling external application: $appDisplayName" -log_file $log_file
    Write-ToLog -message "Using command: $($app.uninstall_command)" -log_file $log_file

    $regex = '([a-zA-Z]:.*.exe)(.*)'
    if ($app.uninstall_command -match $regex) {
        $command = $matches[1]
        $arguments_unsplit = $matches[2]

        if (-not (Test-Path -Path $command)) {
            Write-ToLog -message "Warning: Uninstall executable not found at: $command for $appDisplayName. Considering it already uninstalled." -log_file $log_file
            return $true
        }

        $arguments_split = @()
        if (-not [string]::IsNullOrWhiteSpace($arguments_unsplit)) {
            $arguments_split = $arguments_unsplit -split ' (?=(?:[^\\"]*\\"[^\\"]*\\")*[^\\"]*$)' |
                               Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                               ForEach-Object { $_.Trim('\\"') }
        }

        Write-ToLog -message "Parsed command: $command" -log_file $log_file
        Write-ToLog -message "Parsed arguments: $($arguments_split -join ', ')" -log_file $log_file

        try {
            $process   = Start-Process -FilePath $command -ArgumentList $arguments_split -PassThru -Wait -NoNewWindow
            $exit_code = $process.ExitCode
            Write-ToLog -message "Uninstalled $appDisplayName with exit code $exit_code" -log_file $log_file

            $successExitCodes = @(0, 3010, 1641)
            if ($successExitCodes -contains $exit_code) {
                Write-ToLog -message "Uninstallation of $appDisplayName successful with expected exit code $exit_code" -log_file $log_file
                return $true
            } else {
                Write-ToLog -message "Uninstallation of $appDisplayName may have failed with exit code $exit_code" -log_file $log_file
                return $true  # Return true to remove from tracking — external exit codes are unreliable
            }
        }
        catch {
            Write-ToLog -message "Error during uninstallation of external application ${appDisplayName}: $_" -log_file $log_file
            return $false
        }
    }
    else {
        Write-ToLog -message "Invalid uninstall command format for ${appDisplayName}: $($app.uninstall_command)" -log_file $log_file
        return $false
    }
}
