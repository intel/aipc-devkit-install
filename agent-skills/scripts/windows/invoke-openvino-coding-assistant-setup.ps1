param(
    [switch]$Approve,
    [switch]$Pull,
    [switch]$Apply,
    [switch]$ApproveRetryPull,
    [switch]$ApproveStopOvms,
    [switch]$SkipOvms,
    [switch]$SkipContinue,
    [string]$Model = $null,
    [int]$Port = 0
)

. "$PSScriptRoot\_skill-common.ps1"

$skillId = 'openvino-coding-assistant'
$result = Get-SkillResultSkeleton -SkillId $skillId -SkillVersion '0.2.0' -RiskClass 'write-config' -FunctionalStatus 'fail'

$needsNetwork = [bool]$Pull
$needsWrite = [bool]$Apply
if ($needsNetwork -and -not (Test-ApprovalRequired -RiskClass 'network' -Approve:$Approve)) {
    $result.functional_status = 'blocked'
    $result.overall_status = 'blocked'
    $result.warnings += 'Approval required for -Pull (network): pass -Approve'
    $result.exit_code = 2
    Write-SkillResult -Result $result
}
if ((-not $SkipOvms -or $needsWrite) -and -not (Test-ApprovalRequired -RiskClass 'network' -Approve:$Approve)) {
    $result.functional_status = 'blocked'
    $result.overall_status = 'blocked'
    $result.warnings += 'Approval required for OVMS launch: pass -Approve'
    $result.exit_code = 2
    Write-SkillResult -Result $result
}
if ($needsWrite -and -not (Test-ApprovalRequired -RiskClass 'write-config' -Approve:$Approve)) {
    $result.functional_status = 'blocked'
    $result.overall_status = 'blocked'
    $result.warnings += 'Writing Continue config requires -Approve'
    $result.exit_code = 2
    Write-SkillResult -Result $result
}

$result.approval_granted = $true
$catalogModel = if ($Model) { $Model } else { $script:DefaultCodingCatalogModelId }
$restPort = if ($Port -gt 0) { $Port } else { $script:DefaultCodingOvmsPort }
$result.catalog_model_id = $catalogModel
$result.coding_ovms_port = $restPort
$result.canonical_doc = 'https://docs.openvino.ai/2026/model-server/ovms_demos_code_completion_vsc.html'

if (-not $SkipOvms) {
    $ovmsScript = Join-Path $PSScriptRoot 'invoke-ovms-agentic-setup.ps1'
    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $argList = @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ovmsScript,
            '-Approve',
            '-Profile', 'agent',
            '-SkipChatSmoke',
            '-Model', $catalogModel,
            '-Target', $script:DefaultCodingOvmsTarget,
            '-Port', [string]$restPort
        )
        if ($Pull) { $argList += '-Pull' }
        if ($ApproveRetryPull) { $argList += '-ApproveRetryPull' }
        if ($ApproveStopOvms) { $argList += '-ApproveStopOvms' }
        $disk = Get-OvmsModelDiskRequirements -ModelId $catalogModel
        if ($disk.recommended_gb -gt 0) {
            $argList += @('-MinFreeDiskGb', [string]$disk.recommended_gb)
        }

        $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList `
            -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $stdout = Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue
        if ($stderr) { $result.logs += @($stderr -split "`n" | Where-Object { $_ }) }

        $jsonStart = $stdout.IndexOf('{')
        if ($jsonStart -lt 0) {
            $result.functional_status = 'fail'
            $result.exit_code = 1
            $result.error = @{
                code    = 'OVMS_SUBPROCESS_NO_JSON'
                message = 'OVMS setup did not return JSON on stdout'
            }
            $result.logs += $stdout
            Write-SkillResult -Result $result
        }
        $ovmsJson = $stdout.Substring($jsonStart)
        $ovmsResult = $ovmsJson | ConvertFrom-Json
        $result.ovms_subprocess_exit = $proc.ExitCode
        foreach ($c in @($ovmsResult.checks)) {
            $cid = 'OVMS-' + $c.id
            Add-VerifyCheck -Result $result -Check @{ id = $cid; status = $c.status; message = $c.message }
        }
        $result.endpoint = $ovmsResult.endpoint
        $result.serving_model = $ovmsResult.serving_model
        if ($ovmsResult.functional_status -ne 'pass' -and $ovmsResult.functional_status -ne 'partial') {
            $result.functional_status = $ovmsResult.functional_status
            $result.exit_code = if ($ovmsResult.exit_code) { [int]$ovmsResult.exit_code } else { 1 }
            $result.error = $ovmsResult.error
            $result.overall_status = $result.functional_status
            Write-SkillResult -Result $result
        }
        if ($ovmsResult.functional_status -eq 'partial') {
            $result.warnings += 'OVMS setup partial; Continue step may still work if Qwen3.6 35B is advertised on port {0}' -f $restPort
        }
    } finally {
        Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
}

if (-not $SkipContinue) {
    $continueResult = Get-SkillResultSkeleton -SkillId 'openvino-coding-assistant-internal' -RiskClass 'write-config' -FunctionalStatus 'fail'
    Add-ContinueOvmsConfigToResult -Result $continueResult -Approve:$Approve -Apply:$Apply `
        -CatalogModelId $catalogModel -Port $restPort
    foreach ($c in @($continueResult.checks)) {
        Add-VerifyCheck -Result $result -Check @{ id = $c.id; status = $c.status; message = $c.message; evidence = $c.evidence }
    }
    if ($continueResult.continue_config_backup) { $result.continue_config_backup = $continueResult.continue_config_backup }
    if ($continueResult.continue_config_path) { $result.continue_config_path = $continueResult.continue_config_path }
    if ($continueResult.error) { $result.error = $continueResult.error }
    $result.functional_status = $continueResult.functional_status
    $result.exit_code = $continueResult.exit_code
    if ($continueResult.next_steps) { $result.next_steps = @($continueResult.next_steps) }
    foreach ($w in @($continueResult.warnings)) {
        if ($w -and ($result.warnings -notcontains $w)) { $result.warnings += $w }
    }
}

if ($result.functional_status -eq 'fail' -or $result.functional_status -eq 'blocked') {
    $result.overall_status = $result.functional_status
    Write-SkillResult -Result $result
}

$result.functional_status = 'pass'
$result.exit_code = 0
$result.overall_status = 'pass'
if (-not $result.next_steps -or $result.next_steps.Count -eq 0) {
    $result.next_steps = @(
        "Open VS Code and select OVMS $($script:DefaultCodingServingModelId) in Continue."
        "Confirm GET http://localhost:$restPort/v3/models lists $($script:DefaultCodingServingModelId)."
    )
}
Write-SkillResult -Result $result
