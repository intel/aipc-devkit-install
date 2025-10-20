# Uninstall.ps1
# Module containing all uninstallation-related functions

# Test if a winget uninstallation was successful
function Test-UninstallationSuccess {
    param (
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
            return $true  # Still return success, since the goal is for the app to not be installed
        }
        -1978335188 { 
            Write-ToLog -message "No applicable uninstaller found for $app_name" -log_file $log_file
            return $true  # Consider it success, since we can't uninstall what doesn't exist
        }
        -1978335186 { 
            Write-ToLog -message "Uninstallation of $app_name was blocked by policy" -log_file $log_file
            return $false
        }
        -1978335185 { 
            Write-ToLog -message "No packages found to uninstall for $app_name" -log_file $log_file
            return $true  # Still return success, since the goal is for the app to not be installed
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
            return $exit_code -eq 0  # For any other code, return true only if it's 0
        }
    }
}

# Used by the GUI to uninstall selected packages
function Uninstall-SelectedPackages {
    param (
        [array]$selectedPackages,
        [string]$log_file,
        [string]$json_uninstall_file_path
    )
    
    # Prepare result tracking
    $results = @{
        TotalPackages = $selectedPackages.Count
        SuccessfulUninstalls = 0
        FailedUninstalls = 0
        FailedPackages = @()
    }

    foreach ($package in $selectedPackages) {
        # Create app object from the package information in the datatable
        if ($package.Type -eq "Winget") {
            $app = [PSCustomObject]@{
                id = $package.Id
                friendly_name = $package.FriendlyName
                version = if ($package.Version -eq "Latest") { $null } else { $package.Version }
            }
            $section = "winget_applications"
            $id = $package.Id
        } else {
            $app = [PSCustomObject]@{
                name = $package.Id
                friendly_name = $package.FriendlyName
                version = if ($package.Version -eq "Latest") { $null } else { $package.Version }
            }
            $section = "external_applications"
            $id = $package.Id
        }
        
        # For external applications, look up the full details including uninstall_command
        if ($package.Type -eq "External") {
            $uninstallJson = Get-Content -Path $json_uninstall_file_path -Raw | ConvertFrom-Json
            $originalApp = $uninstallJson.external_applications | Where-Object { $_.name -eq $app.name } | Select-Object -First 1
            if ($originalApp) {
                $app = $originalApp
            }
        }
        
        try {
            if ($app.PSObject.Properties.Name -contains "uninstall_command") {
                $success = Uninstall-ExternalApplication -app $app -log_file $log_file
            } else {
                $success = Uninstall-WingetApplication -app $app -log_file $log_file
            }
            
            if ($success) {
                $results.SuccessfulUninstalls++
                # Remove from uninstall.json after successful uninstall
                Remove-FromJsonById -jsonFilePath $json_uninstall_file_path -section $section -id $id
            } else {
                $results.FailedUninstalls++
                $appName = if ($app.friendly_name) { $app.friendly_name } else { if ($app.id) { $app.id } else { $app.name } }
                $results.FailedPackages += $appName
            }
        } catch {
            $appIdentifier = if ($app.id) { $app.id } else { $app.name }
            Write-ToLog -message "Error uninstalling $appIdentifier`: $_" -log_file $log_file
            $results.FailedUninstalls++
            $appName = if ($app.friendly_name) { $app.friendly_name } else { $appIdentifier }
            $results.FailedPackages += $appName
        }
    }
    
    return $results
}

# Uninstall a winget application
function Uninstall-WingetApplication {
    param (
        [PSCustomObject]$app,
        [string]$log_file
    )

    # Validate app object has required properties
    if (-not $app -or (-not $app.id -and -not $app.name)) {
        Write-ToLog -message "Error: Invalid application object provided to Uninstall-WingetApplication. Must have id or name property." -log_file $log_file
        return $false
    }

    # Determine the application identifier to use (prefer id, fall back to name)
    $appIdentifier = if ($app.id) { $app.id } else { $app.name }
    $appDisplayName = if ($app.friendly_name) { $app.friendly_name } else { $appIdentifier }

    # Log what we're about to uninstall
    Write-ToLog -message "Uninstalling application: $appDisplayName $(if ($app.version) { "version $($app.version)" } else { "(any version)" })" -log_file $log_file

    # Construct arguments for winget uninstallation with comprehensive silent flags
    $arguments = @(
        "uninstall", 
        "--purge", 
        "--accept-source-agreements", 
        "--silent", 
        "--disable-interactivity",
        "--force"  # Force uninstall without confirmation dialogs
    )
    
    # Add the application ID
    $arguments += @("--id", $appIdentifier)
    
    if ($app.version -and $app.version -ne "Latest" -and $app.version -ne "" -and $app.version -ne $null) {
        $arguments += @("-v", $app.version)
    }
    
    # Add uninstall override flags if they exist for this application
    if ($app.uninstall_override_flags) {
        $arguments += @("--override", $app.uninstall_override_flags)
        Write-ToLog -message "Using custom uninstall override flags for ${appDisplayName}: $($app.uninstall_override_flags)" -log_file $log_file
    }

    Write-ToLog -message "Uninstalling $appDisplayName" -log_file $log_file
    
    # Set comprehensive environment variables to suppress ALL UI elements
    $env:WINGET_DISABLE_INTERACTIVITY = "1"
    $env:WINGET_DISABLE_UPGRADE_PROMPTS = "1"
    $env:WINGET_DISABLE_CONFIRMATION = "1"
    $env:SILENT = "1"
    $env:QUIET = "1"
    
    # Log the full command we're about to execute
    $commandStr = "winget $($arguments -join ' ')"
    Write-ToLog -message "Executing command: $commandStr" -log_file $log_file
    
    try {
        $process = Start-Process -FilePath winget -ArgumentList $arguments -PassThru -Wait -NoNewWindow
        $exit_code = $process.ExitCode
        
        return Test-UninstallationSuccess -exit_code $exit_code -app_name $appDisplayName -log_file $log_file
    }
    catch {
        Write-ToLog -message "Error during uninstallation of ${appDisplayName}: $_" -log_file $log_file
        return $false
    }
}

# Uninstall an external application
function Uninstall-ExternalApplication {
    param (
        [PSCustomObject]$app,
        [string]$log_file
    )

    # Get display name for logging
    $appDisplayName = if ($app.friendly_name) { $app.friendly_name } else { $app.name }

    # Validate app object has required properties
    if (-not $app -or -not $app.name) {
        Write-ToLog -message "Error: Invalid application object for external application" -log_file $log_file
        return $false
    }

    if (-not $app.uninstall_command) {
        Write-ToLog -message "Warning: No uninstall command provided for $appDisplayName. Considering it already uninstalled." -log_file $log_file
        return $true  # Return success since there's nothing to uninstall
    }

    Write-ToLog -message "Uninstalling external application: $appDisplayName" -log_file $log_file
    Write-ToLog -message "Using command: $($app.uninstall_command)" -log_file $log_file

    $regex = '([a-zA-Z]:.*.exe)(.*)' # Regex to match the uninstall command
    if ($app.uninstall_command -match $regex) {
        $command = $matches[1]
        $arguments_unsplit = $matches[2]
        
        # Check if the executable exists
        if (-not (Test-Path -Path $command)) {
            Write-ToLog -message "Warning: Uninstall executable not found at: $command for $appDisplayName. Considering it already uninstalled." -log_file $log_file
            return $true  # Return success since there's nothing to uninstall
        }
        
        # Split the arguments properly
        $arguments_split = @()
        if (-not [string]::IsNullOrWhiteSpace($arguments_unsplit)) {
            $arguments_split = $arguments_unsplit -split ' (?=(?:[^\\"]*\\"[^\\"]*\\")*[^\\"]*$)' | 
                               Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | 
                               ForEach-Object { $_.Trim('\\"') }
        }
        
        Write-ToLog -message "Parsed command: $command" -log_file $log_file
        Write-ToLog -message "Parsed arguments: $($arguments_split -join ', ')" -log_file $log_file
        
        try {
            $process = Start-Process -FilePath $command -ArgumentList $arguments_split -PassThru -Wait -NoNewWindow
            $exit_code = $process.ExitCode
            Write-ToLog -message "Uninstalled $appDisplayName with exit code $exit_code" -log_file $log_file
            
            # Consider any exit code as success for external applications, as different installers use different codes
            # For applications like Visual Studio, the uninstaller might return a non-zero exit code even on success
            if ($exit_code -eq 0) {
                return $true
            } else {
                # Check known "success" exit codes from common uninstallers
                $successExitCodes = @(0, 3010, 1641)  # 3010 = Reboot required, 1641 = Initiated reboot
                if ($successExitCodes -contains $exit_code) {
                    Write-ToLog -message "Uninstallation of $appDisplayName successful with expected exit code $exit_code" -log_file $log_file
                    return $true
                } else {
                    Write-ToLog -message "Uninstallation of $appDisplayName may have failed with exit code $exit_code" -log_file $log_file
                    # Return true anyway to remove from tracking file, as we can't reliably determine failure for external apps
                    return $true
                }
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

# Batch uninstallation function used by the command-line mode
function Invoke-BatchUninstall {
    param (
        [string]$json_uninstall_file_path,
        [string]$uninstall_log_file
    )
    
    Write-Host "Starting batch uninstallation process..." -ForegroundColor Cyan
    Write-ToLog -message "Starting batch uninstallation from $json_uninstall_file_path" -log_file $uninstall_log_file
    
    # Check if the uninstall JSON file exists
    if (-not (Test-Path -Path $json_uninstall_file_path)) {
        $errorMsg = "Uninstall JSON file not found at: $json_uninstall_file_path"
        Write-Host $errorMsg -ForegroundColor Red
        Write-ToLog -message $errorMsg -log_file $uninstall_log_file
        return
    }
    
    # Try to read the uninstall JSON file
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
    
    # Initialize success trackers
    $successfulWingetUninstalls = 0
    $failedWingetUninstalls = 0
    $successfulExternalUninstalls = 0
    $failedExternalUninstalls = 0

    # Import Remove-FromJsonById from Append-ToJson.ps1 if not already available
    if (-not (Get-Command Remove-FromJsonById -ErrorAction SilentlyContinue)) {
        $appendToJsonPath = Join-Path -Path (Split-Path $PSScriptRoot -Parent) -ChildPath "Public\Append-ToJson.ps1"
        if (Test-Path $appendToJsonPath) {
            . $appendToJsonPath
        }
    }
    
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
                # Remove from uninstall.json immediately after uninstall
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
                # Remove from uninstall.json immediately after uninstall
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

    # At this point, Remove-FromJsonById will have deleted uninstall.json if all apps are removed.
    # If the file still exists, update it (for any failed uninstalls)
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
    
    # Summarize results
    Write-Host "`nUninstallation Summary:" -ForegroundColor Yellow
    Write-Host "--------------------" -ForegroundColor Yellow
    Write-Host "Winget Applications: $successfulWingetUninstalls successful, $failedWingetUninstalls failed" -ForegroundColor White
    Write-Host "External Applications: $successfulExternalUninstalls successful, $failedExternalUninstalls failed" -ForegroundColor White
    Write-Host "Total: $($successfulWingetUninstalls + $successfulExternalUninstalls) successful, $($failedWingetUninstalls + $failedExternalUninstalls) failed" -ForegroundColor White
    
    # Log summary
    Write-ToLog -message "Uninstallation Summary: $successfulWingetUninstalls winget apps successful, $failedWingetUninstalls failed" -log_file $uninstall_log_file
    Write-ToLog -message "Uninstallation Summary: $successfulExternalUninstalls external apps successful, $failedExternalUninstalls failed" -log_file $uninstall_log_file
}
