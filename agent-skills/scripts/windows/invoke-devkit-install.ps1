param(
    [switch]$Approve,
    [string]$InstallRoot = $null,
    [ValidateSet('install', 'gui')]
    [string]$SetupCommand = 'install',
    [switch]$Silent,
    [switch]$PreflightOnly,
    [int]$MinFreeDiskGb = 100,
    [switch]$SkipSetup2,
    [switch]$Setup2Only,
    [switch]$ForceSetup2,
    [string]$DevKitWorkingDir = 'C:\Intel',
    [switch]$Setup2InProcess,
    [switch]$Setup2Full,
    [switch]$Setup2RunGenAiDependencies,
    [switch]$Setup2StopWhenGenAiReady,
    [switch]$Elevate,
    [switch]$ElevatedChild,
    [string]$InstallJobId = '',
    [switch]$WaitInstallJob,
    [int]$UacAcceptanceSeconds = 90
)

. "$PSScriptRoot\_skill-common.ps1"

$installerScriptPath = $PSCommandPath

function Complete-IntelDevKitInstall {
    param([object]$Result)
    if ($InstallJobId -and $ElevatedChild) {
        Save-DevKitInstallJobResult -JobId $InstallJobId -Result $Result
    }
    Write-SkillResult -Result $Result
}

if ($WaitInstallJob) {
    if (-not $InstallJobId) {
        $result = Get-SkillResultSkeleton -SkillId 'intel-devkit-install' -RiskClass 'install' -FunctionalStatus 'blocked'
        $result.error = @{
            code        = 'INSTALL_JOB_ID_REQUIRED'
            message     = 'Pass -InstallJobId with -WaitInstallJob'
            remediation = 'Use the job_id from the prior -Elevate response'
        }
        $result.exit_code = 2
        Write-SkillResult -Result $result
    }
    $jobStatus = Get-DevKitInstallJobStatus -JobId $InstallJobId
    Write-DevKitInstallJobPollSkillResult -JobId $InstallJobId -Status $jobStatus
}

if ($ElevatedChild -and $InstallJobId) {
    try {
        $imported = Import-DevKitInstallJobParameters -JobId $InstallJobId
        foreach ($key in $imported.Keys) {
            $val = $imported[$key]
            if ($val -is [System.Management.Automation.PSCustomObject]) { continue }
            switch ($key) {
                'Approve' { $Approve = [bool]$val; break }
                'Silent' { $Silent = [bool]$val; break }
                'PreflightOnly' { $PreflightOnly = [bool]$val; break }
                'SkipSetup2' { $SkipSetup2 = [bool]$val; break }
                'Setup2Only' { $Setup2Only = [bool]$val; break }
                'ForceSetup2' { $ForceSetup2 = [bool]$val; break }
                'Setup2InProcess' { $Setup2InProcess = [bool]$val; break }
                'Setup2Full' { $Setup2Full = [bool]$val; break }
                'Setup2RunGenAiDependencies' { $Setup2RunGenAiDependencies = [bool]$val; break }
                'Setup2StopWhenGenAiReady' { $Setup2StopWhenGenAiReady = [bool]$val; break }
                'InstallRoot' { if ($val) { $InstallRoot = "$val" }; break }
                'SetupCommand' { if ($val) { $SetupCommand = "$val" }; break }
                'MinFreeDiskGb' { $MinFreeDiskGb = [int]$val; break }
                'DevKitWorkingDir' { if ($val) { $DevKitWorkingDir = "$val" }; break }
            }
        }
    } catch {
        $result = Get-SkillResultSkeleton -SkillId 'intel-devkit-install' -RiskClass 'install' -FunctionalStatus 'fail'
        $result.error = @{
            code        = 'INSTALL_JOB_MANIFEST_INVALID'
            message     = $_.Exception.Message
            remediation = 'Re-run install with -Approve -Elevate'
        }
        $result.exit_code = 1
        if ($InstallJobId) { Save-DevKitInstallJobResult -JobId $InstallJobId -Result $result }
        Complete-IntelDevKitInstall -Result $result
    }
    Write-DevKitInstallJobProgress -JobId $InstallJobId -Phase 'running' `
        -Message 'Elevated install session started (Setup_1 and Setup_2 may take hours)' -ProcessId $PID
}

if (-not $PSBoundParameters.ContainsKey('Silent')) {
    $Silent = ($SetupCommand -eq 'install')
}

$skillId = 'intel-devkit-install'

$result = Get-SkillResultSkeleton -SkillId $skillId -RiskClass 'install' -FunctionalStatus 'fail'

if (-not (Test-ApprovalRequired -RiskClass 'install' -Approve:$Approve)) {
    $result.functional_status = 'blocked'
    $result.overall_status = 'blocked'
    $result.warnings += 'Approval required: pass -Approve'
    $result.exit_code = 2
    Complete-IntelDevKitInstall -Result $result
}

$result.approval_granted = $true
$root = if ($InstallRoot) { $InstallRoot } else { Find-DevKitInstallRoot }

if (-not $root) {
    $result.error = @{
        code        = 'DEVKIT_ROOT_NOT_FOUND'
        message     = 'Dev Kit installer repository root not found'
        remediation = 'Clone training.developer.aipc with agent-skills at repo root, or set AIPC_DEVKIT_INSTALL_ROOT'
    }
    Complete-IntelDevKitInstall -Result $result
}
$result.devkit_install_root = $root
$result.devkit_working_dir = $DevKitWorkingDir
if ($DevKitWorkingDir -and $DevKitWorkingDir -ne 'C:\Intel') {
    $env:AIPC_DEVKIT_WORKING_DIR = $DevKitWorkingDir
    $result.warnings += "DevKitWorkingDir=$DevKitWorkingDir; verify V3 also checks AIPC_DEVKIT_WORKING_DIR\openvino_genai"
}

$setup = Get-DevKitSetupScriptPath -InstallRoot $root
$setup2 = Get-DevKitSetup2ScriptPath -InstallRoot $root

if (-not $Setup2Only -and -not $setup) {
    $result.error = @{
        code        = 'SETUP_SCRIPT_MISSING'
        message     = 'Setup_1.ps1 not found under Windows_Software_Installation\WingetGUI_Installer'
        remediation = 'Verify installer clone is complete'
    }
    Complete-IntelDevKitInstall -Result $result
}

$willRunSetup2 = (-not $SkipSetup2) -and ($Setup2Only -or ($SetupCommand -eq 'install'))
if ($willRunSetup2 -and -not $setup2) {
    $result.error = @{
        code        = 'SETUP2_SCRIPT_MISSING'
        message     = 'Setup_2.ps1 not found under Windows_Software_Installation\WingetGUI_Installer'
        remediation = 'Verify installer clone includes Setup_2.ps1 for OpenVINO GenAI'
    }
    Complete-IntelDevKitInstall -Result $result
}

if ($setup) { $result.logs += $setup }
if ($setup2) { $result.logs += $setup2 }

$appsJson = Get-DevKitApplicationsJsonPath -InstallRoot $root
if ($appsJson) {
    $result.applications_json = $appsJson
}

# I1 - preflight
$isAdmin = Test-DevKitAdministrator
$willRequestElevation = (-not $ElevatedChild) -and (-not $isAdmin) -and $Elevate -and (-not $PreflightOnly)

if ($willRequestElevation) {
    Add-VerifyCheck -Result $result -Check @{
        id      = 'I1-admin'
        status  = 'skip'
        message = 'Elevation job will request Administrator via UAC (-Elevate)'
    }
} else {
    Add-VerifyCheck -Result $result -Check @{
        id      = 'I1-admin'
        status  = $(if ($isAdmin) { 'pass' } else { 'fail' })
        message = $(if ($isAdmin) { 'Running elevated' } else { 'Administrator required; use -Elevate for UAC elevation (Hermes) or re-run elevated' })
    }
}

$hasNetwork = Test-DevKitInstallNetwork
Add-VerifyCheck -Result $result -Check @{
    id      = 'I1-network'
    status  = $(if ($hasNetwork) { 'pass' } else { 'fail' })
    message = $(if ($hasNetwork) { 'Network reachable (microsoft.com:443)' } else { 'Network check failed' })
}

$diskCheckPath = if ($willRunSetup2) { $DevKitWorkingDir } else { $root }
$freeGb = Get-DevKitFreeDiskSpaceGb -Path $diskCheckPath
if ($null -eq $freeGb) {
    Add-VerifyCheck -Result $result -Check @{
        id      = 'I1-disk'
        status  = 'skip'
        message = 'Could not read free disk space'
    }
} elseif ($freeGb -lt 20) {
    Add-VerifyCheck -Result $result -Check @{
        id      = 'I1-disk'
        status  = 'fail'
        message = ('Free space {0} GB - critically low (under 20 GB)' -f $freeGb)
    }
} else {
    $diskMsg = "Free space ${freeGb} GB on drive for install path"
    if ($freeGb -lt $MinFreeDiskGb) {
        $result.warnings += "Disk below recommended $MinFreeDiskGb GB; Setup scripts may still proceed with a warning"
        $diskMsg += " (recommended >= $MinFreeDiskGb GB)"
    }
    Add-VerifyCheck -Result $result -Check @{
        id      = 'I1-disk'
        status  = 'pass'
        message = $diskMsg
    }
}

$preflightFails = @($result.checks | Where-Object { $_.id -like 'I1-*' -and $_.status -eq 'fail' })
if ($preflightFails.Count -gt 0) {
    $result.functional_status = 'blocked'
    $result.overall_status = 'blocked'
    $result.warnings += 'Fix preflight failures before install (admin, network, disk)'
    $result.exit_code = 2
    Complete-IntelDevKitInstall -Result $result
}

if ($willRequestElevation) {
    $invokeParams = @{}
    foreach ($key in $PSBoundParameters.Keys) {
        if ($key -in @('Elevate', 'ElevatedChild', 'WaitInstallJob', 'InstallJobId', 'UacAcceptanceSeconds')) { continue }
        $invokeParams[$key] = $PSBoundParameters[$key]
    }
    $jobStart = Start-DevKitInstallElevationJob -InstallerScriptPath $installerScriptPath `
        -InvokeParameters $invokeParams -UacAcceptanceSeconds $UacAcceptanceSeconds

    $result | Add-Member -NotePropertyName install_job -NotePropertyValue $jobStart -Force
    if ($jobStart.job_id) {
        Set-IntelDevKitInstallJobPollFields -Result $result -JobId $jobStart.job_id
    }

    if (-not $jobStart.ok -or $jobStart.phase -eq 'uac_denied') {
        $result.functional_status = 'blocked'
        $result.overall_status = 'blocked'
        $result.exit_code = 2
        $result.error = @{
            code        = 'UAC_DENIED'
            message     = $jobStart.message
            remediation = 'User must approve the Windows UAC prompt when Hermes starts elevation, then re-run with -Approve -Elevate'
        }
    } elseif ($jobStart.phase -eq 'running') {
        $result.functional_status = 'partial'
        $result.overall_status = 'partial'
        $result.exit_code = 0
        $result.warnings += 'Install running in elevated window; poll with -WaitInstallJob -InstallJobId'
        $result.warnings += 'After install completes, continue verify/OVMS/smoke from standard-user Hermes (not elevated)'
    } else {
        $result.functional_status = 'partial'
        $result.overall_status = 'partial'
        $result.exit_code = 0
        $result.warnings += 'Waiting for UAC; poll with -WaitInstallJob -InstallJobId if install does not start'
    }
    Complete-IntelDevKitInstall -Result $result
}

if ($PreflightOnly) {
    $result.functional_status = 'pass'
    $result.overall_status = 'pass'
    $result.warnings += 'PreflightOnly: Setup_1.ps1 and Setup_2.ps1 were not invoked'
    $result.exit_code = 0
    Complete-IntelDevKitInstall -Result $result
}

$beforeStatus = Get-DevKitStatus -InstallRoot $root
$result.devkit_status_before = $beforeStatus.status

$wingetInstallerDir = if ($setup) { Split-Path -Path $setup -Parent } else { Split-Path -Path $setup2 -Parent }
Get-ChildItem -LiteralPath $wingetInstallerDir -Recurse -Include '*.ps1' -File -ErrorAction SilentlyContinue |
    Unblock-File -ErrorAction SilentlyContinue

$result.warnings += 'Setup_1.ps1 may take a long time (Visual Studio, Python, etc.); run from an interactive Admin session'
$result.warnings += 'Setup_2.ps1 downloads OpenVINO GenAI and related content; long runtime and network required'
if ($Setup2Only -and -not $Setup2Full) {
    $result.warnings += 'Setup2Only default: genai-minimal (verify V3); use -Setup2Full for full upstream Setup_2.ps1 (hours)'
} elseif (-not $Setup2Full) {
    $result.warnings += 'Setup_2 default: genai-minimal after Setup_1; use -Setup2Full for notebooks/LlamaCpp upstream script'
}
$result.warnings += 'OVMS is not installed by Setup_1 or Setup_2; run intel-ovms-agentic-setup after install completes'

$run = $null
$setupHint = $null
$summary = @{}

if (-not $Setup2Only) {
    if ($Silent -and $SetupCommand -eq 'install') {
        $result.warnings += 'Using Setup_1 install via child PowerShell (ExecutionPolicy Bypass for unsigned/cloned scripts)'
        $result.setup_invoke_mode = 'silent-install'
    } else {
        $result.setup_invoke_mode = $SetupCommand
    }

    $run = Invoke-DevKitSetup1 -SetupScriptPath $setup -Command $SetupCommand -Silent:$Silent
    $result.logs += $run.log_line
    foreach ($line in $run.output) {
        if ($line) { $result.logs += $line }
    }

    $tail = @($run.output | Select-Object -Last 40)
    $result | Add-Member -NotePropertyName setup_output_tail -NotePropertyValue $tail -Force
    $setupHint = Get-DevKitSetup1FailureHint -OutputLines $run.output
    if ($setupHint) {
        $result | Add-Member -NotePropertyName setup_failure_hint -NotePropertyValue $setupHint -Force
    }

    $i2Message = "Setup_1.ps1 $SetupCommand exit $($run.exit_code)$(if ($run.silent) { ' (child PS install)' } else { '' })"
    if ($setupHint) { $i2Message += (' - ' + $setupHint) }

    Add-VerifyCheck -Result $result -Check @{
        id      = 'I2-cli-invoke'
        status  = $(if ($run.exit_code -eq 0) { 'pass' } else { 'fail' })
        message = $i2Message
    }

    $installLog = Get-DevKitInstallLogPath
    if (Test-Path $installLog) {
        $result.logs += $installLog
        $result.install_log = $installLog
        if ($run.exit_code -ne 0) {
            $logTail = Get-DevKitInstallLogTailLines -InstallLogPath $installLog
            if ($logTail.Count -gt 0) {
                $result | Add-Member -NotePropertyName install_log_tail -NotePropertyValue $logTail -Force
            }
        }
    }

    $summary = Get-DevKitSetupInstallSummaryFromOutput -OutputLines $run.output
    if ($summary.Count -gt 0) {
        $result | Add-Member -NotePropertyName install_summary -NotePropertyValue $summary -Force
    }

    $idempotentNote = if ($beforeStatus.status -eq 'present' -and $run.exit_code -eq 0) {
        'Re-run on present Dev Kit; Setup_1 skips packages already installed'
    } else {
        'First install or top-up completed invoke'
    }
    Add-VerifyCheck -Result $result -Check @{
        id      = 'I4-idempotency'
        status  = $(if ($run.exit_code -eq 0) { 'pass' } else { 'skip' })
        message = $idempotentNote
    }
} else {
    Add-VerifyCheck -Result $result -Check @{ id = 'I2-cli-invoke'; status = 'skip'; message = 'Setup2Only: Setup_1.ps1 not invoked' }
    Add-VerifyCheck -Result $result -Check @{ id = 'I4-idempotency'; status = 'skip'; message = 'Setup2Only' }
}

$run2 = $null
$genaiExpectedPath = Join-Path $DevKitWorkingDir 'openvino_genai'
$setup1OkForSetup2 = $Setup2Only -or ($null -ne $run -and $run.exit_code -eq 0)

if ($willRunSetup2 -and -not $setup1OkForSetup2) {
    Add-VerifyCheck -Result $result -Check @{
        id      = 'I5-setup2-invoke'
        status  = 'skip'
        message = 'Setup_2.ps1 skipped because Setup_1 did not exit 0'
    }
    Add-VerifyCheck -Result $result -Check @{
        id      = 'I6-openvino-genai'
        status  = 'skip'
        message = 'Setup_2 not run'
    }
} elseif ($willRunSetup2) {
    $genaiState = Test-DevKitOpenVinoGenAiReady -DevKitWorkingDir $DevKitWorkingDir
    if ($genaiState.ready -and -not $ForceSetup2) {
        Add-VerifyCheck -Result $result -Check @{
            id      = 'I5-setup2-invoke'
            status  = 'pass'
            message = "Graceful skip: openvino_genai already ready at $($genaiState.path) (verify V3); use -ForceSetup2 or -Setup2Full to re-run upstream Setup_2.ps1"
        }
        $result.openvino_genai_path = $genaiState.path
        $result.warnings += 'Setup_2 not invoked; existing openvino_genai satisfies skill I6 and verify V3'
    } elseif (-not $Setup2Full) {
        $run2 = Invoke-DevKitEnsureOpenVinoGenAiMinimal -DevKitWorkingDir $DevKitWorkingDir -RunGenAiDependencies:$Setup2RunGenAiDependencies
        $result.logs += $run2.log_line
        foreach ($line in $run2.output) {
            if ($line) { $result.logs += $line }
        }
        $result.setup2_mode = $run2.mode
        $tail2 = @($run2.output | Select-Object -Last 40)
        $result | Add-Member -NotePropertyName setup2_output_tail -NotePropertyValue $tail2 -Force
        Add-VerifyCheck -Result $result -Check @{
            id      = 'I5-setup2-invoke'
            status  = $(if ($run2.exit_code -eq 0) { 'pass' } else { 'fail' })
            message = "genai-minimal exit $($run2.exit_code) (DevKitWorkingDir=$DevKitWorkingDir)"
        }
    } else {
        $run2 = Invoke-DevKitSetup2 -SetupScriptPath $setup2 -DevKitWorkingDir $DevKitWorkingDir `
            -InProcess:$Setup2InProcess -StopWhenGenAiReady:$Setup2StopWhenGenAiReady
        if ($run2.meta_log) { $result.logs += $run2.meta_log }
        $result.logs += $run2.log_line
        foreach ($line in $run2.output) {
            if ($line) { $result.logs += $line }
        }
        if ($run2.truncated) {
            $result.warnings += 'Setup_2 stopped early: openvino_genai ready (Setup2StopWhenGenAiReady)'
        }
        $tail2 = @($run2.output | Select-Object -Last 40)
        $result | Add-Member -NotePropertyName setup2_output_tail -NotePropertyValue $tail2 -Force

        $i5Status = if ($run2.exit_code -eq 0) { 'pass' } else { 'fail' }
        if ($run2.truncated) { $i5Status = 'pass' }
        Add-VerifyCheck -Result $result -Check @{
            id      = 'I5-setup2-invoke'
            status  = $i5Status
            message = "Setup_2.ps1 exit $($run2.exit_code) (DevKitWorkingDir=$DevKitWorkingDir)$(if ($run2.truncated) { '; truncated after genai ready' } else { '' })"
        }
    }

    if (Test-Path -LiteralPath $genaiExpectedPath) {
        $result.openvino_genai_path = $genaiExpectedPath
        Add-VerifyCheck -Result $result -Check @{
            id      = 'I6-openvino-genai'
            status  = 'pass'
            message = "Found at $genaiExpectedPath"
        }
    } else {
        Add-VerifyCheck -Result $result -Check @{
            id      = 'I6-openvino-genai'
            status  = 'fail'
            message = "openvino_genai not found at $genaiExpectedPath (verify V3 expects C:\Intel unless custom dir)"
        }
    }
} else {
    Add-VerifyCheck -Result $result -Check @{
        id      = 'I5-setup2-invoke'
        status  = 'skip'
        message = 'Setup_2 skipped (-SkipSetup2 or SetupCommand gui)'
    }
    Add-VerifyCheck -Result $result -Check @{
        id      = 'I6-openvino-genai'
        status  = 'skip'
        message = 'Setup_2 not requested'
    }
}

$uninstallJson = Get-DevKitUninstallJsonPath -InstallRoot $root
$afterStatus = Get-DevKitStatus -InstallRoot $root
$result.devkit_status_after = $afterStatus.status

Add-VerifyCheck -Result $result -Check @{
    id      = 'I3-state'
    status  = 'pass'
    message = "devkit_status_after=$($afterStatus.status); uninstall_json=$(if ($uninstallJson) { $uninstallJson } else { '(not found yet)' })"
}
if ($uninstallJson) { $result.uninstall_json = $uninstallJson }

$failedCount = if ($summary.ContainsKey('failed_installs')) { $summary['failed_installs'] } else { $null }
$i6Fail = @($result.checks | Where-Object { $_.id -eq 'I6-openvino-genai' -and $_.status -eq 'fail' }).Count -gt 0
$i5Fail = @($result.checks | Where-Object { $_.id -eq 'I5-setup2-invoke' -and $_.status -eq 'fail' }).Count -gt 0
$i2Fail = $null -ne $run -and $run.exit_code -ne 0

if ($i2Fail) {
    $result.functional_status = 'fail'
    $result.exit_code = 1
    $installLog = Get-DevKitInstallLogPath
    $remediation = "Review setup_output_tail, install_log_tail (if present), and $installLog"
    if ($setupHint) { $remediation = "$setupHint. $remediation" }
    $result.error = @{
        code        = 'SETUP_1_FAILED'
        message     = "Setup_1.ps1 exited with code $($run.exit_code)"
        remediation = $remediation
    }
} elseif ($i5Fail -or $i6Fail) {
    $result.functional_status = 'partial'
    $result.exit_code = 1
    $result.warnings += 'Setup_2 did not produce openvino_genai at expected path; review setup2_output_tail'
    if ($i5Fail) {
        $result.error = @{
            code        = 'SETUP_2_FAILED'
            message     = "Setup_2.ps1 exited with code $($run2.exit_code)"
            remediation = 'Review setup2_output_tail; run Setup_2.ps1 manually from WingetGUI_Installer with -ExecutionPolicy Bypass'
        }
    }
} elseif ($null -ne $failedCount -and $failedCount -gt 0) {
    $result.functional_status = 'partial'
    $result.exit_code = 1
    $result.warnings += "Setup_1 reported $failedCount failed package(s)"
} elseif ($afterStatus.status -eq 'absent' -and -not $Setup2Only) {
    $result.functional_status = 'partial'
    $result.exit_code = 0
    $result.warnings += 'Install finished but devkit_status still absent; check uninstall.json and winget logs'
} else {
    $result.functional_status = 'pass'
    $result.exit_code = 0
    $result.next_skill = 'intel-devkit-verify'
}

if ($afterStatus.status -ne 'absent') {
    Add-DevKitStandardUserHandoffWarnings -Result $result -Context post-install
}

$result.overall_status = $result.functional_status
Complete-IntelDevKitInstall -Result $result
