param(
    [switch]$Approve,
    [switch]$Apply,
    [string]$CatalogModel = $null,
    [string]$ServingModel = $null,
    [int]$Port = 0
)

. "$PSScriptRoot\_skill-common.ps1"

$skillId = 'openvino-coding-assistant'
$result = Get-SkillResultSkeleton -SkillId $skillId -SkillVersion '0.2.0' -RiskClass 'write-config' -FunctionalStatus 'fail'

if (-not (Test-ApprovalRequired -RiskClass 'write-config' -Approve:$Approve)) {
    $result.functional_status = 'blocked'
    $result.overall_status = 'blocked'
    $result.warnings += 'Approval required: pass -Approve'
    $result.exit_code = 2
    Write-SkillResult -Result $result
}

$result.approval_granted = $true
$catalog = if ($CatalogModel) { $CatalogModel } else { $script:DefaultCodingCatalogModelId }
$serving = if ($ServingModel) { $ServingModel } else { $script:DefaultCodingServingModelId }
$restPort = if ($Port -gt 0) { $Port } else { $script:DefaultCodingOvmsPort }

Add-ContinueOvmsConfigToResult -Result $result -Approve:$Approve -Apply:$Apply `
    -CatalogModelId $catalog -ServingModel $serving -Port $restPort

$result.overall_status = $result.functional_status
Write-SkillResult -Result $result
