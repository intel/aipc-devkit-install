# Upgrade the Dev Kit OVMS bundle (ovms\ovms.exe) for D9 and newer OpenVINO runtimes.
# Dev Kit first install may ship OVMS v2026.0; D9 (Qwen3.6-35B-A3B) expects >= 2026.3.1 python_on.
param(
    [string]$InstallRoot = $null,
    [string]$Version = '2026.3.1',
    [switch]$Approve,
    [switch]$WhatIf
)

. "$PSScriptRoot\_skill-common.ps1"

$skillId = 'intel-ovms-runtime-upgrade'
$result = Get-SkillResultSkeleton -SkillId $skillId -RiskClass 'network' -FunctionalStatus 'fail'
$result.approval_granted = [bool]$Approve

$resolved = Find-DevKitOvmsAgenticScript -InstallRoot $InstallRoot
if (-not $resolved) {
    $result.warnings += 'ovms_agentic_setup.ps1 not found; set InstallRoot or clone Dev Kit'
    $result.exit_code = 1
    Write-SkillResult -Result $result
    return
}

$ovmsWorkingDir = Split-Path -Path $resolved.script -Parent
$ovmsBundleDir = Join-Path $ovmsWorkingDir 'ovms'
$ovmsExe = Join-Path $ovmsBundleDir 'ovms.exe'

$result.ovms_working_dir = $ovmsWorkingDir
$result.target_version = $Version

if (Test-Path -LiteralPath $ovmsExe) {
    $result.ovms_version_before = (Get-Item -LiteralPath $ovmsExe).VersionInfo.FileVersion
}

if (-not (Test-ApprovalRequired -RiskClass 'network' -Approve:$Approve)) {
    $result.functional_status = 'blocked'
    $result.warnings += 'Network download requires -Approve'
    $result.exit_code = 0
    Write-SkillResult -Result $result
    return
}

$tag = "v$Version"
$zipName = "ovms_windows_${Version}_python_on.zip"
$zipUrl = "https://github.com/openvinotoolkit/model_server/releases/download/$tag/$zipName"
$result.logs += "download_url=$zipUrl"

if ($WhatIf) {
    $result.functional_status = 'pass'
    $result.warnings += 'WhatIf: no download or file changes'
    $result.exit_code = 0
    Write-SkillResult -Result $result
    return
}

$tempRoot = Join-Path $env:TEMP "ovms-upgrade-$Version-$(Get-Random)"
$zipPath = Join-Path $tempRoot $zipName
try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing

    $extractDir = Join-Path $tempRoot 'extract'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force

    $newBundle = Join-Path $extractDir 'ovms'
    if (-not (Test-Path -LiteralPath (Join-Path $newBundle 'ovms.exe'))) {
        throw "Extracted package missing ovms\ovms.exe under $extractDir"
    }

    if (Test-Path -LiteralPath $ovmsBundleDir) {
        $backup = Join-Path $ovmsWorkingDir ("ovms.pre-$Version." + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Rename-Item -LiteralPath $ovmsBundleDir -NewName (Split-Path -Leaf $backup)
        $result.logs += "backup=$backup"
    }

    Move-Item -LiteralPath $newBundle -Destination $ovmsBundleDir

    $setupVars = Join-Path $ovmsBundleDir 'setupvars.ps1'
    if (Test-Path -LiteralPath $setupVars) {
        try { & $setupVars | Out-Null } catch { $result.warnings += "setupvars.ps1: $_" }
    }

    $result.ovms_version_after = (Get-Item -LiteralPath $ovmsExe).VersionInfo.FileVersion
    $result.functional_status = 'pass'
    $result.exit_code = 0
    $d9 = $script:DefaultAgentModelId
    $result.warnings += "Re-test D9: ovms_agentic_setup.ps1 -Model '$d9' -Target GPU -Pull (junction layout; no absolute -CacheDir)"
}
catch {
    $result.functional_status = 'fail'
    $result.warnings += $_.Exception.Message
    $result.exit_code = 1
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$result.overall_status = $result.functional_status
Write-SkillResult -Result $result
