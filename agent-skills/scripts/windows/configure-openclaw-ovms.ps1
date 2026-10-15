param(
    [switch]$Approve,
    [switch]$Apply,
    [switch]$Pull,
    [switch]$ApproveRetryPull,
    [switch]$ApproveStopOvms,
    [string]$Model,
    [string]$BaseUrl,
    [int]$MinFreeDiskGb = 0
)
if (-not $PSBoundParameters.ContainsKey('Pull')) { $Pull = $false }
& "$PSScriptRoot\configure-agent-provider.ps1" -TargetAgent openclaw -Approve:$Approve -Apply:$Apply -Pull:$Pull `
    -ApproveRetryPull:$ApproveRetryPull -ApproveStopOvms:$ApproveStopOvms -Model $Model -BaseUrl $BaseUrl -MinFreeDiskGb $MinFreeDiskGb @args
