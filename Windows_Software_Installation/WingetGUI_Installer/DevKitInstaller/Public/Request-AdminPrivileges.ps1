<#
.SYNOPSIS
    Administrator privilege checking and elevation.

.DESCRIPTION
    Test-Administrator checks whether the current session is elevated.
    Request-AdminPrivileges will prompt the user and re-launch the given
    script as administrator if necessary.
#>

function Test-Administrator {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-AdminPrivileges {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$commandToRun = "",

        [Parameter(Mandatory=$false)]
        [string]$ScriptPath = ""
    )

    if (-not (Test-Administrator)) {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        $result = [System.Windows.Forms.MessageBox]::Show(
            "This application requires administrator privileges to install software.`n`nWould you like to restart as administrator?",
            'Administrator Required',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )

        if ($result -eq 'Yes') {
            # Use the explicitly-provided script path so the correct entry point is relaunched
            if (-not $ScriptPath) {
                $ScriptPath = $PSCommandPath
                if (-not $ScriptPath) {
                    $ScriptPath = $MyInvocation.MyCommand.Path
                }
            }

            $argumentList = if ($commandToRun) {
                "-ExecutionPolicy RemoteSigned -File `"$ScriptPath`" $commandToRun"
            } else {
                "-ExecutionPolicy RemoteSigned -File `"$ScriptPath`""
            }

            Start-Process -FilePath "powershell.exe" -ArgumentList $argumentList -Verb RunAs
        }

        exit
    }
}
