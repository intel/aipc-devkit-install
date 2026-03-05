<# Intel Confidential

.SYNOPSIS
    Dynatrace OneAgent Configuration Script - Run Once After Windows Installation
.DESCRIPTION
    This Script sets the mandatory settings of dynatrace OneAgent host to monitoring mode and sets changes to 
    map to IAPM ID of AIPC Cloud. 
.PREREQUISITES
    Dynatrace executables are preinstalled on the client machine.
.PARAMETER None
.PRE-REQUISITES
    PowerShell 5.1 or higher
    Dynatrace production binary installed at "C:\Program Files\dynatrace" (default location)

.Notes:
    - The script must be run with Administrator privileges.
    - The script creates a registry entry to track completion and avoid re-execution.
    - Logs are stored at "C:\Program Files\dynatrace\scripts\logs\DynatraceConfig.log".

Contacts: vijay.chandrashekar@intel.com for any questions or issues.

#>

# Check if powershell is running as Administrator and self-elevate if needed
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-ElevatedProcess {
    param([string]$ScriptPath)
    
    try {
        Write-Host "Script requires elevation. Attempting to restart with administrator privileges..." -ForegroundColor Yellow
        
        $arguments = "-ExecutionPolicy Bypass -File `"$ScriptPath`""
        Start-Process -FilePath "PowerShell.exe" -ArgumentList $arguments -Verb RunAs -Wait
        
        Write-Host "Elevated process completed." -ForegroundColor Green
        exit 0
    }
    catch {
        Write-Host "Failed to elevate script: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Please run this script as Administrator manually." -ForegroundColor Red
        exit 1
    }
}

# Elevation check - must be at the top of the script
if (-NOT (Test-Administrator)) {
    Write-Host "Current user is not an administrator. Elevation required." -ForegroundColor Red
    
    # Get the current script path
    $CurrentScript = $MyInvocation.MyCommand.Path
    if ($CurrentScript) {
        Start-ElevatedProcess -ScriptPath $CurrentScript
    }
    else {
        Write-Host "Cannot determine script path for elevation. Please run as Administrator." -ForegroundColor Red
        exit 1
    }
}

Write-Host "Running with Administrator privileges." -ForegroundColor Green

# Registry paths
$TrackingRegistryPath = "HKLM:\SOFTWARE\Intel\DynatraceConfig"
$RegistryValueName = "DynatraceConfigCompleted"
$LogPath = "C:\Program Files\dynatrace\scripts\logs\DynatraceConfig.log"

# Create log directory if it doesn't exist
$LogDirectory = Split-Path -Path $LogPath -Parent
if (!(Test-Path -Path $LogDirectory)) {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
}

# Function to write log with color coding
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $Timestamp = Get-Date -Format "dd-MMM-yyyy HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    
    # Write to log file
    Add-Content -Path $LogPath -Value $LogEntry -ErrorAction SilentlyContinue
    
    # Write to console with color coding
    switch ($Level.ToUpper()) {
        "ERROR" { 
            Write-Host $LogEntry -ForegroundColor Red 
        }
        "SUCCESS" { 
            Write-Host $LogEntry -ForegroundColor Green 
        }
        "WARNING" { 
            Write-Host $LogEntry -ForegroundColor Yellow 
        }
        "INFO" { 
            Write-Host $LogEntry -ForegroundColor Cyan 
        }
        default { 
            Write-Host $LogEntry -ForegroundColor White 
        }
    }
}

# Function to create registry entry
function Set-RegistryFlag {
    try {
        # Create registry path if it doesn't exist
        if (!(Test-Path $TrackingRegistryPath)) {
            New-Item -Path $TrackingRegistryPath -Force | Out-Null
            Write-Log "Created registry path: $TrackingRegistryPath" -Level "SUCCESS"
        }
        
        # Set completion flag
        Set-ItemProperty -Path $TrackingRegistryPath -Name $RegistryValueName -Value 1 -Type DWord
        Write-Log "Registry flag set successfully" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to set registry flag: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Function to check if script has already run
function Test-AlreadyRun {
    try {
        if (Test-Path $TrackingRegistryPath) {
            $Value = Get-ItemProperty -Path $TrackingRegistryPath -Name $RegistryValueName -ErrorAction SilentlyContinue
            if ($Value.$RegistryValueName -eq 1) {
                return $true
            }
        }
        return $false
    }
    catch {
        Write-Log "Error checking registry: $($_.Exception.Message)" -Level "WARNING"
        return $false
    }
}

# Function to validate proxy configuration
function Test-ProxyConfiguration {
    param($OneAgentCtl)
    
    try {
        Write-Log "Validating current proxy configuration..." -Level "INFO"
        $ProxyResult = & $OneAgentCtl --get-proxy 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            # Check if proxy is empty or not set
            if ([string]::IsNullOrWhiteSpace($ProxyResult) -or $ProxyResult -match "no proxy|not set|empty") {
                Write-Log "Proxy validation passed: No proxy is currently configured" -Level "SUCCESS"
                return $true
            }
            else {
                Write-Log "Proxy validation failed: Proxy is currently set to '$ProxyResult'" -Level "ERROR"
                Write-Log "Proxy must be empty/unset before proceeding with configuration" -Level "ERROR"
                return $false
            }
        }
        else {
            Write-Log "Warning: Could not retrieve current proxy configuration. Exit code: $LASTEXITCODE" -Level "WARNING"
            Write-Log "Proxy check output: $ProxyResult" -Level "WARNING"
            # Continue with configuration as we cannot determine current state
            return $true
        }
    }
    catch {
        Write-Log "Exception during proxy validation: $($_.Exception.Message)" -Level "WARNING"
        # Continue with configuration as we cannot determine current state
        return $true
    }
}

# Function to execute Dynatrace commands
function Invoke-DynatraceConfiguration {
    $DynatracePath = "C:\Program Files\dynatrace\oneagent\agent\tools"
    $OneAgentCtl = Join-Path $DynatracePath "oneagentctl.exe"
    
    # Check if Dynatrace is installed
    if (!(Test-Path $OneAgentCtl)) {
        Write-Log "Dynatrace OneAgent not found at: $OneAgentCtl" -Level "ERROR"
        Write-Log "Please ensure Dynatrace OneAgent is installed before running this script" -Level "ERROR"
        return $false
    }
    
    Write-Log "Found Dynatrace OneAgent at: $OneAgentCtl" -Level "SUCCESS"
    
    # Change to Dynatrace directory
    try {
        Set-Location $DynatracePath
        Write-Log "Changed directory to: $DynatracePath" -Level "INFO"
    }
    catch {
        Write-Log "Failed to change directory to: $DynatracePath - $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
    
    # Validate proxy configuration before proceeding
    if (!(Test-ProxyConfiguration -OneAgentCtl $OneAgentCtl)) {
        Write-Log "Proxy validation failed. Cannot proceed with configuration." -Level "ERROR"
        return $false
    }
    
    $Success = $true
    
    # Command 1: Set host group
    try {
        Write-Log "Executing: Set host group to 43139_prod" -Level "INFO"
        $Result1 = & $OneAgentCtl --set-host-group=43139_prod --restart-service 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Successfully set host group to 43139_prod" -Level "SUCCESS"
            Write-Log "Command output: $Result1" -Level "INFO"
        }
        else {
            Write-Log "Failed to set host group. Exit code: $LASTEXITCODE" -Level "ERROR"
            Write-Log "Command output: $Result1" -Level "ERROR"
            $Success = $false
        }
    }
    catch {
        Write-Log "Exception while setting host group: $($_.Exception.Message)" -Level "ERROR"
        $Success = $false
    }
    
    # Command 2: Set monitoring mode (run only if first command succeeded)
    if ($Success) {
        try {
            Write-Log "Executing: Set monitoring mode to Infra" -Level "INFO"
            $Result2 = & $OneAgentCtl --set-monitoring-mode=infra-only --restart-service 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Successfully set monitoring mode to Infra Only" -Level "SUCCESS"
                Write-Log "Command output: $Result2" -Level "INFO"
            }
            else {
                Write-Log "Failed to set monitoring mode. Exit code: $LASTEXITCODE" -Level "ERROR"
                Write-Log "Command output: $Result2" -Level "ERROR"
                $Success = $false
            }
        }
        catch {
            Write-Log "Exception while setting monitoring mode: $($_.Exception.Message)" -Level "ERROR"
            $Success = $false
        }
    }
    else {
        Write-Log "Skipping monitoring mode configuration due to previous failure" -Level "WARNING"
    }
    
    # Command 3: Clear proxy settings (run only if previous commands succeeded)
    if ($Success) {
        try {
            Write-Log "Executing: Clear proxy settings" -Level "INFO"
            $Result3 = & $OneAgentCtl --set-proxy= --restart-service 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Successfully cleared proxy settings" -Level "SUCCESS"
                Write-Log "Command output: $Result3" -Level "INFO"
                
                # Verify proxy is now empty
                Write-Log "Verifying proxy configuration after clearing..." -Level "INFO"
                $VerifyResult = & $OneAgentCtl --get-proxy 2>&1
                if ($LASTEXITCODE -eq 0) {
                    if ([string]::IsNullOrWhiteSpace($VerifyResult) -or $VerifyResult -match "no proxy|not set|empty") {
                        Write-Log "Verification successful: Proxy is now empty" -Level "SUCCESS"
                    }
                    else {
                        Write-Log "Warning: Proxy may not be completely cleared. Current value: '$VerifyResult'" -Level "WARNING"
                    }
                }
                else {
                    Write-Log "Warning: Could not verify proxy configuration after clearing" -Level "WARNING"
                }
            }
            else {
                Write-Log "Failed to clear proxy settings. Exit code: $LASTEXITCODE" -Level "ERROR"
                Write-Log "Command output: $Result3" -Level "ERROR"
                $Success = $false
            }
        }
        catch {
            Write-Log "Exception while clearing proxy settings: $($_.Exception.Message)" -Level "ERROR"
            $Success = $false
        }
    }
    else {
        Write-Log "Skipping proxy configuration due to previous failure" -Level "WARNING"
    }
    
    return $Success
}

# Main execution 
try {
    Write-Log "=== Dynatrace Configuration Script Started ===" -Level "INFO"
    Write-Log "Running with Administrator privileges: $(Test-Administrator)" -Level "INFO"
    Write-Log "Tracking Registry: $TrackingRegistryPath" -Level "INFO"
    Write-Log "Log Path: $LogPath" -Level "INFO"
    
    # Check if script has already run
    if (Test-AlreadyRun) {
        Write-Log "Dynatrace configuration has already been completed. Exiting." -Level "SUCCESS"
        exit 0
    }
    
    Write-Log "First time execution detected. Proceeding with configuration..." -Level "INFO"
    
    # Execute Dynatrace configuration
    $ConfigSuccess = Invoke-DynatraceConfiguration
    
    if ($ConfigSuccess) {
        Write-Log "Dynatrace configuration completed successfully" -Level "SUCCESS"
        
        # Set registry flag to prevent future runs
        if (Set-RegistryFlag) {
            Write-Log "Configuration marked as completed in registry" -Level "SUCCESS"
        }
        else {
            Write-Log "Warning: Could not set registry flag. Script may run again." -Level "WARNING"
        }
        
        Write-Log "=== Dynatrace Configuration Script Completed Successfully ===" -Level "SUCCESS"
        exit 0
    }
    else {
        Write-Log "Dynatrace configuration failed" -Level "ERROR"
        Write-Log "=== Dynatrace Configuration Script Completed with Errors ===" -Level "ERROR"
        exit 1
    }
}
catch {
    Write-Log "Unexpected error in main execution: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "=== Dynatrace Configuration Script Failed ===" -Level "ERROR"
    exit 1
}
finally {
    # Return to original location
    Set-Location $env:SystemRoot
}