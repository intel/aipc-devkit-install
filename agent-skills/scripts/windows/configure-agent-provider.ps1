param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('hermes', 'openclaw')]
    [string]$TargetAgent,
    [switch]$Approve,
    [switch]$Apply,
    [switch]$Pull,
    [switch]$ApproveRetryPull,
    [switch]$ApproveStopOvms,
    [string]$Model = $null,
    [string]$BaseUrl = $null,
    [int]$MinFreeDiskGb = 0
)

. "$PSScriptRoot\_skill-common.ps1"

if (-not $PSBoundParameters.ContainsKey('Pull')) {
    $Pull = $false
}

$skillId = 'intel-agent-provider-config'
$result = Get-SkillResultSkeleton -SkillId $skillId -RiskClass 'write-config' -FunctionalStatus 'fail'

if ($Apply) {
    if (-not (Test-ApprovalRequired -RiskClass 'write-config' -Approve:$Approve)) {
        $result.functional_status = 'blocked'
        $result.warnings += 'Apply requires -Approve'
        $result.exit_code = 2
        Write-SkillResult -Result $result
    }
    $result.warnings += 'MVP stub: Apply not implemented; use staged diff and hermes model handoff steps'
}

$result.approval_granted = [bool]$Approve
$modelId = if ($Model) { $Model } else { $script:DefaultAgentModelId }
$base = if ($BaseUrl) { $BaseUrl } else { $script:DefaultOvmsBaseUrl }

$result.warnings += 'Never call ovms_agentic_setup.ps1 directly; use invoke-ovms-agentic-setup.ps1 only'
$result.warnings += 'Provider switch is manual: complete OVMS first, then follow local_provider_handoff (Hermes does not switch inference mid-session automatically)'

Add-AgentOvmsSetupCheck -Result $result -Approve:$Approve -Pull:$Pull -ApproveRetryPull:$ApproveRetryPull `
    -ApproveStopOvms:$ApproveStopOvms -ModelId $modelId -MinFreeDiskGb $MinFreeDiskGb

if ($result.functional_status -eq 'blocked') {
    if (-not $result.next_skill) { $result.next_skill = 'intel-ovms-agentic-setup' }
    $result.overall_status = 'blocked'
    Write-SkillResult -Result $result
}

$live = Get-OvmsAdvertisedModelIdForAgent -BaseUrl $base -CatalogModelId $modelId
$result | Add-Member -NotePropertyName advertised_model_ids -NotePropertyValue @($live.advertised_ids) -Force
$result | Add-Member -NotePropertyName model_id_source -NotePropertyValue $live.source -Force
$result | Add-Member -NotePropertyName advertised_match_pattern -NotePropertyValue $live.advertised_match_pattern -Force

$serving = if ($live.model_for_agent) { $live.model_for_agent } elseif ($result.serving_model) { $result.serving_model } else { $null }
if (-not $live.advertised_match) {
    $result.functional_status = 'fail'
    $result.exit_code = 1
    if ($live.advertised_ids.Count -eq 0) {
        $result.functional_status = 'blocked'
        $result.exit_code = 2
        $result.error = @{
            code        = 'OVMS_NOT_READY'
            message     = "GET $base/models returned no model ids"
            remediation = 'Start OVMS and confirm http://localhost:8000/v3/models lists the agent graph'
        }
    } else {
        $result.error = @{
            code        = 'MODEL_ADVERTISED_MISMATCH'
            message     = $live.advertised_match_message
            remediation = 'Restart OVMS with the catalog model for this skill, or fix -Model; pattern must match an advertised id'
        }
        $result.warnings += $live.advertised_match_message
    }
    Add-VerifyCheck -Result $result -Check @{
        id      = 'C2-v3-models'
        status  = 'fail'
        message = $live.advertised_match_message
    }
    $result.overall_status = $result.functional_status
    Write-SkillResult -Result $result
}

$modelForAgent = $serving
$result.serving_model = $serving
if ($serving -and $serving -ne $modelId) {
    $result.warnings += "Agent config uses advertised id '$serving' (regex $($live.advertised_match_pattern)); catalog pull id '$modelId'"
}

Add-VerifyCheck -Result $result -Check @{
    id      = 'C2-v3-models'
    status  = 'pass'
    message = "model_for_agent=$serving; pattern=$($live.advertised_match_pattern); advertised=$(if ($live.advertised_ids.Count) { $live.advertised_ids -join ', ' } else { 'none' })"
}

$diff = switch ($TargetAgent) {
    'hermes' {
        @{
            path   = Join-Path $env:USERPROFILE '.hermes\config.yaml'
            staged = @"
model:
  default: "$modelForAgent"
  provider: "custom"
  base_url: "$base"
"@
        }
    }
    'openclaw' {
        @{
            path   = Join-Path $env:USERPROFILE '.openclaw\openclaw.json'
            staged = "{ `"providers`": { `"ovms`": { `"baseUrl`": `"$base`", `"model`": `"$modelForAgent`" } } }"
        }
    }
}

Add-VerifyCheck -Result $result -Check @{ id = 'C1-staged-diff'; status = 'pass'; evidence = $diff }
$result.local_provider_handoff = New-HermesLocalProviderHandoff -BaseUrl $base -ModelId $modelId -ServingModel $serving -TargetAgent $TargetAgent
$result.warnings += 'Rollback: restore previous config from backup path (TBD)'
$result.warnings += 'Use the same model string as GET /v3/models after OVMS setup completes'
$result.model = $modelForAgent
$result.catalog_model_id = $modelId
$result.endpoint = $base
$infEval = Test-AgenticInferenceFromEndpoint -BaseUrl $base -AdvertisedIds @($live.advertised_ids)
Apply-InferenceReadinessToResult -Result $result -Eval $infEval
if (-not $result.agent_inference_ready) {
    $result.warnings += 'Agentic inference is not ready; OVMS must advertise the large agent model before Hermes local chat.'
}
$result.target_agent = $TargetAgent
$o1 = @($result.checks | Where-Object { $_.id -eq 'O1-agent-ovms-model' } | Select-Object -First 1)
if ($o1 -and $o1.status -eq 'fail') {
    $result.functional_status = 'fail'
    $result.exit_code = 1
} elseif ($o1 -and $o1.status -eq 'partial') {
    $result.functional_status = 'partial'
    $result.exit_code = 0
} else {
    $result.functional_status = 'pass'
    $result.exit_code = 0
}
$result.overall_status = $result.functional_status
Write-SkillResult -Result $result
