<#
.SYNOPSIS
    Internal WPF helpers for the GUI.

.DESCRIPTION
    Utility functions used by the public GUI functions:
    Ensure-StaThread and Convert-AppsToSelectionItems.
#>

# Load WPF assemblies (safe to call multiple times — .NET ignores duplicates)
Add-Type -AssemblyName PresentationFramework  -ErrorAction SilentlyContinue
Add-Type -AssemblyName PresentationCore       -ErrorAction SilentlyContinue
Add-Type -AssemblyName WindowsBase            -ErrorAction SilentlyContinue

function Ensure-StaThread {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        Write-Host 'WPF requires STA. Start PowerShell with -STA to use WPF dialogs.' -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Convert-AppsToSelectionItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $applications
    )

    $items = New-Object System.Collections.Generic.List[object]

    foreach ($app in $applications.winget_applications) {
        if ($null -eq $app) { continue }
        $items.Add([pscustomobject]@{
            Check        = if ($null -ne $app.skip_install) { $app.skip_install -ne 'yes' } else { $true }
            Id           = if ($null -ne $app.id -and $app.id -ne '') { $app.id } else { $app.name }
            FriendlyName = if ($null -ne $app.friendly_name -and $app.friendly_name -ne '') { $app.friendly_name } else { $app.name }
            Summary      = if ($null -ne $app.summary -and $app.summary -ne '') { $app.summary } else { 'No description available' }
            Version      = if ($null -ne $app.version -and $app.version -ne '') { $app.version } else { 'Latest' }
            Type         = 'Winget'
        })
    }

    foreach ($app in $applications.external_applications) {
        if ($null -eq $app) { continue }
        $items.Add([pscustomobject]@{
            Check        = if ($null -ne $app.skip_install) { $app.skip_install -ne 'yes' } else { $true }
            Id           = $app.name
            FriendlyName = if ($null -ne $app.friendly_name -and $app.friendly_name -ne '') { $app.friendly_name } else { $app.name }
            Summary      = if ($null -ne $app.summary -and $app.summary -ne '') { $app.summary } else { 'External application' }
            Version      = 'External'
            Type         = 'External'
        })
    }

    return ,$items
}
