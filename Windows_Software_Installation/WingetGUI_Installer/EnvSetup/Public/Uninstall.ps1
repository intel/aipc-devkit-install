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
            return $true
        }
        default { 
            Write-ToLog -message "Failed to uninstall $app_name. Exit code: $exit_code" -log_file $log_file
            return $false
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
        $app = [PSCustomObject]@{
            name = $package.Id
            friendly_name = $package.FriendlyName
            version = if ($package.Version -eq "Latest") { $null } else { $package.Version }
        }
        
        # For external applications
        if ($package.Type -eq "External") {
            # Need to look up the original application details to get uninstall command
            $uninstallJson = Get-Content -Path $json_uninstall_file_path -Raw | ConvertFrom-Json
            $originalApp = $uninstallJson.external_applications | Where-Object { $_.name -eq $app.name } | Select-Object -First 1
            
            if ($originalApp) {
                $app = $originalApp
            }
        }
        
        try {
            if ($app.PSObject.Properties.Name -contains "uninstall_command") {
                # This is an external application
                $success = Uninstall-ExternalApplication -app $app -log_file $log_file
            } else {
                # This is a winget application
                $success = Uninstall-WingetApplication -app $app -log_file $log_file
            }
            
            if ($success) {
                $results.SuccessfulUninstalls++
            } else {
                $results.FailedUninstalls++
                $appName = if ($app.friendly_name) { $app.friendly_name } else { $app.name }
                $results.FailedPackages += $appName
            }
        } catch {
            Write-ToLog -message "Error uninstalling $($app.name): $_" -log_file $log_file
            $results.FailedUninstalls++
            $appName = if ($app.friendly_name) { $app.friendly_name } else { $app.name }
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
    if (-not $app -or -not $app.name) {
        Write-ToLog -message "Error: Invalid application object provided to Uninstall-WingetApplication" -log_file $log_file
        return $false
    }

    # Log what we're about to uninstall
    Write-ToLog -message "Uninstalling application: $($app.name) $(if ($app.version) { "version $($app.version)" } else { "(any version)" })" -log_file $log_file

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
        Write-ToLog -message "Using custom uninstall override flags for $($app.name): $($app.uninstall_override_flags)" -log_file $log_file
    }

    Write-ToLog -message "Uninstalling $($app.name)" -log_file $log_file
    
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
        
        return Test-UninstallationSuccess -exit_code $exit_code -app_name $app.name -log_file $log_file
    }
    catch {
        Write-ToLog -message "Error during uninstallation of $($app.name): $_" -log_file $log_file
        return $false
    }
}

# Uninstall an external application
function Uninstall-ExternalApplication {
    param (
        [PSCustomObject]$app,
        [string]$log_file
    )

    # Validate app object has required properties
    if (-not $app -or -not $app.uninstall_command) {
        Write-ToLog -message "Error: Invalid application object or missing uninstall command for external application" -log_file $log_file
        return $false
    }

    $regex = "([a-zA-Z]:.*.exe)(.*)" # Regex to match the uninstall command
    if ($app.uninstall_command -match $regex) {
        $command = $matches[1]
        $arguments_unsplit = $matches[2]
        $arguments_split = $arguments_unsplit -split '\s+' | Where-Object { $_ -ne "" } # Splits the arguments for the uninstall command

        Write-ToLog -message "Uninstalling external application: $($app.name)" -log_file $log_file
        Write-ToLog -message "Using command: $command $arguments_unsplit" -log_file $log_file
        
        try {
            $process = Start-Process -FilePath $command -ArgumentList $arguments_split -PassThru -Wait -NoNewWindow
            $exit_code = $process.ExitCode
            Write-ToLog -message "Uninstalled $($app.name) with exit code $exit_code" -log_file $log_file
            return ($exit_code -eq 0)
        }
        catch {
            Write-ToLog -message "Error during uninstallation of external application $($app.name): $_" -log_file $log_file
            return $false
        }
    }
    else {
        Write-ToLog -message "Invalid uninstall command format for $($app.name)" -log_file $log_file
        return $false
    }
}

# Batch uninstallation function used by the command-line mode
function Invoke-BatchUninstall {
    param (
        [string]$json_uninstall_file_path,
        [string]$uninstall_log_file
    )
    
    $applications = Get-Content -Path $json_uninstall_file_path -Raw | ConvertFrom-Json
    
    # Uninstall winget applications
    foreach ($app in $applications.winget_applications) {
        Uninstall-WingetApplication -app $app -log_file $uninstall_log_file
    }
    
    # Uninstall external applications
    foreach ($app in $applications.external_applications) {
        Uninstall-ExternalApplication -app $app -log_file $uninstall_log_file
    }
    
    # Remove JSON uninstall folder after completion
    $json_uninstall_dir = Split-Path -Path $json_uninstall_file_path -Parent
    Remove-Item -Path $json_uninstall_dir -Recurse
}
