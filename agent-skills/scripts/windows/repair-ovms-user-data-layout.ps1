# One-time or post-reboot repair: junction ...\OVMS\models and .ovcache -> %USERPROFILE%\OVMS
# so ovms_agentic_setup.ps1 can use relative paths (avoids OVMS CACHE_DIR JSON bug on absolute profile paths).
param(
    [string]$InstallRoot = $null,
    [switch]$WhatIf
)

. "$PSScriptRoot\_skill-common.ps1"

$layout = Initialize-DevKitOvmsUserDataLayout -InstallRoot $InstallRoot -RepairBlockingDirectories:$(-not $WhatIf)
$result = Get-SkillResultSkeleton -SkillId 'intel-ovms-user-data-repair' -RiskClass 'read' -FunctionalStatus 'fail'
$result.approval_granted = $true

if ($layout.skipped) {
    $result.functional_status = 'blocked'
    $result.warnings += $layout.message
    $result.exit_code = 0
    Write-SkillResult -Result $result
}

if ($WhatIf) {
    $result.warnings += 'WhatIf: no changes made; run without -WhatIf to repair'
}

if ($layout.ok) {
    $result.functional_status = 'pass'
    $result.exit_code = 0
    foreach ($line in $layout.junction) { $result.logs += $line }
    if ($layout.ovms_dir) { $result.logs += "ovms_dir=$($layout.ovms_dir)" }
    $result.warnings += 'Start OVMS with: invoke-ovms-agentic-setup.ps1 -Approve -Pull -Profile verify (do not pass absolute -CacheDir to ovms_agentic_setup.ps1)'
} else {
    $result.functional_status = 'fail'
    $result.exit_code = 1
    $result.warnings += $layout.message
}

$result.overall_status = $result.functional_status
Write-SkillResult -Result $result
