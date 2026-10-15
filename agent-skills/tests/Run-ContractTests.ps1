param(
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
$testsRoot = $PSScriptRoot
$agentSkillsRoot = Split-Path $testsRoot -Parent
$scriptsRoot = Join-Path $agentSkillsRoot 'scripts\windows'
$goldenRoot = Join-Path $testsRoot 'integration\golden-reports'

function ConvertFrom-SkillResultJson {
    param([string]$RawOutput)
    $start = $RawOutput.IndexOf('{')
    $end = $RawOutput.LastIndexOf('}')
    if ($start -lt 0 -or $end -le $start) {
        throw "No JSON object in output: $RawOutput"
    }
    $jsonText = $RawOutput.Substring($start, $end - $start + 1)
    return $jsonText | ConvertFrom-Json
}

function Compare-SkillResultToGolden {
    param(
        [object]$Actual,
        [object]$Golden,
        [string[]]$IgnorePaths = @('run_id', 'started_at', 'finished_at')
    )
    $issues = @()
    foreach ($prop in @('schema_id', 'skill_id', 'functional_status', 'overall_status', 'devkit_status', 'next_skill', 'exit_code')) {
        if ($Golden.PSObject.Properties.Name -contains $prop) {
            $g = $Golden.$prop
            $a = $Actual.$prop
            if ("$a" -ne "$g") {
                $issues += "Field $prop expected '$g' got '$a'"
            }
        }
    }
    if ($Golden.checks) {
        $goldenChecks = @{}
        foreach ($c in $Golden.checks) { $goldenChecks[$c.id] = $c.status }
        foreach ($c in $Actual.checks) {
            if ($goldenChecks.ContainsKey($c.id)) {
                if ($c.status -ne $goldenChecks[$c.id]) {
                    $issues += "Check $($c.id) expected $($goldenChecks[$c.id]) got $($c.status)"
                }
            }
        }
        foreach ($id in $goldenChecks.Keys) {
            $found = @($Actual.checks | Where-Object { $_.id -eq $id })
            if ($found.Count -eq 0) {
                $issues += "Missing check id $id"
            }
        }
    }
    return $issues
}

function Invoke-VerifyWithInstallRoot {
    param([string]$InstallRoot)
    $invokeArgs = @{}
    if ($InstallRoot) { $invokeArgs['InstallRoot'] = $InstallRoot }
    $out = & (Join-Path $scriptsRoot 'invoke-devkit-verify.ps1') @invokeArgs 2>&1 | Out-String
    return ConvertFrom-SkillResultJson -RawOutput $out
}

$failures = 0

Write-Host 'Contract: intel-devkit-verify (devkit absent)'
$absentDir = Join-Path $testsRoot 'fixtures\devkit-absent-not-installed'
$actualAbsent = Invoke-VerifyWithInstallRoot -InstallRoot $absentDir
$goldenAbsent = Get-Content (Join-Path $goldenRoot 'verify-devkit-absent.json') -Raw | ConvertFrom-Json
$issues = Compare-SkillResultToGolden -Actual $actualAbsent -Golden $goldenAbsent
if ($issues.Count -gt 0) {
    $failures++
    $issues | ForEach-Object { Write-Warning $_ }
} else {
    Write-Host '  PASS'
}

Write-Host 'Contract: intel-devkit-verify (fixture present-minimal)'
$presentRoot = Join-Path $testsRoot 'fixtures\devkit-present-minimal'
$actualPresent = Invoke-VerifyWithInstallRoot -InstallRoot $presentRoot
if ($actualPresent.devkit_status -ne 'present') {
    $failures++
    Write-Warning "Expected devkit_status=present got $($actualPresent.devkit_status)"
} else {
    Write-Host '  PASS devkit_status=present'
}
$v1 = @($actualPresent.checks | Where-Object { $_.id -eq 'V1-installer-state' -and $_.status -eq 'pass' })
if ($v1.Count -eq 0) {
    $failures++
    Write-Warning 'V1-installer-state should pass for present-minimal fixture'
}

Write-Host 'Contract: intel-devkit-verify next_skill routing'
. (Join-Path $scriptsRoot '_skill-common.ps1')
$mockInstallGap = [pscustomobject]@{
    devkit_status = 'partial'
    checks        = @(
        @{ id = 'V3-openvino-genai'; status = 'fail' },
        @{ id = 'V4-ovms-installed'; status = 'fail' }
    )
}
$fixturePresentMinimal = Join-Path $testsRoot 'fixtures\devkit-present-minimal'
$fixtureAbsentRoot = Join-Path $testsRoot 'fixtures\devkit-absent'
$mockGenaiNoOvmsExe = [pscustomobject]@{
    devkit_status       = 'present'
    devkit_install_root = $fixturePresentMinimal
    checks              = @(
        @{ id = 'V3-openvino-genai'; status = 'pass' },
        @{ id = 'V4-ovms-installed'; status = 'fail' }
    )
}
$mockGenaiNoOvmsSlice = [pscustomobject]@{
    devkit_status       = 'present'
    devkit_install_root = $fixtureAbsentRoot
    checks              = @(
        @{ id = 'V3-openvino-genai'; status = 'pass' },
        @{ id = 'V4-ovms-installed'; status = 'fail' }
    )
}
$mockOvmsOnly = [pscustomobject]@{
    devkit_status = 'present'
    checks        = @(
        @{ id = 'V3-openvino-genai'; status = 'pass' },
        @{ id = 'V4-ovms-installed'; status = 'pass' },
        @{ id = 'V4-ovms-running'; status = 'skip' }
    )
}
$routingOk = $true
if ((Resolve-IntelDevkitVerifyNextSkill -Result $mockInstallGap) -ne 'intel-devkit-install') {
    $failures++
    $routingOk = $false
    Write-Warning 'Expected next_skill intel-devkit-install when V3 fail'
}
if ((Resolve-IntelDevkitVerifyNextSkill -Result $mockGenaiNoOvmsExe) -ne 'intel-ovms-agentic-setup') {
    $failures++
    $routingOk = $false
    Write-Warning 'Expected next_skill intel-ovms-agentic-setup when V3 pass and V4 ovms.exe missing (OVMS scripts in install root)'
}
if ((Resolve-IntelDevkitVerifyNextSkill -Result $mockGenaiNoOvmsSlice) -ne 'intel-devkit-ovms-slice-fetch') {
    $failures++
    $routingOk = $false
    Write-Warning 'Expected next_skill intel-devkit-ovms-slice-fetch when V3 pass, V4 fail, and OVMS folder missing under install root'
}
if ((Resolve-IntelDevkitVerifyNextSkill -Result $mockOvmsOnly) -ne 'intel-ovms-agentic-setup') {
    $failures++
    $routingOk = $false
    Write-Warning 'Expected next_skill intel-ovms-agentic-setup when OVMS not running'
}
if ($routingOk) {
    Write-Host '  PASS verify next_skill routing'
}

Write-Host 'Contract: verify presentation after GenAI pass (OVMS runtime missing)'
$mockVerifyOvmsGap = [pscustomobject]@{
    skill_id           = 'intel-devkit-verify'
    functional_status  = 'partial'
    devkit_status      = 'present'
    devkit_install_root = $fixturePresentMinimal
    next_skill         = 'intel-ovms-agentic-setup'
    checks             = @(
        @{ id = 'V3-openvino-genai'; status = 'pass' },
        @{ id = 'V4-ovms-installed'; status = 'fail' }
    )
}
$presOvmsGap = Build-SkillUserPresentation -Result $mockVerifyOvmsGap
if ($presOvmsGap.user_message -match 'intel-') {
    $failures++
    Write-Warning 'Verify OVMS-only gap user_message should not name a skill'
} elseif (($presOvmsGap.agent_next_steps -join ' ') -notmatch 'intel-ovms-agentic-setup') {
    $failures++
    Write-Warning 'Verify OVMS-only gap should keep intel-ovms-agentic-setup in agent_next_steps'
} else {
    Write-Host '  PASS verify partial_needs_ovms presentation'
}

Write-Host 'Contract: verify agent-ready pass suggests provider config'
$mockVerifyAgentPass = [pscustomobject]@{
    skill_id              = 'intel-devkit-verify'
    functional_status     = 'pass'
    devkit_status         = 'present'
    agent_inference_ready = $true
    checks                = @(
        @{ id = 'V3-openvino-genai'; status = 'pass' },
        @{ id = 'V4-ovms-installed'; status = 'pass' },
        @{ id = 'V4-ovms-running'; status = 'pass' },
        @{ id = 'V6-agentic-inference'; status = 'pass' }
    )
}
Set-IntelAgentProviderConfigNextSkillIfReady -Result $mockVerifyAgentPass
if ($mockVerifyAgentPass.next_skill -ne 'intel-agent-provider-config') {
    $failures++
    Write-Warning 'Expected next_skill intel-agent-provider-config when verify pass and agent_inference_ready'
} else {
    $presAgentPass = Build-SkillUserPresentation -Result $mockVerifyAgentPass
    if ($presAgentPass.user_message -match 'intel-') {
        $failures++
        Write-Warning 'Verify agent-ready pass user_message should not name a skill'
    } elseif (($presAgentPass.agent_next_steps -join ' ') -notmatch 'intel-agent-provider-config') {
        $failures++
        Write-Warning 'Verify agent-ready pass should keep intel-agent-provider-config in agent_next_steps'
    } else {
        Write-Host '  PASS verify agent handoff next_skill and presentation'
    }
}

Write-Host 'Contract: OVMS agent profile pass suggests provider config'
$mockOvmsAgentPass = [pscustomobject]@{
    skill_id              = 'intel-ovms-agentic-setup'
    functional_status     = 'pass'
    model_profile         = 'agent'
    agent_inference_ready = $true
    checks                = @(
        @{ id = 'O2-health'; status = 'pass' },
        @{ id = 'O4-chat'; status = 'pass' },
        @{ id = 'A1-agentic-inference'; status = 'pass' }
    )
}
Set-IntelAgentProviderConfigNextSkillIfReady -Result $mockOvmsAgentPass
if ($mockOvmsAgentPass.next_skill -ne 'intel-agent-provider-config') {
    $failures++
    Write-Warning 'Expected next_skill intel-agent-provider-config when OVMS agent pass and agent_inference_ready'
} else {
    $presOvmsAgent = Build-SkillUserPresentation -Result $mockOvmsAgentPass
    if ($presOvmsAgent.user_message -match 'intel-') {
        $failures++
        Write-Warning 'OVMS agent pass user_message should not name a skill'
    } elseif (($presOvmsAgent.agent_next_steps -join ' ') -notmatch 'intel-agent-provider-config') {
        $failures++
        Write-Warning 'OVMS agent pass should keep provider config in agent_next_steps'
    } else {
        Write-Host '  PASS OVMS agent handoff next_skill and presentation'
    }
}

Write-Host 'Contract: intel-devkit-install job user presentation'
$mockInstallRunning = [pscustomobject]@{
    skill_id           = 'intel-devkit-install'
    functional_status  = 'partial'
    checks             = @()
    warnings           = @('Install running in elevated window; poll with -WaitInstallJob -InstallJobId')
    install_job        = @{ job_id = 'test-job-id'; phase = 'running'; pid = 1 }
}
Set-IntelDevKitInstallJobPollFields -Result $mockInstallRunning -JobId 'test-job-id'
$pres = Build-SkillUserPresentation -Result $mockInstallRunning
if ($pres.user_message -match '\.ps1' -or ($pres.next_steps -join ' ') -match 'powershell\.exe') {
    $failures++
    Write-Warning 'Install job presentation should not include script paths in user channel'
} elseif ($pres.user_message -notmatch 'still running') {
    $failures++
    Write-Warning 'Install job user_message should indicate the install is still running'
} else {
    Write-Host '  PASS install job partial presentation'
}

Write-Host 'Contract: OVMS catalog vs advertised model matching'
. (Join-Path $scriptsRoot '_skill-common.ps1')
$matchCases = @(
    @{
        advertised = @('OpenVINO/Qwen3.5-0.8B-int4-ov')
        catalog    = 'OpenVINO/Qwen3.5-0.8B-int4-ov'
        expect     = $true
    },
    @{
        advertised = @('OpenVINO/Qwen3.5-0.8B-int4-ov')
        catalog    = 'Qwen3.5-0.8B'
        expect     = $true
    },
    @{
        advertised = @('Qwen3.5-0.8B')
        catalog    = 'OpenVINO/Qwen3.5-0.8B-int4-ov'
        expect     = $true
    },
    @{
        advertised = @('OpenVINO/Qwen3.6-35B-A3B-int4-ov')
        catalog    = 'OpenVINO/Qwen3.5-0.8B-int4-ov'
        expect     = $false
    },
    @{
        advertised = @('OpenVINO/Muse-Glimmer-30B-int4-ov')
        catalog    = 'OpenVINO/Muse-Glimmer-30B-int4-ov'
        expect     = $true
    },
    @{
        advertised = @('OpenVINO/Qwen3.6-35B-A3B-int4-ov')
        catalog    = 'OpenVINO/Muse-Glimmer-30B-int4-ov'
        expect     = $false
    }
)
foreach ($case in $matchCases) {
    $m = Find-OvmsAdvertisedModelByCatalog -AdvertisedIds $case.advertised -CatalogModelId $case.catalog
    if ([bool]$m.matched -ne $case.expect) {
        $failures++
        Write-Warning "Model match catalog=$($case.catalog) advertised=$($case.advertised -join ',') expected=$($case.expect) got=$($m.matched) msg=$($m.message)"
    }
}
if ($failures -eq 0) {
    Write-Host '  PASS catalog regex / stem matching'
}

Write-Host 'Contract: fetch-devkit-ovms-slice (WhatIf blocked without Approve)'
$sliceBlocked = & (Join-Path $scriptsRoot 'fetch-devkit-ovms-slice.ps1') -InstallRoot (Join-Path $testsRoot 'fixtures\devkit-absent-not-installed') 2>&1 | Out-String
try {
    $sliceB = ConvertFrom-SkillResultJson -RawOutput $sliceBlocked
    if ($sliceB.functional_status -ne 'blocked') {
        $failures++
        Write-Warning "Expected functional_status=blocked got $($sliceB.functional_status)"
    } else {
        Write-Host '  PASS blocked without -Approve'
    }
} catch {
    $failures++
    Write-Warning "fetch-devkit-ovms-slice blocked test failed: $($_.Exception.Message)"
}

Write-Host 'Contract: fetch-devkit-ovms-slice (WhatIf with Approve)'
$sliceWhatIf = & (Join-Path $scriptsRoot 'fetch-devkit-ovms-slice.ps1') -InstallRoot (Join-Path $testsRoot 'fixtures\devkit-absent-not-installed') -Approve -WhatIf 2>&1 | Out-String
try {
    $sliceW = ConvertFrom-SkillResultJson -RawOutput $sliceWhatIf
    if ($sliceW.functional_status -ne 'pass') {
        $failures++
        Write-Warning "Expected functional_status=pass for WhatIf got $($sliceW.functional_status)"
    } else {
        Write-Host '  PASS WhatIf'
    }
} catch {
    $failures++
    Write-Warning "fetch-devkit-ovms-slice WhatIf test failed: $($_.Exception.Message)"
}

Write-Host 'Contract: intel-endpoint-smoke-test-report (no OVMS — expect fail)'
$smokeOut = & (Join-Path $scriptsRoot 'endpoint-smoke-test.ps1') -BaseUrl 'http://127.0.0.1:59999/v3' 2>&1 | Out-String
try {
    $smoke = ConvertFrom-SkillResultJson -RawOutput $smokeOut
    if ($smoke.functional_status -ne 'fail') {
        $failures++
        Write-Warning "Expected functional_status=fail got $($smoke.functional_status)"
    } else {
        Write-Host '  PASS functional_status=fail when endpoint down'
    }
} catch {
    $failures++
    Write-Warning "Smoke test parse/run failed: $($_.Exception.Message)"
}

if ($failures -gt 0) {
    Write-Error "$failures contract test group(s) failed"
    exit 1
}
Write-Host 'All contract tests passed.'
exit 0
