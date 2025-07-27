<#
    Helper function to just write to any given log, with timestamp included
    Creates file if it does not exist already
#>
function Write-ToLog {
    param (
        [string]$message,
        [string]$log_file
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    # Create file if it doesn't exist
    if (-not (Test-Path -Path $log_file)) {
        New-Item -Path $log_file -ItemType File
    }
    "$timestamp - $message" | Out-File -FilePath $log_file -Append
}