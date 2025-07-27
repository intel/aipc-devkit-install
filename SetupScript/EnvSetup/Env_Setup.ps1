# This script is designed to set up a development environment on Windows using winget.
# It installs or updates a list of applications, including Visual Studio, Python, and others.
# It also sets the execution policy to Unrestricted to allow script execution.
# **********************************************#
# IMPORTANT: This script must be run from an elevated PowerShell prompt.
# Usage:
# Set-ExecutionPolicy -ExecutionPolicy Unrestricted LocalMachine
# ./Env_Setup.ps1 install -> Installs software
# ./Env_Setup.ps1 uninstall -> Uninstalls software
# ***************************************** #
<#
   Contact: 
    Vijay (vijay.chandrashekar@intel.com) 
    Ram (vaithi.s.ramadoss@intel.com)
#>
param(
    [string]$command # Accepts a command parameter to determine whether to install or uninstall applications
)
<#
    Global variables
#>
# If external = $true, this means the script is for the customer, meaning they must accept the EULA pop-up
# If external = $false, this means it is "internal", the user will NOT have to accept the EULA pop-up
# By switching this to false YOU acknowledge that this script will NOT be provided toward customers to be used on their own personal machines
$Global:external = $false # Indicates whether the script is for external use, affecting EULA acceptance
$task_name = "AIPCCloud ENV Setup" # Name of the scheduled task for environment setup

Set-Location -Path $PSScriptRoot # Sets the current directory to the script's location
$logs_dir = ".\logs" # Directory for storing log files
$json_dir = ".\json" # Directory for storing JSON files

# Source helper scripts
. ".\Public\Write_ToLog.ps1" # Sources a script for logging messages
. ".\Public\Append-ToJson.ps1" # Sources a script for appending data to JSON files
. ".\Public\Pre_Req.ps1" # Sources a script for checking pre-requisites

<#
    Initializes logs for installation
#>
function Setup-Directory([string]$location) {
    if (-not (Test-Path -Path $location)) {
        New-Item -Path $location -ItemType Directory | Out-Null # Creates a directory if it doesn't exist
    }
}


<#
    Creates a file at the given location
#>
function  Setup-File([string]$location) {
    if (-not (Test-Path -Path $location)) {
        New-Item -Path $location -ItemType File | Out-Null # Creates a file if it doesn't exist
    }
}


<#
    Calls script for user to accept EULA agreements for ALL software this script installs
    Returns true if they accept, false otherwise
#>
function Accept-Eula() {
    # Source Script
    $run_once = ".\Public\Run_Once_Eula.ps1" # Path to the EULA acceptance script
    & $run_once # Executes the EULA acceptance script
    return $? # Returns the exit status of the EULA script
}

<#
    Checks if winget installation was successful based on exit code
#>
function Test-InstallationSuccess([int]$exitCode) {
    # Winget exit codes: 0 = success, -1978335212 = already installed, others = failure
    return ($exitCode -eq 0 -or $exitCode -eq -1978335212)
}



try {


    # Log directory structure
    $install_logs_dir = "$logs_dir\install" # Directory for installation logs
    $uninstall_logs_dir = "$logs_dir\uninstall" # Directory for uninstallation logs
    $error_logs_dir = "$logs_dir\error" # Directory for error logs

    # Logs text file locations
    $install_log_file = "$install_logs_dir\install_log.txt" # File for installation logs
    $uninstall_log_file = "$uninstall_logs_dir\uninstall.txt" # File for uninstallation logs
    $error_log_file = "$error_logs_dir\error_log.txt" # File for error logs

    # Json file structure
    $json_install_dir = "$json_dir\install" # Directory for installation JSON files
    $json_uninstall_dir = "$json_dir\uninstall" # Directory for uninstallation JSON files
    $json_install_file_path = "$json_install_dir\applications.json" # Path to the installation JSON file
    $json_uninstall_file_path = "$json_uninstall_dir\uninstall.json" # Path to the uninstallation JSON file

    # ============================== Reading JSON and organizing items =====================

    # Read items from applications.json 

    if ($command -eq "install") {

        # Setup logging directories and files
        Setup-Directory $install_logs_dir
        Setup-Directory $error_logs_dir
        Setup-File $install_log_file
        Setup-File $error_log_file

        # Setup uninstall json file
        Setup-Directory $json_uninstall_dir


        # Check for pre-requsites
        $pre_req = Check-PreReq # Calls a function to check pre-requisites
        if ($pre_req) {
            Write-ToLog -message "All pre-requisites complete. Installing." -log_file $install_log_file
        }
        else {
            Write-ToLog -message "Pre-requisites not met. Exiting." -log_file $install_log_file
            Write-Host "Pre-requisites not met. Exiting." -ForegroundColor Red
            exit 1 # Exits the script if pre-requisites are not met
        }

        # If running externally, have user agree to EULA pop-up
        if ($Global:external) {
          
            if (-not (Accept-Eula)) {
                Write-Host "Eula not accepted. Exiting." -ForegroundColor Red
                Write-ToLog -message "Eula not accepted. Exiting." -log_file $install_log_file
                exit 1 # Exits the script if EULA is not accepted
            }
            else {
                Write-Host "Eula accepted. Proceeding." -ForegroundColor Green
                $host_name = hostname
                Write-ToLog -message "Hostname: $host_name has accepted the EULA Agreement" -log_file $install_log_file
            }
        }

        $applications = Get-Content -Path $json_install_file_path -Raw | ConvertFrom-Json # Reads and parses the JSON file

        # Print out which items are going to be downloaded
        Write-Host "Preparing to install the following applications:" -ForegroundColor Yellow
        foreach ($app in $applications.winget_applications) {
            Write-Host "- $($app.name) - Source: Winget" -ForegroundColor Green
            if ($null -ne $app.dependencies) {
                Write-Host "  Dependencies:" -ForegroundColor Blue
                foreach ($dep in $app.dependencies) {
                    Write-Host "    - $($dep.name) v$($dep.version)" -ForegroundColor Blue
                }
            }
        }

        Write-Host "Additional external applications"
        foreach ($app in $applications.external_applications) {
            Write-Host "- $($app.name) - Source: External" -ForegroundColor Green
            if ($null -ne $app.dependencies) {
                Write-Host "  Dependencies:" -ForegroundColor Blue
                foreach ($dep in $app.dependencies) {
                    Write-Host "    - $($dep.name) v$($dep.version)" -ForegroundColor Blue
                }
            }
        }

        # Prep winget so no hanging
        winget list --accept-source-agreements > $null 2>&1 # Prepares winget by accepting source agreements

        $winget_list = Get-WinGetPackage # Retrieves the list of installed winget packages


        # Initialize lists to track installed applications
        $data = @{
            winget_applications   = @() # List to track installed winget applications
            external_applications = @() # List to track installed external applications
        }

        # Check dependencies
        foreach ($app in $applications.winget_applications) {
            if ($null -ne $app.dependencies) {
                foreach ($dep in $app.dependencies) {
                    $depName = $dep.name
                    $depVersion = $dep.version

                    # Check if dependency is already in the list of applications to install
                    $dependencyApp = $applications.winget_applications | Where-Object { $_.name -match $depName }

                    if ($null -eq $dependencyApp) {
                        # Check if dependency is already installed on the system
                        $isInstalled = $winget_list | Where-Object { $_.Name -match $depName }

                        if ($null -eq $isInstalled) {
                            Write-Host "Dependency $depName required for $($app.name) is not installed and not in the install list. Skipping $($app.name)" -ForegroundColor Yellow
                            # Remove the application from the list if its dependency can't be met
                            $applications.winget_applications = $applications.winget_applications | Where-Object { $_.name -ne $app.name }
                        } 
                    }
                }
            }
        }

        # Download each winget application
        foreach ($app in $applications.winget_applications) {
            $app_name = $app.name
            $global_install_flags = $applications.global_install_flags

            # Construct arguments for winget installation
            $arguments = @("install")
            $arguments += @("$global_install_flags")
            if ($app.name) {
                $arguments += @("--id $($app.name)")
            }
            if ($app.version) {
                $arguments += @("-v $($app.version)")
            }
            if ($app.install_location) {
                $arguments += @("-l $($app.install_location)")
            }
            if ($app.override_flags) {
                $arguments += @("--override `"$($app.override_flags)`"")
            }

            Write-ToLog -message "Installing $app_name" -log_file $install_log_file
            $process = Start-Process -FilePath winget -ArgumentList $arguments -NoNewWindow -PassThru -Wait
            $process.WaitForExit()
            $exit_code = $process.ExitCode
            Write-ToLog -message "$app_name finished installing with exit code: $exit_code" -log_file $install_log_file

            # Only add to uninstall list if installation was successful
            if (Test-InstallationSuccess -exitCode $exit_code) {
                # Add to installed list and append immediately for real-time tracking
                $appData = @{
                    name    = $app_name
                    version = $app.version
                }
                
                # Include uninstall override flags if they exist
                if ($app.uninstall_override_flags) {
                    $appData.uninstall_override_flags = $app.uninstall_override_flags
                }
                
                $data.winget_applications = @($appData)
                $data.external_applications = @()

                AppendToJson -json_location $json_uninstall_file_path -data $data
                Write-ToLog -message "$app_name successfully installed and added to uninstall list" -log_file $install_log_file
                Write-Host "Successfully installed and tracked: $app_name" -ForegroundColor Green
                Write-Host "Uninstall JSON location: $json_uninstall_file_path" -ForegroundColor Cyan
            } else {
                Write-ToLog -message "$app_name installation failed with exit code $exit_code - not added to uninstall list" -log_file $install_log_file
                Write-Host "Failed to install $app_name (exit code: $exit_code)" -ForegroundColor Red
            }
        }

        # Download external apps
        foreach ($app in $applications.external_applications) {
            $file_name = $app.name + ".exe"
                
            if (-not (Test-Path -Path $app.download_location)) {
                New-Item -Path $app.download_location -ItemType Directory # Creates the download directory if it doesn't exist
            }

            $arguments = @("-L", $app.source, "-o", "$($app.download_location)\$file_name") # Constructs arguments for downloading external applications
               
            Write-ToLog -message "Installing $($app.name)" -log_file $install_log_file
            $process = Start-Process -FilePath "curl.exe" -ArgumentList "$arguments" -PassThru -NoNewWindow -Wait
            $process.WaitForExit()

            $arguments = @("$($app.install_flags)") # Constructs arguments for installing external applications
            $exec_path = "$($app.download_location)\$file_name"
            $process = Start-Process -FilePath $exec_path -ArgumentList $arguments -PassThru -Wait -NoNewWindow
            $process.WaitForExit()
            $exit_code = $process.ExitCode

            Write-ToLog -message "Finished installing $($app.name) with exit code $exit_code" -log_file $install_log_file

            # Only add to uninstall list if installation was successful (exit code 0)
            if ($exit_code -eq 0) {
                # Add to installed list and append immediately for real-time tracking
                $data.winget_applications = @()
                $data.external_applications = @(@{
                    name              = $app.name
                    download_location = $app.download_location
                    uninstall_command = $app.uninstall_command
                })

                AppendToJson -json_location $json_uninstall_file_path -data $data
                Write-ToLog -message "$($app.name) successfully installed and added to uninstall list" -log_file $install_log_file
            } else {
                Write-ToLog -message "$($app.name) installation failed with exit code $exit_code - not added to uninstall list" -log_file $install_log_file
                Write-Host "Failed to install $($app.name) (exit code: $exit_code)" -ForegroundColor Red
            }
        }

        # Copy install logs to desktop
        $username = [Environment]::UserName
        Copy-Item -Path $install_log_file -Destination "C:\Users\$username\Desktop\install_logs.txt" # Copies the install log to the user's desktop

        # Check if uninstall.json was created and show summary
        if (Test-Path -Path $json_uninstall_file_path) {
            Write-Host "Uninstall.json created successfully at: $json_uninstall_file_path" -ForegroundColor Green
            $uninstallData = Get-Content -Path $json_uninstall_file_path -Raw | ConvertFrom-Json
            $wingetCount = if ($uninstallData.winget_applications) { $uninstallData.winget_applications.Count } else { 0 }
            $externalCount = if ($uninstallData.external_applications) { $uninstallData.external_applications.Count } else { 0 }
            Write-Host "Tracked for uninstall: $wingetCount winget apps, $externalCount external apps" -ForegroundColor Yellow
        } else {
            Write-Host "Warning: Uninstall.json was not created!" -ForegroundColor Red
        }

        if (-not $Global:external) {
            # Check if the scheduled task exists before trying to unregister it
            try {
                $existingTask = Get-ScheduledTask -TaskName $task_name -ErrorAction SilentlyContinue
                if ($existingTask) {
                    Unregister-ScheduledTask -TaskName $task_name -Confirm:$false
                    Write-ToLog -message "Successfully unregistered scheduled task: $task_name" -log_file $install_log_file
                } else {
                    Write-ToLog -message "Scheduled task '$task_name' not found - nothing to unregister" -log_file $install_log_file
                }
            }
            catch {
                Write-ToLog -message "Failed to unregister scheduled task: $($_.Exception.Message)" -log_file $install_log_file
                Write-Host "Warning: Could not unregister scheduled task '$task_name'" -ForegroundColor Yellow
            }
        }
    }
    elseif ($command -eq "uninstall") {
        if (-not (Test-Path -Path $json_uninstall_file_path)) {
            Write-Host "No Uninstall file specified. Please run installer first" -ForegroundColor Red
            exit # Exits if the uninstall JSON file does not exist
        }

        # Setup uninstall logs
        Setup-Directory $uninstall_logs_dir
        Setup-File $uninstall_log_file

        $applications = Get-Content -Path $json_uninstall_file_path -Raw | ConvertFrom-Json # Reads and parses the uninstall JSON file

        foreach ($app in $applications.winget_applications) {
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
                Write-ToLog -message "Using custom uninstall override flags for $($app.name): $($app.uninstall_override_flags)" -log_file $uninstall_log_file
            }

            Write-ToLog -message "Uninstalling $($app.name)" -log_file $uninstall_log_file
            
            # Set comprehensive environment variables to suppress ALL UI elements
            $env:WINGET_DISABLE_INTERACTIVITY = "1"
            $env:WINGET_DISABLE_UPGRADE_PROMPTS = "1"
            $env:WINGET_DISABLE_CONFIRMATION = "1"
            $env:SILENT = "1"
            $env:QUIET = "1"
            
            $process = Start-Process -FilePath winget -ArgumentList $arguments -PassThru -Wait -NoNewWindow
            $process.WaitForExit() 
            $exit_code = $process.ExitCode
            Write-ToLog -message "Finished uninstalling $($app.name) with exit code $exit_code" -log_file $uninstall_log_file
        }

        foreach ($app in $applications.external_applications) {
            $regex = "([a-zA-Z]:.*.exe)(.*)" # Regex to match the uninstall command
            if ($app.uninstall_command -match $regex) {
                $command = $matches[1]
                $arguments_unsplit = $matches[2]
                $arguments_split = $arguments_unsplit -split '\s+' | Where-Object { $_ -ne "" } # Splits the arguments for the uninstall command

                Write-ToLog -message "Uninstalling $($app.name)" -log_file $uninstall_log_file
                $process = Start-Process -FilePath $command -ArgumentList $arguments_split -PassThru -Wait -NoNewWindow
                $process.WaitForExit()
                $exit_code = $process.ExitCode
                Write-ToLog -message "Uninstalled $($app.name) with exit code $exit_code" -log_file $uninstall_log_file
            }
        }

        # Remove JSON uninstall folder
        Remove-Item -Path $json_uninstall_dir -Recurse # Deletes the uninstall JSON directory
    }
    else {
        $help_str = 
        @"
            Usage:
                - install
                    Installs all software specified in applications.json, checking for dependencies
                - uninstall
                    Uninstalls all software specified in uninstall.json
"@
        Write-Host $help_str -ForegroundColor Red # Displays usage instructions if the command is invalid
    }
}
catch {
    Write-ToLog -message $_.Exception.Message -log_file $error_log_file # Logs any exceptions that occur
    Write-Host "$($_.Exception.Message)" -ForegroundColor Red # Displays the exception message
    Write-Host "An error occurred during installation. See error log files" -ForegroundColor Red # Informs the user of an error
    #Write-Host $Error[0].ScriptStackTrace # Optionally displays the script stack trace
}
