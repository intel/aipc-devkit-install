param(
    [switch]$Approve,
    [string]$InstallRoot = $null
)

. "$PSScriptRoot\_skill-common.ps1"

$skillId = 'intel-devkit-verify'
$result = Get-SkillResultSkeleton -SkillId $skillId -RiskClass 'read' -FunctionalStatus 'partial'
$result.approval_granted = $true

if (Test-DevKitSessionIsElevated) {
    Add-DevKitStandardUserHandoffWarnings -Result $result -Context elevated-session
}

$root = if ($InstallRoot) { $InstallRoot } else { Find-DevKitInstallRoot }
if ($root) { $result.devkit_install_root = $root }
$scopeLocal = [bool]$InstallRoot
$dk = Get-DevKitStatus -InstallRoot $root -LocalOnly:$scopeLocal
$result.devkit_status = $dk.status

$result.checks += @{
    id      = 'V1-installer-state'
    status  = $(if ($dk.status -eq 'absent') { 'fail' } else { 'pass' })
    message = "devkit_status=$($dk.status)"
}

if ($dk.status -eq 'absent') {
    $result.functional_status = 'blocked'
    $result.overall_status = 'blocked'
    $result.next_skill = 'intel-devkit-install'
    $result.exit_code = 0
    $result.checks += @{ id = 'V2-git'; status = 'skip'; message = 'Dev Kit absent' }
    $result.checks += @{ id = 'V3-openvino-genai'; status = 'skip'; message = 'Dev Kit absent' }
    $result.checks += @{ id = 'V4-ovms-installed'; status = 'skip'; message = 'Dev Kit absent' }
    $result.checks += @{ id = 'V4-ovms-model'; status = 'skip'; message = 'Dev Kit absent' }
    $result.checks += @{ id = 'V4-agent-model-on-disk'; status = 'skip'; message = 'Dev Kit absent' }
    $result.checks += @{ id = 'V4-ovms-running'; status = 'skip'; message = 'Dev Kit absent' }
    $result.checks += @{ id = 'V5-minimal-inference'; status = 'skip'; message = 'Dev Kit absent' }
    $result.checks += @{ id = 'V6-agentic-inference'; status = 'skip'; message = 'Dev Kit absent' }
} else {
    try {
        $gitV = (git --version 2>&1) -join ' '
        $result.checks += @{ id = 'V2-git'; status = 'pass'; message = $gitV }
    } catch {
        $result.checks += @{ id = 'V2-git'; status = 'fail'; message = $_.Exception.Message }
    }

    $genai = Test-OpenVinoGenAiPresent -InstallRoot $root
    if ($genai.found) {
        $result.checks += @{
            id      = 'V3-openvino-genai'
            status  = 'pass'
            message = "Found at $($genai.path)"
        }
    } else {
        $result.checks += @{
            id      = 'V3-openvino-genai'
            status  = 'fail'
            message = 'openvino_genai not found in standard locations'
        }
    }

    Add-OvmsVerifyChecks -Result $result -InstallRoot $root
    Add-MinimalInferenceVerifyCheck -Result $result
    $ovmsRunning = @($result.checks | Where-Object { $_.id -eq 'V4-ovms-running' -and $_.status -eq 'pass' })
    if ($ovmsRunning.Count -gt 0) {
        $endpoint = if ($result.endpoint) { $result.endpoint } else { $script:DefaultOvmsBaseUrl }
        $infEval = Add-AgenticInferenceCheck -Result $result -CheckId 'V6-agentic-inference' -BaseUrl $endpoint
    } else {
        $infEval = Add-AgenticInferenceCheck -Result $result -CheckId 'V6-agentic-inference' -OvmsNotRunning
    }
    Apply-InferenceReadinessToResult -Result $result -Eval $infEval
}

$next = Resolve-IntelDevkitVerifyNextSkill -Result $result
if ($next) { $result.next_skill = $next }

$fails = @($result.checks | Where-Object { $_.status -eq 'fail' })
if ($result.functional_status -ne 'blocked') {
    if ($fails.Count -eq 0 -and $result.devkit_status -eq 'present') {
        $result.functional_status = 'pass'
        $result.exit_code = 0
    } elseif ($result.devkit_status -eq 'partial') {
        $result.functional_status = 'partial'
        $result.exit_code = 0
    } elseif ($result.devkit_status -eq 'present' -and (Test-DevKitVerifyOvmsOnlyFailures -Result $result)) {
        $result.functional_status = 'partial'
        $result.exit_code = 0
    } else {
        $result.functional_status = 'fail'
        $result.exit_code = 1
    }
    $result.overall_status = $result.functional_status
}

Set-IntelAgentProviderConfigNextSkillIfReady -Result $result

Write-SkillResult -Result $result
