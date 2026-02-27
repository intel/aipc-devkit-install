<#
.SYNOPSIS
    Pre-requisite checks for the installer.

.DESCRIPTION
    Validates administrator privileges, winget version, and the
    Microsoft.WinGet.Client module. In external mode the user is
    prompted interactively; in internal mode installs happen silently.
#>

$green_check = [char]0x2705
$red_x       = [char]0x274C

function CheckIf-Admin {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Check-Winget {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $minimum = [Version]"1.10.390"
    $current = winget --version 2>$null
    if (-not $current) { return $false }

    $current = [Version]($current.TrimStart('v'))
    return $current -ge $minimum
}

function Check-WinGet-Client {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if (Get-InstalledModule -Name "Microsoft.WinGet.Client" -ErrorAction SilentlyContinue) {
        return $true
    }
    return $false
}

function Check-PreReq {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # Read mode from module configuration (replaces $Global:external)
    $externalMode = (Get-DevKitConfig).ExternalMode

    if ($externalMode) {
        # ---- External / customer-facing mode — interactive prompts ----
        if (-not (CheckIf-Admin)) {
            Write-Host "$red_x`: Administrator terminal"
            return $false
        }

        if (-not (Check-Winget)) {
            $user_input = Read-Host "This script requires winget version 1.10.390 minimum to run. Would you like to upgrade? [y/n]"
            if ($user_input -eq 'y' -or $user_input -eq 'yes' -or $user_input -eq 'Y') {
                winget upgrade winget
            } else {
                Write-Host "Not installing."
                return $false
            }
        }

        if (-not (Check-WinGet-Client)) {
            Write-Host "This script requires the winget client to be installed." -ForegroundColor Yellow
            Write-Host "This will also install the NuGet Package Provider." -ForegroundColor Yellow
            $user_input = Read-Host "Would you like to install these? [y/n]"
            if ($user_input -eq 'y' -or $user_input -eq 'yes' -or $user_input -eq 'Y') {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
                Install-Module -Name Microsoft.WinGet.Client -SkipPublisherCheck -Force
            } else {
                Write-Host "Not installing." -ForegroundColor Red
                return $false
            }
        }

        if ((CheckIf-Admin) -and (Check-Winget) -and (Check-WinGet-Client)) {
            Write-Host "$green_check`: Administrator terminal."
            Write-Host "$green_check`: Winget version 1.10.390 minimum."
            Write-Host "$green_check`: Microsoft Winget client installed."
            Write-Host "$green_check`: All pre-requisites complete. Proceeding with installation..."
            Start-Sleep 2
            return $true
        }
    }
    else {
        # ---- Internal mode — install silently with error handling ----
        try {
            $nugetInstalled = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
            if (-not $nugetInstalled) {
                Write-Host "Installing NuGet package provider..." -ForegroundColor Yellow
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop
            } else {
                Write-Host "NuGet package provider already installed." -ForegroundColor Green
            }
        }
        catch {
            Write-Host "Warning: Could not install NuGet package provider. Continuing anyway..." -ForegroundColor Yellow
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        }

        try {
            if (-not (Get-InstalledModule -Name "Microsoft.WinGet.Client" -ErrorAction SilentlyContinue)) {
                Write-Host "Installing Microsoft.WinGet.Client module..." -ForegroundColor Yellow
                Install-Module -Name Microsoft.WinGet.Client -Force -Scope CurrentUser -ErrorAction Stop
            } else {
                Write-Host "Microsoft.WinGet.Client module already installed." -ForegroundColor Green
            }
        }
        catch {
            Write-Host "Warning: Could not install Microsoft.WinGet.Client module. Continuing anyway..." -ForegroundColor Yellow
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        }

        try {
            Write-Host "Checking for winget updates..." -ForegroundColor Yellow
            winget upgrade winget --silent --disable-interactivity --accept-source-agreements 2>$null
        }
        catch {
            Write-Host "Warning: Could not upgrade winget. Continuing anyway..." -ForegroundColor Yellow
        }

        return $true
    }
}
