# Uninstall.ps1
# Module containing all uninstallation-related functions

# Remove persistent environment variables set during installation
function Remove-PersistentEnvironmentVariables {
    param (
        [PSCustomObject]$app,
        [string]$log_file
    )

    # Check if the app has post_install_environment_variables
    if (-not $app.post_install_environment_variables) {
        return
    }

    $appDisplayName = if ($app.friendly_name) { $app.friendly_name } else { 
        if ($app.id) { $app.id } else { $app.name }
    }

    foreach ($varName in $app.post_install_environment_variables.PSObject.Properties.Name) {
        try {
            # Try to remove from Machine scope first (requires admin)
            [Environment]::SetEnvironmentVariable($varName, $null, "Machine")
            Write-ToLog -message "Removed environment variable $varName from Machine scope for ${appDisplayName}" -log_file $log_file
        } catch {
            # If Machine scope fails, try User scope
            try {
                [Environment]::SetEnvironmentVariable($varName, $null, "User")
                Write-ToLog -message "Removed environment variable $varName from User scope for ${appDisplayName}" -log_file $log_file
            } catch {
                Write-ToLog -message "Warning: Failed to remove environment variable $varName for ${appDisplayName}: $_" -log_file $log_file
            }
        }
    }
}

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

function Test-WingetUninstallOverrideSupport {
    if ($script:WingetUninstallOverrideSupportCached -ne $null) {
        return [bool]$script:WingetUninstallOverrideSupportCached
    }

    $supportsOverride = $false
    try {
        $wingetHelpText = (& winget uninstall --help 2>&1 | Out-String)
        if (-not [string]::IsNullOrWhiteSpace($wingetHelpText) -and ($wingetHelpText -match '(?im)^\s*--override\b')) {
            $supportsOverride = $true
        }
    }
    catch {
        $supportsOverride = $false
    }

    $script:WingetUninstallOverrideSupportCached = $supportsOverride
    return $supportsOverride
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

    try {
        $jsonText = Get-Content -Path $json_uninstall_file_path -Raw
        if ([string]::IsNullOrWhiteSpace($jsonText)) {
            throw "uninstall.json is empty"
        }
        $uninstallJson = $jsonText | ConvertFrom-Json
    }
    catch {
        Write-ToLog -message "Error: Invalid uninstall JSON at ${json_uninstall_file_path}: $($_.Exception.Message)" -log_file $log_file
        throw "Invalid uninstall JSON. Please recreate uninstall.json by running install again."
    }
    $globalUninstallFlags = if ($uninstallJson.PSObject.Properties.Name -contains "global_uninstall_flags") { $uninstallJson.global_uninstall_flags } else { $null }

    # Load applications.json so uninstall commands are sourced from the single source of truth.
    $installJson = $null
    try {
        $installJsonPath = Join-Path -Path (Split-Path $PSScriptRoot -Parent) -ChildPath "JSON\install\applications.json"
        if (Test-Path -Path $installJsonPath) {
            $installJson = Get-Content -Path $installJsonPath -Raw | ConvertFrom-Json
        }
    }
    catch {
        Write-ToLog -message "Warning: Could not load applications.json for uninstall command lookup: $($_.Exception.Message)" -log_file $log_file
    }

    # Auto-include currently tracked dependency packages so uninstalling a primary app
    # also removes dependencies that were pulled in for it.
    if ($installJson -and $selectedPackages.Count -gt 0) {
        function Resolve-DependencyPackageFromTracked {
            param(
                [string]$dependencyName,
                [object]$trackedJson
            )

            if ([string]::IsNullOrWhiteSpace($dependencyName) -or -not $trackedJson) {
                return $null
            }

            $wingetExact = $trackedJson.winget_applications | Where-Object {
                ($_.id -and $_.id -eq $dependencyName) -or ($_.name -and $_.name -eq $dependencyName)
            } | Select-Object -First 1
            if ($wingetExact) {
                return [PSCustomObject]@{
                    Type = "Winget"
                    Id = if ($wingetExact.id) { $wingetExact.id } else { $wingetExact.name }
                    FriendlyName = if ($wingetExact.friendly_name) { $wingetExact.friendly_name } else { if ($wingetExact.id) { $wingetExact.id } else { $wingetExact.name } }
                    Version = if ($wingetExact.version) { $wingetExact.version } else { "Latest" }
                }
            }

            $externalExact = $trackedJson.external_applications | Where-Object {
                $_.name -and $_.name -eq $dependencyName
            } | Select-Object -First 1
            if ($externalExact) {
                return [PSCustomObject]@{
                    Type = "External"
                    Id = $externalExact.name
                    FriendlyName = if ($externalExact.friendly_name) { $externalExact.friendly_name } else { $externalExact.name }
                    Version = if ($externalExact.version) { $externalExact.version } else { "Latest" }
                }
            }

            # Fallback to loose match for dependency names like "Git" vs "Git.Git"
            $wingetLoose = $trackedJson.winget_applications | Where-Object {
                ($_.id -and $_.id -match [regex]::Escape($dependencyName)) -or
                ($_.name -and $_.name -match [regex]::Escape($dependencyName)) -or
                ($_.friendly_name -and $_.friendly_name -match [regex]::Escape($dependencyName))
            } | Select-Object -First 1
            if ($wingetLoose) {
                return [PSCustomObject]@{
                    Type = "Winget"
                    Id = if ($wingetLoose.id) { $wingetLoose.id } else { $wingetLoose.name }
                    FriendlyName = if ($wingetLoose.friendly_name) { $wingetLoose.friendly_name } else { if ($wingetLoose.id) { $wingetLoose.id } else { $wingetLoose.name } }
                    Version = if ($wingetLoose.version) { $wingetLoose.version } else { "Latest" }
                }
            }

            $externalLoose = $trackedJson.external_applications | Where-Object {
                ($_.name -and $_.name -match [regex]::Escape($dependencyName)) -or
                ($_.friendly_name -and $_.friendly_name -match [regex]::Escape($dependencyName))
            } | Select-Object -First 1
            if ($externalLoose) {
                return [PSCustomObject]@{
                    Type = "External"
                    Id = $externalLoose.name
                    FriendlyName = if ($externalLoose.friendly_name) { $externalLoose.friendly_name } else { $externalLoose.name }
                    Version = if ($externalLoose.version) { $externalLoose.version } else { "Latest" }
                }
            }

            return $null
        }

        function Test-DependencyRequiredByUnselectedTrackedApps {
            param(
                [string]$dependencyName,
                [string]$resolvedDependencyId,
                [object]$trackedJson,
                [object]$configJson,
                [object]$selectedIdSet
            )

            if (-not $trackedJson -or -not $configJson) {
                return $false
            }

            $trackedApps = @()
            if ($trackedJson.winget_applications) {
                foreach ($wa in $trackedJson.winget_applications) {
                    $trackedApps += [PSCustomObject]@{
                        Type = "Winget"
                        Id = if ($wa.id) { $wa.id } else { $wa.name }
                    }
                }
            }
            if ($trackedJson.external_applications) {
                foreach ($ea in $trackedJson.external_applications) {
                    $trackedApps += [PSCustomObject]@{
                        Type = "External"
                        Id = $ea.name
                    }
                }
            }

            foreach ($tracked in $trackedApps) {
                if (-not $tracked -or [string]::IsNullOrWhiteSpace([string]$tracked.Id)) { continue }
                if ($selectedIdSet.Contains([string]$tracked.Id)) { continue }

                $cfg = $null
                if ($tracked.Type -eq "Winget") {
                    $cfg = $configJson.winget_applications | Where-Object { $_.id -eq $tracked.Id } | Select-Object -First 1
                } else {
                    $cfg = $configJson.external_applications | Where-Object { $_.name -eq $tracked.Id } | Select-Object -First 1
                }

                if (-not $cfg -or -not $cfg.dependencies) { continue }

                foreach ($dep in $cfg.dependencies) {
                    if (-not $dep -or -not $dep.name) { continue }
                    $otherDepName = [string]$dep.name
                    if ($otherDepName -eq $dependencyName -or $otherDepName -eq $resolvedDependencyId) {
                        return $true
                    }
                }
            }

            return $false
        }

        $selectedKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($pkg in $selectedPackages) {
            if ($pkg -and $pkg.Id) {
                [void]$selectedKeys.Add([string]$pkg.Id)
            }
        }

        $queue = New-Object System.Collections.ArrayList
        foreach ($pkg in $selectedPackages) { [void]$queue.Add($pkg) }
        $autoAddedLabels = @()

        while ($queue.Count -gt 0) {
            $current = $queue[0]
            $queue.RemoveAt(0)

            $deps = @()
            if ($current.Type -eq "Winget") {
                $cfg = $installJson.winget_applications | Where-Object { $_.id -eq $current.Id } | Select-Object -First 1
                if ($cfg -and $cfg.dependencies) { $deps = @($cfg.dependencies) }
            } else {
                $cfg = $installJson.external_applications | Where-Object { $_.name -eq $current.Id } | Select-Object -First 1
                if ($cfg -and $cfg.dependencies) { $deps = @($cfg.dependencies) }
            }

            foreach ($dep in $deps) {
                if (-not $dep -or -not $dep.name) { continue }
                $depName = [string]$dep.name

                if ($selectedKeys.Contains($depName)) {
                    continue
                }

                $trackedDep = Resolve-DependencyPackageFromTracked -dependencyName $depName -trackedJson $uninstallJson
                if ($trackedDep) {
                    # Check if this resolved dependency is already selected to prevent duplicates
                    if ($selectedKeys.Contains([string]$trackedDep.Id)) {
                        continue
                    }

                    $requiredElsewhere = Test-DependencyRequiredByUnselectedTrackedApps `
                        -dependencyName $depName `
                        -resolvedDependencyId ([string]$trackedDep.Id) `
                        -trackedJson $uninstallJson `
                        -configJson $installJson `
                        -selectedIdSet $selectedKeys

                    if ($requiredElsewhere) {
                        Write-ToLog -message "Skipping auto-uninstall of dependency '$($trackedDep.Id)' because it is still required by another tracked application not selected for uninstall." -log_file $log_file
                        continue
                    }

                    [void]$selectedKeys.Add([string]$trackedDep.Id)
                    $selectedPackages += $trackedDep
                    [void]$queue.Add($trackedDep)
                    $autoAddedLabels += "[$($trackedDep.Type)] $($trackedDep.Id)"
                }
            }
        }

        if ($autoAddedLabels.Count -gt 0) {
            $autoAddedUnique = $autoAddedLabels | Sort-Object -Unique
            Write-ToLog -message ("Auto-included dependency packages for uninstall: " + ($autoAddedUnique -join ", ")) -log_file $log_file
        }
    }

    $results.TotalPackages = $selectedPackages.Count

    # Dependency-aware uninstall ordering: uninstall dependents before their dependencies.
    if ($installJson -and $selectedPackages.Count -gt 1) {
        $remaining = @($selectedPackages)
        $ordered = @()

        while ($remaining.Count -gt 0) {
            $referencedDependencyNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

            foreach ($pkg in $remaining) {
                $deps = @()
                if ($pkg.Type -eq "Winget") {
                    $cfg = $installJson.winget_applications | Where-Object { $_.id -eq $pkg.Id } | Select-Object -First 1
                    if ($cfg -and $cfg.dependencies) { $deps = @($cfg.dependencies) }
                } else {
                    $cfg = $installJson.external_applications | Where-Object { $_.name -eq $pkg.Id } | Select-Object -First 1
                    if ($cfg -and $cfg.dependencies) { $deps = @($cfg.dependencies) }
                }

                foreach ($dep in $deps) {
                    if ($dep -and $dep.name) {
                        [void]$referencedDependencyNames.Add([string]$dep.name)
                    }
                }
            }

            $pick = $null
            foreach ($pkg in $remaining) {
                if (-not $referencedDependencyNames.Contains([string]$pkg.Id)) {
                    $pick = $pkg
                    break
                }
            }
            if ($null -eq $pick) {
                $pick = $remaining[0]
            }

            $ordered += $pick
            $remaining = @($remaining | Where-Object { -not ($_ -eq $pick) })
        }

        $selectedPackages = @($ordered)
        $orderedLabels = @($selectedPackages | ForEach-Object { "[$($_.Type)] $($_.Id)" })
        Write-ToLog -message ("Uninstall order after dependency resolution: " + ($orderedLabels -join " -> ")) -log_file $log_file
    }

    foreach ($package in $selectedPackages) {
        # Create app object from the package information in the datatable
        if ($package.Type -eq "Winget") {
            $app = [PSCustomObject]@{
                id = $package.Id
                friendly_name = $package.FriendlyName
                version = if ("Latest" -eq $package.Version) { $null } else { $package.Version }
            }
            $section = "winget_applications"
            $id = $package.Id
        } else {
            $app = [PSCustomObject]@{
                name = $package.Id
                friendly_name = $package.FriendlyName
                version = if ("Latest" -eq $package.Version) { $null } else { $package.Version }
            }
            $section = "external_applications"
            $id = $package.Id
        }
        
        # Look up full application details from uninstall.json so app-specific uninstall parameters are preserved
        if ($package.Type -eq "Winget") {
            $originalApp = $uninstallJson.winget_applications | Where-Object { $_.id -eq $app.id -or $_.name -eq $app.id } | Select-Object -First 1
            if ($originalApp) {
                $app = $originalApp
            }
        } elseif ($package.Type -eq "External") {
            $originalApp = $uninstallJson.external_applications | Where-Object { $_.name -eq $app.name } | Select-Object -First 1
            if ($originalApp) {
                $app = $originalApp
            }

            # Always source uninstall_command from applications.json for external apps.
            if ($installJson -and $installJson.external_applications) {
                $sourceExternalApp = $installJson.external_applications | Where-Object { $_.name -eq $app.name } | Select-Object -First 1
                if ($sourceExternalApp) {
                    $app.uninstall_command = $sourceExternalApp.uninstall_command
                    Write-ToLog -message "Sourced uninstall_command from applications.json for $($app.name)" -log_file $log_file
                } else {
                    Write-ToLog -message "Warning: External app '$($app.name)' not found in applications.json during uninstall." -log_file $log_file
                }
            }
        }
        
        try {
            # Route by selected package type, not by whether a property exists.
            # External rows can be missing uninstall_command in the UI object and must not fall back to winget.
            if ($package.Type -and $package.Type.ToString().ToLower() -eq "external") {
                $success = Uninstall-ExternalApplication -app $app -log_file $log_file
            } else {
                $success = Uninstall-WingetApplication -app $app -log_file $log_file -global_uninstall_flags $globalUninstallFlags
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
        [string]$log_file,
        [string]$global_uninstall_flags
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

    # Construct arguments for winget uninstallation using global flags from uninstall.json when available
    $resolvedGlobalFlags = if (-not [string]::IsNullOrWhiteSpace($global_uninstall_flags)) {
        $global_uninstall_flags
    } else {
        "--purge --accept-source-agreements --silent --disable-interactivity --force"
    }

    $arguments = @("uninstall")
    $globalFlagParts = $resolvedGlobalFlags -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($globalFlagParts.Count -gt 0 -and $globalFlagParts[0].ToLower() -eq "uninstall") {
        $globalFlagParts = $globalFlagParts | Select-Object -Skip 1
    }
    $arguments += $globalFlagParts
    
    # Add the application ID
    $arguments += @("--id", $appIdentifier)
    $hasUninstallOverride = $false
    
    # Add uninstall override flags only when supported by installed winget.
    if ($app.uninstall_override_flags) {
        $supportsUninstallOverride = Test-WingetUninstallOverrideSupport
        if ($supportsUninstallOverride) {
            $hasUninstallOverride = $true
            $arguments += @("--override", [string]$app.uninstall_override_flags)
            Write-ToLog -message "Using custom uninstall override flags for ${appDisplayName}: $($app.uninstall_override_flags)" -log_file $log_file
        }
        else {
            Write-ToLog -message "Installed winget does not support '--override' for uninstall. Proceeding without uninstall override flags for ${appDisplayName}." -log_file $log_file
        }
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

        # If uninstall override flags are rejected by winget/installer, retry once without override flags.
        if ($hasUninstallOverride -and $exit_code -eq -1978335230) {
            Write-ToLog -message "Uninstall override flags for ${appDisplayName} were rejected (exit code: $exit_code). Retrying uninstall without override flags." -log_file $log_file

            $retryArguments = @("uninstall")
            $retryArguments += $globalFlagParts
            $retryArguments += @("--id", $appIdentifier)

            $retryCommandStr = "winget $($retryArguments -join ' ')"
            Write-ToLog -message "Retrying command: $retryCommandStr" -log_file $log_file

            $retryProcess = Start-Process -FilePath winget -ArgumentList $retryArguments -PassThru -Wait -NoNewWindow
            $exit_code = $retryProcess.ExitCode
        }
        
        $uninstallSuccess = Test-UninstallationSuccess -exit_code $exit_code -app_name $appDisplayName -log_file $log_file
        
        # Remove persistent environment variables if uninstall was successful
        if ($uninstallSuccess) {
            Remove-PersistentEnvironmentVariables -app $app -log_file $log_file
        }
        
        return $uninstallSuccess
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

    $registryEntry = $null
    $displayPatterns = @()
    if (-not [string]::IsNullOrWhiteSpace([string]$app.friendly_name)) { $displayPatterns += [string]$app.friendly_name }
    if (-not [string]::IsNullOrWhiteSpace([string]$app.name)) { $displayPatterns += [string]$app.name }

    $registryKeys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($key in $registryKeys) {
        if ($registryEntry) { break }
        $candidates = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        foreach ($pattern in $displayPatterns) {
            $match = $candidates | Where-Object { $_.DisplayName -and $_.DisplayName -like ("*" + $pattern + "*") } | Select-Object -First 1
            if ($match) {
                $registryEntry = $match
                break
            }
        }
    }

    $effectiveUninstallCommand = [string]$app.uninstall_command

    if ([string]::IsNullOrWhiteSpace($effectiveUninstallCommand)) {
        Write-ToLog -message "Error: No uninstall_command provided for $appDisplayName in applications.json. Marking uninstall as failed." -log_file $log_file
        return $false
    }

    Write-ToLog -message "Uninstalling external application: $appDisplayName" -log_file $log_file
    Write-ToLog -message "Using command: $effectiveUninstallCommand" -log_file $log_file

    $resolvedUninstallCommand = [Environment]::ExpandEnvironmentVariables([string]$effectiveUninstallCommand)
    Write-ToLog -message "Resolved command: $resolvedUninstallCommand" -log_file $log_file

    $regex = '^\s*"?([^"]+\.exe)"?\s*(.*)$' # Match quoted or unquoted .exe command paths
    if ($resolvedUninstallCommand -match $regex) {
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
            
            $successExitCodes = @(0, 3010, 1641)
            $registryStillPresent = $false
            if ($registryEntry -or $displayPatterns.Count -gt 0) {
                foreach ($key in $registryKeys) {
                    $items = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
                    foreach ($pattern in $displayPatterns) {
                        if ($items | Where-Object { $_.DisplayName -and $_.DisplayName -like ("*" + $pattern + "*") } | Select-Object -First 1) {
                            $registryStillPresent = $true
                            break
                        }
                    }
                    if ($registryStillPresent) { break }
                }
            }

            if (($successExitCodes -contains $exit_code) -and (-not $registryStillPresent)) {
                Remove-PersistentEnvironmentVariables -app $app -log_file $log_file
                return $true
            }

            if (($successExitCodes -contains $exit_code) -and $registryStillPresent) {
                Write-ToLog -message "Uninstaller returned success code $exit_code but registry entry still exists for $appDisplayName. Treating as failure." -log_file $log_file
                return $false
            }

            Write-ToLog -message "Uninstallation failed for $appDisplayName with exit code $exit_code" -log_file $log_file
            return $false
        }
        catch {
            Write-ToLog -message "Error during uninstallation of external application ${appDisplayName}: $_" -log_file $log_file
            return $false
        }
    }
    else {
        # Non-exe command (e.g. npm uninstall -g npm) — run via cmd.exe /c,
        # the same pattern used by Install-ExternalApplication for install_command
        $resolvedCommandToRun = $resolvedUninstallCommand

        # Node.js may be uninstalled in the same flow; use absolute npm.cmd path fallback.
        if ($resolvedCommandToRun -match '^\s*npm(\s|$)') {
            $npmCmdPath = $null
            try {
                $npmCmd = Get-Command npm -ErrorAction Stop
                if ($npmCmd -and $npmCmd.Source) {
                    $npmCmdPath = $npmCmd.Source
                }
            }
            catch {}

            if (-not $npmCmdPath) {
                $candidatePaths = @(
                    (Join-Path $env:ProgramFiles 'nodejs\npm.cmd'),
                    (Join-Path ${env:ProgramFiles(x86)} 'nodejs\npm.cmd')
                )
                foreach ($candidate in $candidatePaths) {
                    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -Path $candidate)) {
                        $npmCmdPath = $candidate
                        break
                    }
                }
            }

            if ($npmCmdPath) {
                $resolvedCommandToRun = $resolvedCommandToRun -replace '^\s*npm(?=\s|$)', ('"' + $npmCmdPath + '"')
                Write-ToLog -message "Resolved npm command path for ${appDisplayName}: $npmCmdPath" -log_file $log_file
            }
        }

        Write-ToLog -message "Running uninstall command via cmd for ${appDisplayName}: $resolvedCommandToRun" -log_file $log_file
        try {
            $process = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", $resolvedCommandToRun) -PassThru -Wait -NoNewWindow
            $exit_code = $process.ExitCode
            Write-ToLog -message "Uninstall command for ${appDisplayName} completed with exit code: $exit_code" -log_file $log_file
            
            # Define success exit codes; VS Code extension uninstall returns 1 when extension not found (treat as success)
            $successExitCodes = @(0, 3010, 1641)
            if ($resolvedCommandToRun -match '^\s*code\s+--uninstall-extension') {
                $successExitCodes = @(0, 1, 3010, 1641)  # Exit code 1 = extension not found (expected behavior)
            }
            
            if ($successExitCodes -contains $exit_code) {
                Remove-PersistentEnvironmentVariables -app $app -log_file $log_file
                return $true
            }
            Write-ToLog -message "Uninstall command for ${appDisplayName} failed with exit code: $exit_code" -log_file $log_file
            return $false
        }
        catch {
            Write-ToLog -message "Error running uninstall command for ${appDisplayName}: $_" -log_file $log_file
            return $false
        }
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

    # Load applications.json so external uninstall commands are sourced from the single source of truth.
    $installJson = $null
    try {
        $installJsonPath = Join-Path -Path (Split-Path $PSScriptRoot -Parent) -ChildPath "JSON\install\applications.json"
        if (Test-Path -Path $installJsonPath) {
            $installJson = Get-Content -Path $installJsonPath -Raw | ConvertFrom-Json
        }
    }
    catch {
        Write-ToLog -message "Warning: Could not load applications.json for batch uninstall command lookup: $($_.Exception.Message)" -log_file $uninstall_log_file
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
    $globalUninstallFlags = if ($applications.PSObject.Properties.Name -contains "global_uninstall_flags") { $applications.global_uninstall_flags } else { $null }

    if ($applications.winget_applications -and $applications.winget_applications.Count -gt 0) {
        Write-Host "Uninstalling $($applications.winget_applications.Count) winget applications..." -ForegroundColor Cyan
        Write-ToLog -message "Uninstalling $($applications.winget_applications.Count) winget applications" -log_file $uninstall_log_file
        
        foreach ($app in $applications.winget_applications) {
            $appName = if ($app.friendly_name) { $app.friendly_name } else { if ($app.id) { $app.id } else { $app.name } }
            Write-Host "Uninstalling winget application: $appName" -ForegroundColor Cyan
            
            $success = Uninstall-WingetApplication -app $app -log_file $uninstall_log_file -global_uninstall_flags $globalUninstallFlags
            if ($success) {
                $successfulWingetUninstalls++
                # Remove from uninstall.json immediately after uninstall
                Remove-FromJsonById -jsonFilePath $json_uninstall_file_path -section "winget_applications" -id $app.id
                Write-Host "Successfully uninstalled and removed from tracking: $appName" -ForegroundColor DarkGreen
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

            if ($installJson -and $installJson.external_applications) {
                $sourceExternalApp = $installJson.external_applications | Where-Object { $_.name -eq $app.name } | Select-Object -First 1
                if ($sourceExternalApp) {
                    $app.uninstall_command = $sourceExternalApp.uninstall_command
                    Write-ToLog -message "Sourced uninstall_command from applications.json for $($app.name)" -log_file $uninstall_log_file
                } else {
                    Write-ToLog -message "Warning: External app '$($app.name)' not found in applications.json during batch uninstall." -log_file $uninstall_log_file
                }
            }
            
            $success = Uninstall-ExternalApplication -app $app -log_file $uninstall_log_file
            if ($success) {
                $successfulExternalUninstalls++
                # Remove from uninstall.json immediately after uninstall
                Remove-FromJsonById -jsonFilePath $json_uninstall_file_path -section "external_applications" -id $app.name
                Write-Host "Successfully uninstalled and removed from tracking: $appName" -ForegroundColor DarkGreen
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
    
    # Copy uninstall logs to desktop
    $username = [Environment]::UserName
    $desktopPath = "C:\Users\$username\Desktop\uninstall_logs.txt"
    try {
        Copy-Item -Path $uninstall_log_file -Destination $desktopPath -Force
        Write-Host "`nUninstall logs copied to desktop: $desktopPath" -ForegroundColor Green
    } catch {
        Write-Host "Warning: Could not copy uninstall logs to desktop: $_" -ForegroundColor Yellow
    }
}
