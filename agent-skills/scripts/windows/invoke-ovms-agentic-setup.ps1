param(
    [switch]$Approve,
    [switch]$Pull,
    [switch]$ApproveRetryPull,
    [switch]$ApproveStopOvms,
    [ValidateSet('verify', 'agent')]
    [string]$Profile = 'verify',
    [string]$Model = $null,
    [string]$Target = $null,
    [int]$Port = 8000,
    [int]$MinFreeDiskGb = 0,
    [switch]$SkipLaunch,
    [switch]$RunToolTest,
    [switch]$SkipChatSmoke
)

. "$PSScriptRoot\_skill-common.ps1"

$skillId = 'intel-ovms-agentic-setup'
$result = Get-SkillResultSkeleton -SkillId $skillId -RiskClass 'network' -FunctionalStatus 'fail'

$needsNetwork = [bool]$Pull
if ($needsNetwork -and -not (Test-ApprovalRequired -RiskClass 'network' -Approve:$Approve)) {
    $result.functional_status = 'blocked'
    $result.overall_status = 'blocked'
    $result.warnings += 'Approval required for -Pull (network): pass -Approve'
    $result.exit_code = 2
    Write-SkillResult -Result $result
}

if (-not $needsNetwork -and -not (Test-ApprovalRequired -RiskClass 'network' -Approve:$Approve)) {
    $result.functional_status = 'blocked'
    $result.overall_status = 'blocked'
    $result.warnings += 'Approval required to launch OVMS: pass -Approve'
    $result.exit_code = 2
    Write-SkillResult -Result $result
}

$result.approval_granted = $true
if (Test-DevKitSessionIsElevated) {
    Add-DevKitStandardUserHandoffWarnings -Result $result -Context elevated-session
    if ($env:AIPC_OVMS_USE_CLONE_PATHS -eq '1') {
        $result.warnings += 'AIPC_OVMS_USE_CLONE_PATHS=1 with an elevated session can recreate Admin-owned model/cache under the clone; unset it for standard-user Track A'
    }
}
$modelId = if ($Model) { $Model } else { Get-OvmsModelForProfile -Profile $Profile }
$target = if ($Target) { $Target } else { Get-OvmsTargetForProfile -Profile $Profile }
$result.model_profile = $Profile

$root = Find-DevKitInstallRoot
$ovmsResolved = Find-DevKitOvmsAgenticScript -InstallRoot $root
if (-not $ovmsResolved) {
    $result.error = @{
        code        = 'OVMS_SCRIPT_NOT_FOUND'
        message     = 'ovms_agentic_setup.ps1 not found'
        remediation = 'Install Dev Kit or clone training.developer.aipc; optional override: AIPC_DEVKIT_INSTALL_ROOT'
    }
    Write-SkillResult -Result $result
}
if (-not $root -and $ovmsResolved.install_root) {
    $root = $ovmsResolved.install_root
}
$result.devkit_install_root = $root
$result.ovms_agentic_script = $ovmsResolved.script
$result.devkit_discovery = $ovmsResolved.discovery

if (-not $SkipLaunch) {
    $layout = Initialize-DevKitOvmsUserDataLayout -InstallRoot $root -RepairBlockingDirectories
    if ($layout.skipped -and $layout.message) {
        $result.warnings += $layout.message
    } elseif (-not $layout.ok) {
        $result.warnings += "OVMS user-data layout: $($layout.message)"
    } else {
        foreach ($line in $layout.junction) { $result.logs += $line }
        $result.logs += 'ovms_launch_uses_relative_models_and_dot_ovcache_via_junctions'
        $result.warnings += 'Never pass -CacheDir/-ModelRepositoryPath with C:\Users\... to ovms_agentic_setup.ps1 (OVMS CACHE_DIR JSON bug); skill uses relative models/.ovcache only'
    }
}

$toolTest = $RunToolTest -or ($Profile -eq 'verify')
Add-OvmsSetupChecksToResult -Result $result -InstallRoot $root -ModelId $modelId -Target $target -Pull:$Pull -RunToolTest:$toolTest `
    -SkipLaunch:$SkipLaunch -SkipChatSmoke:$SkipChatSmoke -Port $Port -Approve:$Approve -ApproveRetryPull:$ApproveRetryPull `
    -ApproveStopOvms:$ApproveStopOvms -MinFreeDiskGb $MinFreeDiskGb

if ($result.functional_status -eq 'blocked') {
    $result.overall_status = 'blocked'
    if (-not $result.next_skill) { $result.next_skill = 'intel-ovms-agentic-setup' }
    Write-SkillResult -Result $result
}

$baseUrl = if ($result.endpoint) { $result.endpoint } else { Get-OvmsBaseUrl -Port $Port }
$advertised = @(Get-ResultProperty -Result $result -Name 'ovms_advertised_models')
$o2Pass = @($result.checks | Where-Object { $_.id -eq 'O2-health' -and $_.status -eq 'pass' })
if ($o2Pass.Count -gt 0) {
    $infEval = Add-AgenticInferenceCheck -Result $result -CheckId 'A1-agentic-inference' -BaseUrl $baseUrl -AdvertisedIds $advertised
} else {
    $infEval = Add-AgenticInferenceCheck -Result $result -CheckId 'A1-agentic-inference' -OvmsNotRunning
}
Apply-InferenceReadinessToResult -Result $result -Eval $infEval

$criticalFails = @($result.checks | Where-Object { $_.status -eq 'fail' -and $_.id -in @('O2-health', 'O4-chat', 'O0-preflight') })
$anyFail = @($result.checks | Where-Object { $_.status -eq 'fail' })
if ($criticalFails.Count -gt 0) {
    $result.functional_status = 'fail'
    $result.exit_code = 1
} elseif ($anyFail.Count -gt 0) {
    $result.functional_status = 'partial'
    $result.exit_code = 0
} else {
    $result.functional_status = 'pass'
    $result.exit_code = 0
}
if ($result.functional_status -eq 'pass' -and $Profile -eq 'verify' -and -not $result.agent_inference_ready) {
    $result.functional_status = 'partial'
    $result.overall_status = 'partial'
    $result.readiness_tier = 'smoke'
    $result.next_skill = 'intel-ovms-agentic-setup'
    $result.warnings += 'Smoke (verify) model only; not ready for large agent chat until -Profile agent succeeds.'
} elseif ($Profile -eq 'agent' -and $result.agent_inference_ready) {
    $result.readiness_tier = 'agent'
    Set-IntelAgentProviderConfigNextSkillIfReady -Result $result
}
$result.overall_status = $result.functional_status
Write-SkillResult -Result $result
