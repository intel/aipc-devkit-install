<#
    This script checks to following:
    - Terminal is being run with administrator priviledges
    - Winget minimum version 1.10.390 is setup
    - NuGet Package Provider is installed
    - Microsoft winget client

#>
$green_check = [char]0x2705
$red_x = [char]0x274C

<#
    Checks to ensure Terminal is being run in admin mode
    Returns true if terminal is being run in admin mode
    Returns false in all other cases
#>
function CheckIf-Admin() {
    $windows_identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $windows_principal = New-Object Security.Principal.WindowsPrincipal($windows_identity)
    $is_admin = $windows_principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

    if (-not $is_admin) {
        return $false
    }
    return $true
}



<#
    Checks the version of winget installed is at least 1.10.390
    Returns true if it is a MINIMUM 1.10.390
    Return false if winget version is lower than 1.10.390
#>
function Check-Winget() {
    $minimum_winget_version = [Version]"1.10.390"
    $current_winget_version = winget --version 2>$null
    if (-not $current_winget_version) {
        return $false
    }
    $current_winget_version = [Version]($current_winget_version.TrimStart('v'))
    if ($current_winget_version -lt $minimum_winget_version) {
        return $false
    }
    else {
        return $true
    }
}



<#
    Checks to ensure that the Microsoft WinGet Client is installed
    Returns true if the Winget client module is installed
#>
function Check-WinGet-Client() {
    if (Get-InstalledModule -Name "Microsoft.WinGet.Client" -ErrorAction SilentlyContinue) {
        return $true
    }
    else {
        return $false
    }

}

function Check-PreReq() {
    if ($Global:external) {
        if (-not (CheckIf-Admin)) {
            Write-Host "$red_x`: Administrator terminal"
            return $false
        }

        if (-not (Check-Winget)) {
            $user_input = Read-Host "This script requires winget version 1.10.390 minimum to run. Would you like to upgrade? [y/n]"
            if ($user_input -eq 'y' -or $user_input -eq "yes" -or $user_input -eq "Y") {
                winget upgrade winget
            }
            else {
                Write-Host "Not installing."
                return $false
            }
        }


        if (-not (Check-WinGet-Client)) {
            Write-Host "This script requires the winget client to be installed." -ForegroundColor Yellow
            Write-Host "This will also install the NuGet Package Provider." -ForegroundColor Yellow
            $user_input = Read-Host "Would you like to install these? [y/n]"
            if ($user_input -eq 'y' -or $user_input -eq "yes" -or $user_input -eq "Y") {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
                Install-Module -Name Microsoft.WinGet.Client -SkipPublisherCheck -Force
            }
            else {
                Write-Host "Not installing." -ForegroundColor Red
                return $false
            }
        } 

        if (CheckIf-Admin -and Check-Winget -and Check-WinGet-Client) {
            Write-Host "$green_check`: Administrator terminal."
            Write-Host "$green_check`: Winget version 1.10.390 minimum."
            Write-Host "$green_check`: Microsoft Winget client installed."
            Write-Host "$green_check`: All pre-requisites complete. Proceeding with installation..."
            Start-Sleep 2
            return $true
        }
    } else {
        # Internal mode - install silently with error handling

        # -----------------------------------------------------------------------
        # Step 1: Bootstrap PowerShell PackageManagement's own NuGet provider.
        # On a fresh system this provider is not registered, causing PowerShell to
        # show an interactive prompt:
        #   "The provider nuget 2.8.5.x is not installed. Would you like package
        #    management to automatically download and install nuget?"
        # -ForceBootstrap suppresses that prompt and installs silently.
        # This MUST run before Install-Module or Install-PackageProvider so that
        # PackageManagement itself is ready to talk to PSGallery without prompting.
        # -----------------------------------------------------------------------
        try {
            Write-Host "Bootstrapping PackageManagement NuGet provider..." -ForegroundColor Yellow
            # Import-PackageProvider with -ForceBootstrap silently registers the
            # NuGet provider for PackageManagement without any interactive prompt.
            Import-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop
            Write-Host "PackageManagement NuGet provider bootstrapped." -ForegroundColor Green
        } catch {
            # Provider not yet downloaded - install it silently with ForceBootstrap
            try {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ForceBootstrap -Scope CurrentUser -ErrorAction Stop
                Write-Host "PackageManagement NuGet provider installed." -ForegroundColor Green
            } catch {
                Write-Host "Warning: Could not bootstrap PackageManagement NuGet provider: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        # -----------------------------------------------------------------------
        # Step 2: Install the NuGet package provider for Install-PackageProvider
        # (belt-and-suspenders - ensures it is registered at machine scope too)
        # -----------------------------------------------------------------------
        try {
            $nugetInstalled = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
            if (-not $nugetInstalled) {
                Write-Host "Installing NuGet package provider..." -ForegroundColor Yellow
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ForceBootstrap -Scope CurrentUser -ErrorAction Stop
                Write-Host "NuGet package provider installed." -ForegroundColor Green
            } else {
                Write-Host "NuGet package provider already installed." -ForegroundColor Green
            }
        } catch {
            Write-Host "Warning: Could not install NuGet package provider. Continuing anyway..." -ForegroundColor Yellow
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        # -----------------------------------------------------------------------
        # Step 3: Install Microsoft.WinGet.Client module from PSGallery.
        # -ForceBootstrap is a safety net - if Steps 1/2 above did not fully
        # register the provider, this ensures PackageManagement bootstraps it
        # silently rather than prompting the user.
        # -----------------------------------------------------------------------
        try {
            if (-not (Get-InstalledModule -Name "Microsoft.WinGet.Client" -ErrorAction SilentlyContinue)) {
                Write-Host "Installing Microsoft.WinGet.Client module..." -ForegroundColor Yellow
                Install-Module -Name Microsoft.WinGet.Client -Force -Scope CurrentUser -ErrorAction Stop
                Write-Host "Microsoft.WinGet.Client module installed." -ForegroundColor Green
            } else {
                Write-Host "Microsoft.WinGet.Client module already installed." -ForegroundColor Green
            }
            # Import the module into the current session so Get-WinGetPackage is available
            # without requiring a PowerShell restart.
            Import-Module -Name Microsoft.WinGet.Client -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Host "Warning: Could not install Microsoft.WinGet.Client module. Continuing anyway..." -ForegroundColor Yellow
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        try {
            # Try to upgrade winget
            Write-Host "Checking for winget updates..." -ForegroundColor Yellow
            winget upgrade winget --silent --disable-interactivity --accept-source-agreements 2>$null
        } catch {
            Write-Host "Warning: Could not upgrade winget. Continuing anyway..." -ForegroundColor Yellow
        }
        
        return $true
    }
}