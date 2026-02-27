#Requires -Version 5.1
<#
.SYNOPSIS
    Root module for the DevKitInstaller PowerShell module.

.DESCRIPTION
    Automatically loads all Private (internal) and Public (exported) functions.
    Private functions are available within the module but not exported.
    Public functions are exported via the module manifest (DevKitInstaller.psd1).

.NOTES
    Authors:
    - Ben (benjamin.j.odom@intel.com)
    - Vijay (vijay.chandrashekar@intel.com)
#>

# ---------------------------------------------------------------------------
# Module-scoped configuration — set by Set-DevKitConfig, read by functions
# ---------------------------------------------------------------------------
$script:Config = @{
    ExternalMode      = $false    # $true = customer-facing (EULA required); $false = internal
    JsonInstallFile   = ''        # Absolute path to applications.json
    JsonUninstallFile = ''        # Absolute path to uninstall.json
}

function Set-DevKitConfig {
    <#
    .SYNOPSIS
        Configure module-level settings before running install/uninstall operations.
    #>
    [CmdletBinding()]
    param(
        [bool]$ExternalMode = $false,
        [string]$JsonInstallFile = '',
        [string]$JsonUninstallFile = ''
    )
    $script:Config.ExternalMode = $ExternalMode
    if ($JsonInstallFile)   { $script:Config.JsonInstallFile   = $JsonInstallFile }
    if ($JsonUninstallFile) { $script:Config.JsonUninstallFile = $JsonUninstallFile }
}

function Get-DevKitConfig {
    <#
    .SYNOPSIS
        Returns the current module configuration hashtable.
    #>
    [CmdletBinding()]
    param()
    return $script:Config
}

# ---------------------------------------------------------------------------
# Auto-load function files — Private first (helpers), then Public (exported)
# ---------------------------------------------------------------------------
$privatePath = Join-Path $PSScriptRoot 'Private'
if (Test-Path $privatePath) {
    Get-ChildItem -Path $privatePath -Filter '*.ps1' -Recurse | ForEach-Object {
        try {
            . $_.FullName
        }
        catch {
            Write-Warning "Failed to load private function file $($_.Name): $_"
        }
    }
}

$publicPath = Join-Path $PSScriptRoot 'Public'
if (Test-Path $publicPath) {
    Get-ChildItem -Path $publicPath -Filter '*.ps1' -Recurse | ForEach-Object {
        try {
            . $_.FullName
        }
        catch {
            Write-Warning "Failed to load public function file $($_.Name): $_"
        }
    }
}
