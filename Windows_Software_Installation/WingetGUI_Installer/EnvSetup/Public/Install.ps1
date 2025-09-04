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
        # Add any other exit codes that winget might return
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
            # Error code for "The parameter is incorrect" - common with some installations
            Write-ToLog -message "Application $app_name completed with exit code 87 (parameter incorrect) - likely already installed" -log_file $log_file
            return $true
        }
        3010 {
            # Common installer exit code for reboot required
            Write-ToLog -message "Application $app_name successfully installed (reboot required)" -log_file $log_file
            return $true
        }
        1 {
            # Some installers use 1 to indicate success with warnings or already installed
            Write-ToLog -message "Application $app_name completed with exit code 1 (success with warnings or already installed)" -log_file $log_file
            return $true
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

    # Load the full applications.json for reference
    $applications = Get-Content -Path (Join-Path $PSScriptRoot "..\JSON\install\applications.json") -Raw | ConvertFrom-Json

    foreach ($package in $selectedPackages) {
        # Try to find the full app object from JSON (winget or external)
        $app = $null
        if ($package.Type -eq "External") {
            $app = $applications.external_applications | Where-Object { $_.name -eq $package.Id } | Select-Object -First 1
        } else {
            $app = $applications.winget_applications | Where-Object { ($_.id -eq $package.Id) -or ($_.name -eq $package.Id) } | Select-Object -First 1
        }
        # If not found, fallback to datatable info
        if (-not $app) {
            $app = [PSCustomObject]@{
                name = $package.Id
                friendly_name = $package.FriendlyName
                version = if ($package.Version -eq "Latest") { $null } else { $package.Version }
                silent = $true
                force = $true
            }
        }
        # Always ensure silent/force for GUI, even if property doesn't exist
        if ($app.PSObject.Properties.Name -contains 'silent') {
            $app.silent = $true
        } else {
            $app | Add-Member -MemberType NoteProperty -Name 'silent' -Value $true -Force
        }
        if ($app.PSObject.Properties.Name -contains 'force') {
            $app.force = $true
        } else {
            $app | Add-Member -MemberType NoteProperty -Name 'force' -Value $true -Force
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
    if (-not $app -or (-not $app.id -and -not $app.name)) {
        Write-ToLog -message "Error: Invalid application object provided to Install-WingetApplication. Must have id or name property." -log_file $log_file
        return $false
    }

    # Determine the application identifier to use (prefer id, fall back to name)
    $appIdentifier = if ($app.id) { $app.id } else { $app.name }
    $appDisplayName = if ($app.friendly_name) { $app.friendly_name } else { $appIdentifier }

    # Log what we're about to install
    Write-ToLog -message "Installing application: $appDisplayName $(if ($app.version) { "version $($app.version)" } else { "(latest version)" })" -log_file $log_file
    
    # Construct arguments for winget installation
    $arguments = @(
        "install", 
        "--accept-source-agreements", 
        "--accept-package-agreements"
    )
    
    # Add the application ID
    $arguments += @("--id", $appIdentifier)
    
    if ($app.version) {
        $arguments += @("-v", $app.version)
    }
    
    if ($app.silent -or $true) { # Always use silent flag
        $arguments += @("--silent")
    }
    
    if ($app.force -or $true) { # Always use force flag
        $arguments += @("--force")
    }
    
    # Add override flags if they exist for this application
    if ($app.override_flags) {
        # Handle special case for Visual Studio
        if ($appIdentifier -like "*VisualStudio*") {
            Write-ToLog -message "Using Visual Studio custom override flags for $($appDisplayName): $($app.override_flags)" -log_file $log_file
            $arguments += @("--override", "`"$($app.override_flags)`"")
        }
        # For other applications
        else {
            Write-ToLog -message "Using custom override flags for $($appDisplayName): $($app.override_flags)" -log_file $log_file
            $arguments += @("--override", "`"$($app.override_flags)`"")
        }
    }
    
    # Log the full command we're about to execute
    $commandStr = "winget $($arguments -join ' ')"
    Write-ToLog -message "Executing command: $commandStr" -log_file $log_file
    
    try {
        $process = Start-Process -FilePath winget -ArgumentList $arguments -PassThru -Wait -NoNewWindow
        $exit_code = $process.ExitCode
        
        $success = Test-InstallationSuccess -exit_code $exit_code -app_name $appDisplayName -log_file $log_file
        
        if ($success -and -not [string]::IsNullOrWhiteSpace($uninstall_json_file)) {
            # Add installation timestamp and additional info to tracking
            $trackingApp = $app.PSObject.Copy()
            
            # Add installation timestamp if not present
            if (-not ($trackingApp.PSObject.Properties.Name -contains "installed_on")) {
                $trackingApp | Add-Member -MemberType NoteProperty -Name "installed_on" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
            
            # Add or update last_updated timestamp
            if ($trackingApp.PSObject.Properties.Name -contains "last_updated") {
                $trackingApp.last_updated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            } else {
                $trackingApp | Add-Member -MemberType NoteProperty -Name "last_updated" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
            
            # Append successful installation to uninstall JSON with retry logic
            $retryCount = 0
            $maxRetries = 3
            $success_append = $false
            
            while ($retryCount -lt $maxRetries -and -not $success_append) {
                try {
                    # Add a small delay to prevent file access conflicts
                    if ($retryCount -gt 0) {
                        Start-Sleep -Milliseconds (100 * $retryCount)
                    }
                    
                    Append-ToJson -jsonFilePath $uninstall_json_file -section "winget_applications" -newObject $trackingApp
                    $success_append = $true
                    
                    # Log the tracking update
                    if ($exit_code -eq 0) {
                        Write-ToLog -message "Added/updated $appDisplayName in tracking file for uninstallation" -log_file $log_file
                    } else {
                        Write-ToLog -message "Application $appDisplayName already installed, updated tracking file" -log_file $log_file
                    }
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
        
        # Return tracking app data for batch mode (when uninstall_json_file is empty)
        if ([string]::IsNullOrWhiteSpace($uninstall_json_file) -and $success) {
            $trackingApp = $app.PSObject.Copy()
            
            # Add installation timestamp if not present
            if (-not ($trackingApp.PSObject.Properties.Name -contains "installed_on")) {
                $trackingApp | Add-Member -MemberType NoteProperty -Name "installed_on" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
            
            # Add or update last_updated timestamp
            if ($trackingApp.PSObject.Properties.Name -contains "last_updated") {
                $trackingApp.last_updated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            } else {
                $trackingApp | Add-Member -MemberType NoteProperty -Name "last_updated" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
            
            # Store the tracking app in a global variable for batch collection
            if (-not $Global:BatchTrackedApps) {
                $Global:BatchTrackedApps = @{
                    "winget_applications" = @()
                    "external_applications" = @()
                }
            }
            $Global:BatchTrackedApps.winget_applications += $trackingApp
        }
        
        return $success
    }
    catch {
        Write-ToLog -message "Error during installation of $($appDisplayName): $_" -log_file $log_file
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

    # Get display name for logging
    $appDisplayName = if ($app.friendly_name) { $app.friendly_name } else { $app.name }
    
    Write-ToLog -message "Installing external application $appDisplayName" -log_file $log_file
    
    # Check for required properties
    if (-not $app.name -or -not $app.source) {
        Write-ToLog -message "Error: External application $appDisplayName is missing required properties (name or source)" -log_file $log_file
        return $false
    }
    
    # Create a temporary directory for downloads if it doesn't exist
    $temp_dir = Join-Path $env:TEMP "EnvSetup_Downloads"
    if (-not (Test-Path $temp_dir)) {
        New-Item -ItemType Directory -Path $temp_dir -Force | Out-Null
    }
    
    try {
        # Download the installer
        $installer_path = Join-Path $temp_dir "$($app.name)_installer$(Split-Path $app.source -Extension)"
        try {
            Write-ToLog -message "Downloading $($appDisplayName) from $($app.source)" -log_file $log_file
            Invoke-WebRequest -Uri $app.source -OutFile $installer_path -UseBasicParsing
            Write-ToLog -message "Downloaded installer for $($appDisplayName) to $installer_path" -log_file $log_file
        }
        catch {
            Write-ToLog -message "Failed to download installer for $($appDisplayName): $_" -log_file $log_file
            return $false
        }
        
        # Run the installer
        $arguments = @()
        if ($app.install_flags) {
            $arguments = $app.install_flags -split '\s+'
        } elseif ($app.install_args) {
            # For backward compatibility
            $arguments = $app.install_args -split '\s+'
        }
        
        Write-ToLog -message "Running installer for $appDisplayName with arguments: $($arguments -join ' ')" -log_file $log_file
        $process = Start-Process -FilePath $installer_path -ArgumentList $arguments -PassThru -Wait -NoNewWindow
        $exit_code = $process.ExitCode
        
        $success = ($exit_code -eq 0)
        Write-ToLog -message "Installation of $($appDisplayName) completed with exit code $exit_code" -log_file $log_file
        
        # Only add to tracking if we have an uninstall command
        if (($success -or $exit_code -eq 1603) -and $app.uninstall_command) {
            # Exit code 1603 often means "already installed" for many installers
            # Add installation timestamp and additional info to tracking
            $trackingApp = $app.PSObject.Copy()
            
            # Add installation timestamp if not present
            if (-not ($trackingApp.PSObject.Properties.Name -contains "installed_on")) {
                $trackingApp | Add-Member -MemberType NoteProperty -Name "installed_on" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
            
            # Add or update last_updated timestamp
            if ($trackingApp.PSObject.Properties.Name -contains "last_updated") {
                $trackingApp.last_updated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            } else {
                $trackingApp | Add-Member -MemberType NoteProperty -Name "last_updated" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
            
            # Add status for already installed applications
            if ($exit_code -eq 1603) {
                if (-not ($trackingApp.PSObject.Properties.Name -contains "installation_status")) {
                    $trackingApp | Add-Member -MemberType NoteProperty -Name "installation_status" -Value "already_installed"
                }
                Write-ToLog -message "$appDisplayName appears to be already installed. Adding to tracking file anyway." -log_file $log_file
                # Return success for already installed applications
                $success = $true
            }
            
            # Handle tracking based on mode
            if (-not [string]::IsNullOrWhiteSpace($uninstall_json_file)) {
                # GUI mode: append to JSON file immediately
                $retryCount = 0
                $maxRetries = 3
                $success_append = $false
                
                while ($retryCount -lt $maxRetries -and -not $success_append) {
                    try {
                        # Add a small delay to prevent file access conflicts
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
            else {
                # Batch mode: collect for later batch update
                if (-not $Global:BatchTrackedApps) {
                    $Global:BatchTrackedApps = @{
                        "winget_applications" = @()
                        "external_applications" = @()
                    }
                }
                $Global:BatchTrackedApps.external_applications += $trackingApp
                Write-ToLog -message "Collected $appDisplayName for batch tracking update" -log_file $log_file
            }
        }
        
        return $success
    }
    catch {
        Write-ToLog -message "Error during installation of $($appDisplayName): $_" -log_file $log_file
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
    
    Write-Host "Invoke-BatchInstall: Loading applications from $json_install_file_path" -ForegroundColor Cyan
    Write-ToLog -message "Loading applications from $json_install_file_path" -log_file $install_log_file
    
    # Arrays to collect applications for batch JSON update
    $trackedWingetApps = @()
    $trackedExternalApps = @()
    
    if (-not (Test-Path -Path $json_install_file_path)) {
        $errorMsg = "JSON file not found at: $json_install_file_path"
        Write-Host $errorMsg -ForegroundColor Red
        Write-ToLog -message $errorMsg -log_file $install_log_file
        
        # Try alternative path
        $alternativePath = Join-Path $PSScriptRoot "..\..\JSON\install\applications.json"
        $alternativePath = [System.IO.Path]::GetFullPath($alternativePath)
        
        Write-Host "Checking alternative path: $alternativePath" -ForegroundColor Yellow
        Write-ToLog -message "Checking alternative path: $alternativePath" -log_file $install_log_file
        
        if (Test-Path -Path $alternativePath) {
            Write-Host "Using alternative JSON path: $alternativePath" -ForegroundColor Green
            Write-ToLog -message "Using alternative JSON path: $alternativePath" -log_file $install_log_file
            $json_install_file_path = $alternativePath
        } else {
            $errorMsg = "Alternative JSON path also not found. Installation failed."
            Write-Host $errorMsg -ForegroundColor Red
            Write-ToLog -message $errorMsg -log_file $install_log_file
            return
        }
    }
    
    try {
        Write-Host "Reading JSON file..." -ForegroundColor Cyan
        $applications = Get-Content -Path $json_install_file_path -Raw | ConvertFrom-Json
        
        # Verify JSON structure
        if (-not $applications.winget_applications -and -not $applications.external_applications) {
            $errorMsg = "Invalid JSON structure in $json_install_file_path. Missing winget_applications or external_applications."
            Write-Host $errorMsg -ForegroundColor Red
            Write-ToLog -message $errorMsg -log_file $install_log_file
            return
        }
        
        Write-Host "Successfully loaded applications JSON" -ForegroundColor Green
        Write-ToLog -message "Successfully loaded applications JSON" -log_file $install_log_file
        
        # Install winget applications
        if ($applications.winget_applications) {
            $wingetCount = $applications.winget_applications.Count
            Write-Host "Installing $wingetCount winget applications..." -ForegroundColor Cyan
            Write-ToLog -message "Installing $wingetCount winget applications..." -log_file $install_log_file
            
            $installCount = 0
            $skipCount = 0
            
            foreach ($app in $applications.winget_applications) {
                $appName = if ($app.friendly_name) { $app.friendly_name } else { $app.id -or $app.name }
                
                # Check if the app should be skipped
                if ($app.skip_install -eq "yes") {
                    Write-Host "Skipping $appName (skip_install=yes)" -ForegroundColor Yellow
                    Write-ToLog -message "Skipping $appName (skip_install=yes)" -log_file $install_log_file
                    $skipCount++
                    continue
                }
                
                Write-Host "Installing winget application: $appName" -ForegroundColor Cyan
                $success = Install-WingetApplication -app $app -log_file $install_log_file -uninstall_json_file ""
                
                if ($success) {
                    $installCount++
                    # Add to tracking array instead of immediately updating JSON
                    $trackingApp = $app.PSObject.Copy()
                    if (-not ($trackingApp.PSObject.Properties.Name -contains "installed_on")) {
                        $trackingApp | Add-Member -MemberType NoteProperty -Name "installed_on" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    }
                    if ($trackingApp.PSObject.Properties.Name -contains "last_updated") {
                        $trackingApp.last_updated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    } else {
                        $trackingApp | Add-Member -MemberType NoteProperty -Name "last_updated" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    }
                    $trackedWingetApps += $trackingApp
                    Write-ToLog -message "Added $appName to batch tracking for uninstallation" -log_file $install_log_file
                } else {
                    # Even if installation "failed", let's check if it's already installed and add it to tracking
                    $isAlreadyInstalled = $false
                    
                    # Check if the application is already installed using winget list
                    $appId = if ($app.id) { $app.id } else { $app.name }
                    Write-Host "Checking if $appName is already installed..." -ForegroundColor Yellow
                    
                    try {
                        $wingetList = winget list --id $appId --accept-source-agreements 2>&1
                        $isAlreadyInstalled = $wingetList -match $appId
                        
                        if ($isAlreadyInstalled) {
                            Write-Host "Application $appName is already installed. Adding to batch tracking." -ForegroundColor Yellow
                            Write-ToLog -message "Application $appName is already installed. Adding to batch tracking." -log_file $install_log_file
                            
                            # Add to tracking array
                            $trackingApp = $app.PSObject.Copy()
                            if (-not ($trackingApp.PSObject.Properties.Name -contains "installed_on")) {
                                $trackingApp | Add-Member -MemberType NoteProperty -Name "installed_on" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                            }
                            if ($trackingApp.PSObject.Properties.Name -contains "last_updated") {
                                $trackingApp.last_updated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                            } else {
                                $trackingApp | Add-Member -MemberType NoteProperty -Name "last_updated" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                            }
                            if (-not ($trackingApp.PSObject.Properties.Name -contains "installation_status")) {
                                $trackingApp | Add-Member -MemberType NoteProperty -Name "installation_status" -Value "already_installed"
                            }
                            $trackedWingetApps += $trackingApp
                            Write-ToLog -message "Added $appName to batch tracking (already installed)" -log_file $install_log_file
                        }
                    } catch {
                        Write-Host "Error checking if $appName is already installed: $_" -ForegroundColor Red
                        Write-ToLog -message "Error checking if $appName is already installed: $_" -log_file $install_log_file
                    }
                }
            }
            
            Write-Host "Winget installation summary: $installCount installed, $skipCount skipped" -ForegroundColor Green
            Write-ToLog -message "Winget installation summary: $installCount installed, $skipCount skipped" -log_file $install_log_file
        } else {
            Write-Host "No winget applications found in JSON" -ForegroundColor Yellow
            Write-ToLog -message "No winget applications found in JSON" -log_file $install_log_file
        }
        
        # Install external applications
        if ($applications.external_applications) {
            $externalCount = $applications.external_applications.Count
            Write-Host "Installing $externalCount external applications..." -ForegroundColor Cyan
            Write-ToLog -message "Installing $externalCount external applications..." -log_file $install_log_file
            
            $installCount = 0
            $skipCount = 0
            
            foreach ($app in $applications.external_applications) {
                $appName = if ($app.friendly_name) { $app.friendly_name } else { $app.name }
                
                # Check if the app should be skipped
                if ($app.skip_install -eq "yes") {
                    Write-Host "Skipping $appName (skip_install=yes)" -ForegroundColor Yellow
                    Write-ToLog -message "Skipping $appName (skip_install=yes)" -log_file $install_log_file
                    $skipCount++
                    continue
                }
                
                Write-Host "Installing external application: $appName" -ForegroundColor Cyan
                $success = Install-ExternalApplication -app $app -log_file $install_log_file -uninstall_json_file ""
                
                if ($success) {
                    $installCount++
                    # Add to tracking array instead of immediately updating JSON
                    if ($app.uninstall_command) {
                        $trackingApp = $app.PSObject.Copy()
                        if (-not ($trackingApp.PSObject.Properties.Name -contains "installed_on")) {
                            $trackingApp | Add-Member -MemberType NoteProperty -Name "installed_on" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                        }
                        if ($trackingApp.PSObject.Properties.Name -contains "last_updated") {
                            $trackingApp.last_updated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                        } else {
                            $trackingApp | Add-Member -MemberType NoteProperty -Name "last_updated" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                        }
                        $trackedExternalApps += $trackingApp
                        Write-ToLog -message "Added $appName to batch tracking for uninstallation" -log_file $install_log_file
                    }
                }
            }
            
            Write-Host "External applications summary: $installCount installed, $skipCount skipped" -ForegroundColor Green
            Write-ToLog -message "External applications summary: $installCount installed, $skipCount skipped" -log_file $install_log_file
        } else {
            Write-Host "No external applications found in JSON" -ForegroundColor Yellow
            Write-ToLog -message "No external applications found in JSON" -log_file $install_log_file
        }
        
        # Now perform a single batch update to the JSON file
        if ($trackedWingetApps.Count -gt 0 -or $trackedExternalApps.Count -gt 0) {
            Write-Host "Updating uninstall tracking file with $($trackedWingetApps.Count) winget and $($trackedExternalApps.Count) external applications..." -ForegroundColor Cyan
            Write-ToLog -message "Updating uninstall tracking file with $($trackedWingetApps.Count) winget and $($trackedExternalApps.Count) external applications..." -log_file $install_log_file
            
            try {
                # Create or load existing uninstall JSON
                if (Test-Path -Path $uninstall_json_file) {
                    $uninstallData = Get-Content -Path $uninstall_json_file -Raw | ConvertFrom-Json
                } else {
                    # Create directory if it doesn't exist
                    $uninstallDir = Split-Path -Path $uninstall_json_file -Parent
                    if (-not (Test-Path $uninstallDir)) {
                        New-Item -Path $uninstallDir -ItemType Directory -Force | Out-Null
                    }
                    
                    $uninstallData = @{
                        "winget_applications" = @()
                        "external_applications" = @()
                    }
                }
                
                # Ensure arrays exist
                if (-not $uninstallData.winget_applications) { $uninstallData.winget_applications = @() }
                if (-not $uninstallData.external_applications) { $uninstallData.external_applications = @() }
                
                # Add tracked winget applications
                foreach ($app in $trackedWingetApps) {
                    # Check if already exists
                    $exists = $false
                    $appId = if ($app.id) { $app.id } else { $app.name }
                    
                    for ($i = 0; $i -lt $uninstallData.winget_applications.Count; $i++) {
                        $existing = $uninstallData.winget_applications[$i]
                        $existingId = if ($existing.id) { $existing.id } else { $existing.name }
                        if ($existingId -eq $appId) {
                            # Update existing entry
                            $uninstallData.winget_applications[$i] = $app
                            $exists = $true
                            break
                        }
                    }
                    
                    if (-not $exists) {
                        # Add new entry
                        $uninstallData.winget_applications += $app
                    }
                }
                
                # Add tracked external applications
                foreach ($app in $trackedExternalApps) {
                    # Check if already exists
                    $exists = $false
                    
                    for ($i = 0; $i -lt $uninstallData.external_applications.Count; $i++) {
                        $existing = $uninstallData.external_applications[$i]
                        if ($existing.name -eq $app.name) {
                            # Update existing entry
                            $uninstallData.external_applications[$i] = $app
                            $exists = $true
                            break
                        }
                    }
                    
                    if (-not $exists) {
                        # Add new entry
                        $uninstallData.external_applications += $app
                    }
                }
                
                # Write the complete JSON file in one operation
                $uninstallData | ConvertTo-Json -Depth 5 | Set-Content -Path $uninstall_json_file -Encoding UTF8
                
                Write-Host "Successfully updated uninstall tracking file" -ForegroundColor Green
                Write-ToLog -message "Successfully updated uninstall tracking file with $($trackedWingetApps.Count) winget and $($trackedExternalApps.Count) external applications" -log_file $install_log_file
                
            } catch {
                Write-Host "Error updating uninstall tracking file: $_" -ForegroundColor Red
                Write-ToLog -message "Error updating uninstall tracking file: $_" -log_file $install_log_file
            }
        }
        
        Write-Host "Installation process completed" -ForegroundColor Green
        Write-ToLog -message "Installation process completed" -log_file $install_log_file
    }
    catch {
        $errorMsg = "Error processing JSON file: $_"
        Write-Host $errorMsg -ForegroundColor Red
        Write-ToLog -message $errorMsg -log_file $install_log_file
    }
}
