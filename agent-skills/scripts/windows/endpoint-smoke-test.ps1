param(
    [string]$BaseUrl = $null,
    [string]$Model = $null,
    [switch]$IncludeToolTest,
    [string]$InstallRoot = $null
)

. "$PSScriptRoot\_skill-common.ps1"

$skillId = 'intel-endpoint-smoke-test-report'
$result = Get-SkillResultSkeleton -SkillId $skillId -RiskClass 'read' -FunctionalStatus 'fail'
$result.approval_granted = $true
if (Test-DevKitSessionIsElevated) {
    Add-DevKitStandardUserHandoffWarnings -Result $result -Context elevated-session
}

$base = if ($BaseUrl) { $BaseUrl.TrimEnd('/') } else { $script:DefaultOvmsBaseUrl }
$preferredModel = if ($Model) { $Model } else { $script:DefaultVerifyModelId }
$result.endpoint = $base
$result.model = $preferredModel

$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $modelsResp = Invoke-RestMethod -Uri "$base/models" -TimeoutSec 10
    $ids = @(Get-OvmsModelIdsFromResponse -ModelsResponse $modelsResp)
    $advMatch = Find-OvmsAdvertisedModelByCatalog -AdvertisedIds $ids -CatalogModelId $preferredModel
    $result.serving_model = $advMatch.id
    $result | Add-Member -NotePropertyName advertised_match_pattern -NotePropertyValue $advMatch.pattern -Force
    if (-not $advMatch.matched) {
        Add-VerifyCheck -Result $result -Check @{
            id      = 'E1-models'
            status  = 'fail'
            message = $advMatch.message
        }
        throw [System.InvalidOperationException]::new($advMatch.message)
    }
    $chatCandidates = Get-OvmsChatModelCandidates -AvailableIds $ids -PreferredModel $preferredModel
    Add-VerifyCheck -Result $result -Check @{
        id      = 'E1-models'
        status  = 'pass'
        message = "$($advMatch.message); candidates: $(($chatCandidates -join ', '))"
    }

    $chatRun = Invoke-OvmsChatCompletionSmokeFirstSuccess -BaseUrl $base -ModelCandidates $chatCandidates
    if (-not $chatRun.ok) {
        throw [System.InvalidOperationException]::new($chatRun.error)
    }
    $result.serving_model = $chatRun.model
    $sw.Stop()
    Add-VerifyCheck -Result $result -Check @{
        id      = 'E2-latency'
        status  = 'pass'
        message = "$($sw.ElapsedMilliseconds) ms"
    }
    $result | Add-Member -NotePropertyName latency_ms -NotePropertyValue $sw.ElapsedMilliseconds -Force

    if ($IncludeToolTest) {
        $root = if ($InstallRoot) { $InstallRoot } else { Find-DevKitInstallRoot }
        if (-not $root) {
            Add-VerifyCheck -Result $result -Check @{
                id      = 'E3-tool-path'
                status  = 'skip'
                message = 'Install root unknown; pass -InstallRoot for tool smoke'
            }
        } else {
            $toolRun = Invoke-DevKitOvmsAgenticSetup -InstallRoot $root -Model $result.serving_model -Target $script:DefaultOvmsTarget -Test
            foreach ($line in $toolRun.logs) {
                if ($line) { $result.logs += $line }
            }
            Add-VerifyCheck -Result $result -Check @{
                id      = 'E3-tool-path'
                status  = $(if ($toolRun.ok) { 'pass' } else { 'fail' })
                message = $toolRun.message
            }
        }
    } else {
        Add-VerifyCheck -Result $result -Check @{
            id      = 'E3-tool-path'
            status  = 'skip'
            message = 'Pass -IncludeToolTest when agentic model supports tool-call smoke'
        }
    }

    Add-VerifyCheck -Result $result -Check @{
        id      = 'E4-reproducibility'
        status  = 'pass'
        message = "run_id=$($result.run_id); schema_id=$($result.schema_id)"
    }

    $fails = @($result.checks | Where-Object { $_.status -eq 'fail' })
    if ($fails.Count -gt 0) {
        $result.functional_status = 'fail'
        $result.exit_code = 1
    } else {
        $result.functional_status = 'pass'
        $result.exit_code = 0
    }
} catch {
    $sw.Stop()
    Add-VerifyCheck -Result $result -Check @{ id = 'E1-models'; status = 'fail'; message = $_.Exception.Message }
    Add-VerifyCheck -Result $result -Check @{ id = 'E2-latency'; status = 'skip'; message = 'Chat not attempted' }
    Add-VerifyCheck -Result $result -Check @{ id = 'E3-tool-path'; status = 'skip'; message = 'Endpoint unreachable' }
    Add-VerifyCheck -Result $result -Check @{ id = 'E4-reproducibility'; status = 'pass'; message = "run_id=$($result.run_id)" }
    $result.functional_status = 'fail'
    $result.exit_code = 1
}

$result.overall_status = $result.functional_status
Write-SkillResult -Result $result
