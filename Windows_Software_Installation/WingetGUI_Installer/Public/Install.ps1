# Install a list of selected packages (winget and external)
function Install-SelectedPackages {
    param (
        [Parameter(Mandatory=$true)]
        [array]$selectedPackages,
        [Parameter(Mandatory=$true)]
        [string]$log_file,
        [Parameter(Mandatory=$true)]
        [string]$uninstall_json_file
    )

    # Ensure execution policy allows script execution
    try {
        $currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
        if ($currentPolicy -eq "Restricted" -or $currentPolicy -eq "AllSigned") {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            Write-Host "Updated execution policy from $currentPolicy to RemoteSigned for CurrentUser" -ForegroundColor Yellow
            Write-ToLog -message "Updated execution policy from $currentPolicy to RemoteSigned for CurrentUser" -log_file $log_file
        }
    }
    catch {
        Write-Host "Warning: Could not set execution policy: $_" -ForegroundColor Yellow
        Write-ToLog -message "Warning: Could not set execution policy: $_" -log_file $log_file
    }

    $results = @()
    $installedCount = 0
    $failedCount = 0
    $skippedCount = 0
    $failedPackages = @()
    # Reload the original JSON so we can merge in all properties (like override_flags)
    $jsonPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'JSON/install/applications.json'
    $allAppsJson = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
    $allWingetApps = $allAppsJson.winget_applications
    $allExternalApps = $allAppsJson.external_applications
    $sharedPrerequisiteCommands = $allAppsJson.shared_prerequisites_commands

    foreach ($app in $selectedPackages) {
        $appType = $null

        if ($app.PSObject.Properties["Type"]) {
            $typeValue = $app.Type.ToString().ToLower()
            if ($typeValue -eq "winget") {
                $appType = "winget"
            } elseif ($typeValue -eq "external") {
                $appType = "external"
            }
        }

        if (-not $appType) {
            if ($app.PSObject.Properties["id"]) {
                $appType = "winget"
            } elseif ($app.PSObject.Properties["source"] -or $app.PSObject.Properties["install_command"] -or $app.PSObject.Properties["name"]) {
                $appType = "external"
            } else {
                $appType = "unknown"
            }
        }

        # Try to find the full app object fromgit stat the original JSON by id
        $fullApp = $null
        if ($appType -eq "winget") {
            if ($app.PSObject.Properties["id"]) {
                $fullApp = $allWingetApps | Where-Object { $_.id -eq $app.id } | Select-Object -First 1
            } elseif ($app.PSObject.Properties["Id"]) {
                $fullApp = $allWingetApps | Where-Object { $_.id -eq $app.Id } | Select-Object -First 1
            }
        } elseif ($appType -eq "external") {
            $externalName = $null
            if ($app.PSObject.Properties["name"]) {
                $externalName = $app.name
            } elseif ($app.PSObject.Properties["id"]) {
                $externalName = $app.id
            } elseif ($app.PSObject.Properties["Id"]) {
                $externalName = $app.Id
            }

            if ($externalName) {
                $fullApp = $allExternalApps | Where-Object { $_.name -eq $externalName } | Select-Object -First 1
            }
        }

        if ($fullApp) {
            # Merge missing properties from fullApp into $app
            foreach ($prop in $fullApp.PSObject.Properties) {
                if (-not $app.PSObject.Properties[$prop.Name]) {
                    $app | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
                }
            }
        }

        $appName = if ($app.PSObject.Properties["friendly_name"] -and $app.friendly_name) {
            $app.friendly_name
        } elseif ($app.PSObject.Properties["FriendlyName"] -and $app.FriendlyName) {
            $app.FriendlyName
        } elseif ($app.PSObject.Properties["name"] -and $app.name) {
            $app.name
        } elseif ($app.PSObject.Properties["id"] -and $app.id) {
            $app.id
        } elseif ($app.PSObject.Properties["Id"] -and $app.Id) {
            $app.Id
        } else {
            "UnknownApp"
        }

        $overrideFlags = $null
        if ($app.PSObject.Properties["override_flags"]) {
            $overrideFlags = $app.override_flags
            if ($null -ne $app.override_flags) {
            } else {
            }
        } elseif ($app.PSObject.Properties["OverrideFlags"]) {
            $overrideFlags = $app.OverrideFlags
            if ($null -ne $app.OverrideFlags) {
            } else {
            }
        } else {
        }
        $result = @{ name = $appName; type = $appType; status = "skipped"; message = "" }

        if ($appType -eq "winget") {
            try {
                Write-ToLog -message "Installing winget app: $appName" -log_file $log_file
                $wingetArgs = @("install", "--id", $app.id, "--accept-source-agreements", "--accept-package-agreements", "-h")
                if ($overrideFlags) {
                    Write-ToLog -message ("override_flags/OverrideFlags for " + $appName + ": " + $overrideFlags) -log_file $log_file
                    $wingetArgs += "--override"
                    $wingetArgs += "`"$overrideFlags`""
                } elseif ($app.install_args) {
                    $wingetArgs += $app.install_args
                }
                $process = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -PassThru -Wait -NoNewWindow
                $exit_code = $process.ExitCode
                $success = Test-InstallationSuccess -exit_code $exit_code -app_name $appName -log_file $log_file
                if ($success) {
                    $postInstallSuccess = Invoke-PostInstallActions -app $app -sharedPrerequisiteCommands $sharedPrerequisiteCommands -log_file $log_file
                    if (-not $postInstallSuccess) {
                        $failedCount++
                        $failedPackages += $appName
                        $result.status = "failed"
                        $result.message = "Installed, but post-install actions failed."
                        $results += $result
                        continue
                    }

                    $installedCount++
                    # Always add to uninstall tracking immediately, with required fields
                    $trackingApp = [PSCustomObject]@{
                        id = if ($app.id) { $app.id } elseif ($app.name) { $app.name } else { $appName }
                        name = if ($app.name) { $app.name } elseif ($app.id) { $app.id } else { $appName }
                        friendly_name = if ($app.friendly_name) { $app.friendly_name } else { $appName }
                        version = if ($app.version) { $app.version } else { "Latest" }
                        installed_on = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                        last_updated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    }
                    Append-ToJson -jsonFilePath $uninstall_json_file -section "winget_applications" -newObject $trackingApp
                    $result.status = "success"
                    $result.message = "Installed and tracked."
                } else {
                    $failedCount++
                    $failedPackages += $appName
                    $result.status = "failed"
                    $result.message = "Install failed."
                }
            } catch {
                $failedCount++
                $failedPackages += $appName
                Write-ToLog -message ("Exception during winget install for ${appName}: " + ($_ | Out-String)) -log_file $log_file
                $result.status = "error"
                $result.message = $_.Exception.Message
            }
        } elseif ($appType -eq "external") {
            # Always ensure uninstall tracking is updated for external apps as well, with required fields
            $success = Install-ExternalApplication -app $app -log_file $log_file -uninstall_json_file $uninstall_json_file
            if ($success) {
                $postInstallSuccess = Invoke-PostInstallActions -app $app -sharedPrerequisiteCommands $sharedPrerequisiteCommands -log_file $log_file
                if (-not $postInstallSuccess) {
                    $failedCount++
                    $failedPackages += $appName
                    $result.status = "failed"
                    $result.message = "Installed, but post-install actions failed."
                    $results += $result
                    continue
                }

                $installedCount++
                $result.status = "success"
                $result.message = "Installed and tracked."
            } else {
                $failedCount++
                $failedPackages += $appName
                $result.status = "failed"
                $result.message = "Install failed."
            }
        } else {
            $skippedCount++
            $result.status = "skipped"
            $result.message = "Unknown app type."
        }
        $results += $result
    }
    $summary = @{
        TotalPackages = $selectedPackages.Count
        SuccessfulInstalls = $installedCount
        FailedInstalls = $failedCount
        SkippedInstalls = $skippedCount
        FailedPackages = if ($failedPackages -and $failedPackages.Count -gt 0) { $failedPackages -join ", " } else { "None" }
    }
    Write-Host "Install Summary: Total: $($summary.TotalPackages), Installed: $($summary.SuccessfulInstalls), Failed: $($summary.FailedInstalls), Skipped: $($summary.SkippedInstalls), FailedPackages: $($summary.FailedPackages)" -ForegroundColor Green
    Write-ToLog -message "Install Summary: Total: $($summary.TotalPackages), Installed: $($summary.SuccessfulInstalls), Failed: $($summary.FailedInstalls), Skipped: $($summary.SkippedInstalls), FailedPackages: $($summary.FailedPackages)" -log_file $log_file
    return $summary
}
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

function Resolve-PostInstallCommands {
    param(
        [object]$postInstallCommands,
        [object]$sharedPrerequisiteCommands,
        [string]$log_file
    )

    $resolvedCommands = @()

    if (-not $postInstallCommands) {
        return $resolvedCommands
    }

    foreach ($commandEntry in $postInstallCommands) {
        if (-not $commandEntry) {
            continue
        }

        $entryText = $commandEntry.ToString().Trim()
        if ([string]::IsNullOrWhiteSpace($entryText)) {
            continue
        }

        if ($entryText -match '^shared_prerequisites_commands:(.+)$') {
            $commandSetName = $matches[1].Trim()
            if ($sharedPrerequisiteCommands -and $sharedPrerequisiteCommands.PSObject.Properties[$commandSetName]) {
                $sharedSet = $sharedPrerequisiteCommands.$commandSetName
                foreach ($sharedCommand in $sharedSet) {
                    if (-not [string]::IsNullOrWhiteSpace($sharedCommand)) {
                        $resolvedCommands += $sharedCommand.ToString()
                    }
                }
            } else {
                Write-ToLog -message "Shared post-install command set '$commandSetName' not found in JSON." -log_file $log_file
                return $null
            }
        } else {
            $resolvedCommands += $entryText
        }
    }

    return $resolvedCommands
}

function Set-PersistentEnvironmentVariables {
    param(
        [object]$environmentVariables,
        [string]$log_file,
        [string]$appDisplayName
    )

    if (-not $environmentVariables) {
        return $true
    }

    foreach ($property in $environmentVariables.PSObject.Properties) {
        $varName = $property.Name
        $varValue = if ($null -eq $property.Value) { "" } else { $property.Value.ToString() }

        if ([string]::IsNullOrWhiteSpace($varName)) {
            continue
        }

        try {
            [Environment]::SetEnvironmentVariable($varName, $varValue, "Machine")
            [Environment]::SetEnvironmentVariable($varName, $varValue, "Process")
            Write-ToLog -message "Set persistent machine environment variable for ${appDisplayName}: $varName=$varValue" -log_file $log_file
        }
        catch {
            try {
                [Environment]::SetEnvironmentVariable($varName, $varValue, "User")
                [Environment]::SetEnvironmentVariable($varName, $varValue, "Process")
                Write-ToLog -message "Set persistent user environment variable for ${appDisplayName}: $varName=$varValue" -log_file $log_file
            }
            catch {
                Write-ToLog -message "Failed setting environment variable for ${appDisplayName}: $varName. Error: $($_.Exception.Message)" -log_file $log_file
                return $false
            }
        }
    }

    return $true
}

function Invoke-PostInstallActions {
    param(
        [PSCustomObject]$app,
        [object]$sharedPrerequisiteCommands,
        [string]$log_file
    )

    $appDisplayName = if ($app.PSObject.Properties["friendly_name"] -and $app.friendly_name) {
        $app.friendly_name
    } elseif ($app.PSObject.Properties["name"] -and $app.name) {
        $app.name
    } elseif ($app.PSObject.Properties["id"] -and $app.id) {
        $app.id
    } else {
        "UnknownApp"
    }

    if ($app.PSObject.Properties["post_install_commands"]) {
        $resolvedCommands = Resolve-PostInstallCommands -postInstallCommands $app.post_install_commands -sharedPrerequisiteCommands $sharedPrerequisiteCommands -log_file $log_file
        if ($null -eq $resolvedCommands) {
            Write-ToLog -message "Post-install command resolution failed for $appDisplayName" -log_file $log_file
            return $false
        }

        foreach ($command in $resolvedCommands) {
            Write-ToLog -message "Running post-install command for ${appDisplayName}: $command" -log_file $log_file
            try {
                $process = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $command) -PassThru -Wait -NoNewWindow
                if ($process.ExitCode -ne 0) {
                    Write-ToLog -message "Post-install command failed for ${appDisplayName} with exit code $($process.ExitCode): $command" -log_file $log_file
                    return $false
                }
            }
            catch {
                Write-ToLog -message "Error running post-install command for ${appDisplayName}: $command. Error: $($_.Exception.Message)" -log_file $log_file
                return $false
            }
        }
    }

    if ($app.PSObject.Properties["post_install_environment_variables"]) {
        $envSuccess = Set-PersistentEnvironmentVariables -environmentVariables $app.post_install_environment_variables -log_file $log_file -appDisplayName $appDisplayName
        if (-not $envSuccess) {
            return $false
        }
    }

    return $true
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
    if (-not $app.name -or (-not $app.source -and -not $app.install_command)) {
        Write-ToLog -message "Error: External application $appDisplayName is missing required properties (name and either source or install_command)" -log_file $log_file
        return $false
    }
    
    try {
        $process = $null

        if ($app.install_command) {
            Write-ToLog -message "Running install command for ${appDisplayName}: $($app.install_command)" -log_file $log_file
            $process = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", $app.install_command) -PassThru -Wait -NoNewWindow
        } else {
            # Create a temporary directory for downloads if it doesn't exist
            $temp_dir = Join-Path $env:TEMP "EnvSetup_Downloads"
            if (-not (Test-Path $temp_dir)) {
                New-Item -ItemType Directory -Path $temp_dir -Force | Out-Null
            }

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
        }

        $exit_code = $process.ExitCode
        
        $success = ($exit_code -eq 0)
        Write-ToLog -message "Installation of $($appDisplayName) completed with exit code $exit_code" -log_file $log_file
        
        # Always add to tracking if install succeeded or app is already installed (1603)
        if ($success -or $exit_code -eq 1603) {
            # Add installation timestamp and additional info to tracking
            $trackingApp = [PSCustomObject]@{
                name = if ($app.name) { $app.name } else { $appDisplayName }
                friendly_name = if ($app.friendly_name) { $app.friendly_name } else { $appDisplayName }
                version = if ($app.version) { $app.version } else { "Latest" }
                uninstall_command = if ($app.PSObject.Properties.Name -contains "uninstall_command" -and $app.uninstall_command) { $app.uninstall_command } else { "" }
                installed_on = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                last_updated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
            # Add status for already installed applications
            if ($exit_code -eq 1603) {
                $trackingApp | Add-Member -MemberType NoteProperty -Name "installation_status" -Value "already_installed"
                Write-ToLog -message "$appDisplayName appears to be already installed. Adding to tracking file anyway." -log_file $log_file
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
            # No batch mode: all tracking is immediate per-app
        }
        
        return $success
    }
    catch {
        Write-ToLog -message "Error during installation of $($appDisplayName): $_" -log_file $log_file
        return $false
    }
}

