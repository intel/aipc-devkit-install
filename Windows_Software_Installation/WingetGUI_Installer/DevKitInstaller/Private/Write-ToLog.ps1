<#
.SYNOPSIS
    Writes a timestamped message to a log file.

.DESCRIPTION
    Appends a message with a timestamp to the specified log file.
    Creates the file and parent directories if they do not exist.
#>
function Write-ToLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$message,

        [Parameter(Mandatory=$true)]
        [string]$log_file
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Create parent directory if needed
    $logDir = Split-Path -Parent $log_file
    if ($logDir -and -not (Test-Path -Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    # Create file if it doesn't exist
    if (-not (Test-Path -Path $log_file)) {
        New-Item -Path $log_file -ItemType File -Force | Out-Null
    }

    "$timestamp - $message" | Out-File -FilePath $log_file -Append
}
