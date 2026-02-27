@{
    RootModule        = 'DevKitInstaller.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b8f6d2a1-3e4c-5d7f-9a1b-2c3d4e5f6a7b'
    Author            = 'Intel AIPC Team'
    CompanyName       = 'Intel Corporation'
    Copyright         = '(c) Intel Corporation. All rights reserved.'
    Description       = 'AI PC Dev Kit software installer module using winget and WPF GUI'
    PowerShellVersion = '5.1'

    # Only these functions are visible to callers who Import-Module
    FunctionsToExport = @(
        'Install-SelectedPackages'
        'Uninstall-SelectedPackages'
        'Invoke-BatchUninstall'
        'Show-MainGUI'
        'Check-PreReq'
        'Confirm-Eula'
        'Test-Administrator'
        'Request-AdminPrivileges'
        'Set-DevKitConfig'
        'Get-DevKitConfig'
        'Write-ToLog'
    )

    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('winget', 'installer', 'intel', 'aipc', 'devkit')
            ProjectUri = 'https://github.com/intel/aipc-devkit-install'
        }
    }
}
