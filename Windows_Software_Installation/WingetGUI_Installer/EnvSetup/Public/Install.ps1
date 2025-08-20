# Install.ps1
# Module containing all installation-related functions

# Test if a winget installation was successful
function Test-InstallationSuccess {
    param (
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
        default { 
            Write-ToLog -message "Failed to install $app_name. Exit code: $exit_code" -log_file $log_file
            return $false
        }
    }
}

# Used by the GUI to install selected packages
function Install-SelectedPackages {
    param (
        [array]$selectedPackages,
        [string]$log_file,
        [string]$uninstall_json_file
    )
    
    # Prepare result tracking
    $results = @{
        TotalPackages = $selectedPackages.Count
        SuccessfulInstalls = 0
        FailedInstalls = 0
        FailedPackages = @()
    }

    foreach ($package in $selectedPackages) {
        # Create app object from the package information in the datatable
        $app = [PSCustomObject]@{
            name = $package.Id
            friendly_name = $package.FriendlyName
            version = if ($package.Version -eq "Latest") { $null } else { $package.Version }
            silent = $true
            force = $true
        }
        
        # For external applications
        if ($package.Type -eq "External") {
            # Need to look up the original application details to get URL and other info
            $applications = Get-Content -Path (Join-Path $PSScriptRoot "..\JSON\install\applications.json") -Raw | ConvertFrom-Json
            $originalApp = $applications.external_applications | Where-Object { $_.name -eq $app.name } | Select-Object -First 1
            
            if ($originalApp) {
                $app = $originalApp
            }
        }
        
        $success = $false
        
        try {
            if ($app.PSObject.Properties.Name -contains "url") {
                # This is an external application
                $success = Install-ExternalApplication -app $app -log_file $log_file -uninstall_json_file $uninstall_json_file
            } else {
                # This is a winget application
                $success = Install-WingetApplication -app $app -log_file $log_file -uninstall_json_file $uninstall_json_file
            }
            
            if ($success) {
                $results.SuccessfulInstalls++
            } else {
                $results.FailedInstalls++
                $appName = if ($app.friendly_name) { $app.friendly_name } else { $app.name }
                $results.FailedPackages += $appName
            }
        } catch {
            Write-ToLog -message "Error installing $($app.name): $_" -log_file $log_file
            $results.FailedInstalls++
            $appName = if ($app.friendly_name) { $app.friendly_name } else { $app.name }
            $results.FailedPackages += $appName
        }
    }
    
    return $results
}

# Install a winget application
function Install-WingetApplication {
    param (
        [PSCustomObject]$app,
        [string]$log_file,
        [string]$uninstall_json_file
    )

    # Validate app object has required properties
    if (-not $app -or -not $app.name) {
        Write-ToLog -message "Error: Invalid application object provided to Install-WingetApplication" -log_file $log_file
        return $false
    }

    # Log what we're about to install
    Write-ToLog -message "Installing application: $($app.name) $(if ($app.version) { "version $($app.version)" } else { "(latest version)" })" -log_file $log_file
    
    # Construct arguments for winget installation
    $arguments = @(
        "install", 
        "--accept-source-agreements", 
        "--accept-package-agreements"
    )
    
    if ($app.name) {
        $arguments += @("--id", $app.name)
    }
    
    if ($app.version) {
        $arguments += @("-v", $app.version)
    }
    
    if ($app.silent) {
        $arguments += @("--silent")
    }
    
    if ($app.force) {
        $arguments += @("--force")
    }
    
    # Add override flags if they exist for this application
    if ($app.override_flags) {
        $arguments += @("--override", $app.override_flags)
        Write-ToLog -message "Using custom override flags for $($app.name): $($app.override_flags)" -log_file $log_file
    }
    
    # Log the full command we're about to execute
    $commandStr = "winget $($arguments -join ' ')"
    Write-ToLog -message "Executing command: $commandStr" -log_file $log_file
    
    try {
        $process = Start-Process -FilePath winget -ArgumentList $arguments -PassThru -Wait -NoNewWindow
        $exit_code = $process.ExitCode
        
        $success = Test-InstallationSuccess -exit_code $exit_code -app_name $app.name -log_file $log_file
        
        if ($success -and -not [string]::IsNullOrWhiteSpace($uninstall_json_file)) {
            # Append successful installation to uninstall JSON
            Append-ToJson -jsonFilePath $uninstall_json_file -section "winget_applications" -newObject $app
        }
        
        return $success
    }
    catch {
        Write-ToLog -message "Error during installation of $($app.name): $_" -log_file $log_file
        return $false
    }
}

# Install an external application
function Install-ExternalApplication {
    param (
        [PSCustomObject]$app,
        [string]$log_file,
        [string]$uninstall_json_file
    )

    Write-ToLog -message "Installing external application $($app.name)" -log_file $log_file
    
    # Create a temporary directory for downloads if it doesn't exist
    $temp_dir = Join-Path $env:TEMP "EnvSetup_Downloads"
    if (-not (Test-Path $temp_dir)) {
        New-Item -ItemType Directory -Path $temp_dir -Force | Out-Null
    }
    
    try {
        # Download the installer
        $installer_path = Join-Path $temp_dir "$($app.name)_installer$(Split-Path $app.url -Extension)"
        try {
            Invoke-WebRequest -Uri $app.url -OutFile $installer_path -UseBasicParsing
            Write-ToLog -message "Downloaded installer for $($app.name) to $installer_path" -log_file $log_file
        }
        catch {
            Write-ToLog -message "Failed to download installer for $($app.name): $_" -log_file $log_file
            return $false
        }
        
        # Run the installer
        $arguments = @()
        if ($app.install_args) {
            $arguments = $app.install_args -split '\s+'
        }
        
        $process = Start-Process -FilePath $installer_path -ArgumentList $arguments -PassThru -Wait -NoNewWindow
        $exit_code = $process.ExitCode
        
        $success = ($exit_code -eq 0)
        Write-ToLog -message "Installation of $($app.name) completed with exit code $exit_code" -log_file $log_file
        
        # Only add to uninstall JSON if we have an uninstall command and the uninstall_json_file is valid
        if ($success -and $app.uninstall_command -and -not [string]::IsNullOrWhiteSpace($uninstall_json_file)) {
            Append-ToJson -jsonFilePath $uninstall_json_file -section "external_applications" -newObject $app
        }
        
        return $success
    }
    catch {
        Write-ToLog -message "Error during installation of $($app.name): $_" -log_file $log_file
        return $false
    }
}

# Batch installation function used by the command-line mode
function Invoke-BatchInstall {
    param (
        [string]$json_install_file_path,
        [string]$install_log_file,
        [string]$uninstall_json_file
    )
    
    $applications = Get-Content -Path $json_install_file_path -Raw | ConvertFrom-Json
    
    # Install winget applications
    foreach ($app in $applications.winget_applications) {
        Install-WingetApplication -app $app -log_file $install_log_file -uninstall_json_file $uninstall_json_file
    }
    
    # Install external applications
    foreach ($app in $applications.external_applications) {
        Install-ExternalApplication -app $app -log_file $install_log_file -uninstall_json_file $uninstall_json_file
    }
}
