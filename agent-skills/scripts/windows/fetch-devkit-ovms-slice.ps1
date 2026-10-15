# Fetch only Windows_Software_Installation/OVMS from the Dev Kit installer repo (no full clone).
# Use when agent-skills is present but training.developer.aipc was never cloned (OVMS_SCRIPT_NOT_FOUND).
param(
    [string]$InstallRoot = $null,
    [string]$RepoUrl = $null,
    [string]$Ref = $null,
    [switch]$Approve,
    [switch]$WhatIf,
    [switch]$Force,
    [switch]$IncludeOvmsRuntime,
    [string]$OvmsVersion = '2026.3.1'
)

. "$PSScriptRoot\_skill-common.ps1"

$skillId = 'intel-devkit-ovms-slice-fetch'
$result = Get-SkillResultSkeleton -SkillId $skillId -RiskClass 'network' -FunctionalStatus 'fail'
$result.approval_granted = [bool]$Approve

$script:OvmsRelPosix = 'Windows_Software_Installation/OVMS'
$script:OvmsRelWin = 'Windows_Software_Installation\OVMS'

function Test-GitCliAvailable {
    try {
        $null = & git --version 2>&1
        return $true
    } catch {
        return $false
    }
}

function Get-DefaultDevKitRepoUrl {
    if ($env:AIPC_DEVKIT_REPO_URL) {
        return $env:AIPC_DEVKIT_REPO_URL.Trim()
    }
    return 'https://github.com/intel-innersource/training.developer.aipc.git'
}

function Get-DefaultDevKitRepoRef {
    if ($env:AIPC_DEVKIT_REPO_REF) {
        return $env:AIPC_DEVKIT_REPO_REF.Trim()
    }
    if ($env:AIPC_DEVKIT_REPO_BRANCH) {
        return $env:AIPC_DEVKIT_REPO_BRANCH.Trim()
    }
    return 'DevKit4.0'
}

function Get-DevKitOvmsAgenticScriptPath {
    param([string]$Root)
    if (-not $Root) { return $null }
    $p = Join-Path $Root "$script:OvmsRelWin\ovms_agentic_setup.ps1"
    if (Test-Path -LiteralPath $p) { return $p }
    return $null
}

function Invoke-GitCapture {
    param(
        [string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string[]]$GitArgs
    )
    $argLine = ($GitArgs | ForEach-Object {
            if ($_ -match '\s') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
        }) -join ' '
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($WorkingDirectory) {
            $out = & git -C $WorkingDirectory @GitArgs 2>&1
        } else {
            $out = & git @GitArgs 2>&1
        }
        $code = $LASTEXITCODE
        return @{ exit_code = $code; output = ($out | Out-String).Trim() }
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Unblock-DevKitOvmsScripts {
    param([string]$OvmsDir)
    if (-not (Test-Path -LiteralPath $OvmsDir)) { return }
    Get-ChildItem -LiteralPath $OvmsDir -Recurse -Filter '*.ps1' -ErrorAction SilentlyContinue |
        ForEach-Object { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue }
}

function Copy-DevKitOvmsTree {
    param(
        [string]$SourceOvmsDir,
        [string]$DestOvmsDir
    )
    $parent = Split-Path -Path $DestOvmsDir -Parent
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    if (Test-Path -LiteralPath $DestOvmsDir) {
        Remove-Item -LiteralPath $DestOvmsDir -Recurse -Force
    }
    Copy-Item -LiteralPath $SourceOvmsDir -Destination $DestOvmsDir -Recurse -Force
}

function Fetch-DevKitOvmsSliceViaSparseClone {
    param(
        [string]$Repo,
        [string]$Branch,
        [string]$DestInstallRoot
    )

    $tempRoot = Join-Path $env:TEMP ("aipc-ovms-slice-" + [guid]::NewGuid().ToString('n'))
    try {
        $cloneArgs = @(
            'clone', '--filter=blob:none', '--depth', '1', '--sparse',
            '--branch', $Branch,
            $Repo, $tempRoot
        )
        $result.logs += "git $($cloneArgs -join ' ')"
        $clone = Invoke-GitCapture -GitArgs $cloneArgs
        if ($clone.exit_code -ne 0) {
            throw "git clone failed (exit $($clone.exit_code)): $($clone.output)"
        }

        $sparse = Invoke-GitCapture -WorkingDirectory $tempRoot -GitArgs @('sparse-checkout', 'set', $script:OvmsRelPosix)
        if ($sparse.exit_code -ne 0) {
            throw "git sparse-checkout failed: $($sparse.output)"
        }

        $lfsCheck = Invoke-GitCapture -GitArgs @('lfs', 'version')
        if ($lfsCheck.exit_code -eq 0) {
            $null = Invoke-GitCapture -WorkingDirectory $tempRoot -GitArgs @('lfs', 'install', '--local')
            $lfsPull = Invoke-GitCapture -WorkingDirectory $tempRoot -GitArgs @('lfs', 'pull', '--include', "$($script:OvmsRelPosix)/**")
            if ($lfsPull.output) { $result.logs += $lfsPull.output }
            if ($lfsPull.exit_code -ne 0) {
                $result.warnings += "git lfs pull returned exit $($lfsPull.exit_code); large OVMS assets may be missing"
            }
        } else {
            $result.warnings += 'git-lfs not installed; if OVMS folder uses LFS, install Git LFS and re-run with -Force'
        }

        $sourceOvms = Join-Path $tempRoot $script:OvmsRelWin
        if (-not (Test-Path -LiteralPath (Join-Path $sourceOvms 'ovms_agentic_setup.ps1'))) {
            throw "Sparse checkout did not produce $($script:OvmsRelWin)\ovms_agentic_setup.ps1 (check -Ref and repo access)"
        }

        $destOvms = Join-Path $DestInstallRoot $script:OvmsRelWin
        Copy-DevKitOvmsTree -SourceOvmsDir $sourceOvms -DestOvmsDir $destOvms
        $result.logs += "installed_ovms_dir=$destOvms"
        return $destOvms
    }
    finally {
        if ($tempRoot -and (Test-Path -LiteralPath $tempRoot)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Try-FetchDevKitOvmsSliceInPlace {
    param(
        [string]$Repo,
        [string]$Branch,
        [string]$DestInstallRoot
    )
    $gitDir = Join-Path $DestInstallRoot '.git'
    if (-not (Test-Path -LiteralPath $gitDir)) {
        return $null
    }

    $fetch = Invoke-GitCapture -WorkingDirectory $DestInstallRoot -GitArgs @('fetch', 'origin', $Branch, '--depth', '1')
    if ($fetch.exit_code -ne 0) {
        throw "git fetch failed: $($fetch.output)"
    }
    $checkout = Invoke-GitCapture -WorkingDirectory $DestInstallRoot -GitArgs @('checkout', $Branch)
    if ($checkout.exit_code -ne 0) {
        $result.warnings += "git checkout ${Branch}: $($checkout.output)"
    }

    $sparse = Invoke-GitCapture -WorkingDirectory $DestInstallRoot -GitArgs @('sparse-checkout', 'add', $script:OvmsRelPosix)
    if ($sparse.exit_code -ne 0) {
        throw "git sparse-checkout add failed: $($sparse.output)"
    }

    $pull = Invoke-GitCapture -WorkingDirectory $DestInstallRoot -GitArgs @('pull', '--ff-only')
    if ($pull.output) { $result.logs += $pull.output }

    $destOvms = Join-Path $DestInstallRoot $script:OvmsRelWin
    if (-not (Test-Path -LiteralPath (Join-Path $destOvms 'ovms_agentic_setup.ps1'))) {
        throw "In-place sparse checkout did not materialize ovms_agentic_setup.ps1"
    }
    return $destOvms
}

$root = if ($InstallRoot) { $InstallRoot.TrimEnd('\', '/') } else { Find-DevKitInstallRoot }
if (-not $root) {
    $root = Join-Path $env:USERPROFILE 'source\training.developer.aipc'
}
$result.logs += "install_root=$root"

$repo = if ($RepoUrl) { $RepoUrl.Trim() } else { Get-DefaultDevKitRepoUrl }
$branch = if ($Ref) { $Ref.Trim() } else { Get-DefaultDevKitRepoRef }
$result.logs += "repo=$repo"
$result.logs += "ref=$branch"

$existingScript = Get-DevKitOvmsAgenticScriptPath -Root $root
if ($existingScript -and -not $Force) {
    $result.functional_status = 'pass'
    $result.overall_status = 'pass'
    $result.exit_code = 0
    $result.logs += "ovms_agentic_setup=$existingScript"
    $result.warnings += 'OVMS Dev Kit slice already present; use -Force to re-fetch from git'
    Write-SkillResult -Result $result
    return
}

if (-not (Test-GitCliAvailable)) {
    $result.warnings += 'Git is not available on PATH; install Git for Windows or clone Windows_Software_Installation\OVMS manually'
    $result.exit_code = 1
    Write-SkillResult -Result $result
    return
}

if (-not (Test-ApprovalRequired -RiskClass 'network' -Approve:$Approve)) {
    $result.functional_status = 'blocked'
    $result.overall_status = 'blocked'
    $result.warnings += 'Network git fetch requires -Approve'
    $result.warnings += "Example: fetch-devkit-ovms-slice.ps1 -InstallRoot '$root' -Approve"
    $result.exit_code = 0
    Write-SkillResult -Result $result
    return
}

if ($WhatIf) {
    $result.functional_status = 'pass'
    $result.overall_status = 'pass'
    $result.warnings += 'WhatIf: would sparse-clone Windows_Software_Installation/OVMS only (git + optional LFS)'
    if ($IncludeOvmsRuntime) {
        $result.warnings += "WhatIf: would download ovms_windows_${OvmsVersion}_python_on.zip if ovms.exe missing"
    }
    $result.exit_code = 0
    Write-SkillResult -Result $result
    return
}

try {
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }

    $ovmsDir = $null
    $inPlace = $null
    try {
        $inPlace = Try-FetchDevKitOvmsSliceInPlace -Repo $repo -Branch $branch -DestInstallRoot $root
    } catch {
        $result.warnings += "In-place sparse fetch skipped: $($_.Exception.Message)"
    }
    if ($inPlace) {
        $ovmsDir = $inPlace
        $result.logs += 'mode=in_place_sparse'
    } else {
        $ovmsDir = Fetch-DevKitOvmsSliceViaSparseClone -Repo $repo -Branch $branch -DestInstallRoot $root
        $result.logs += 'mode=temp_sparse_clone'
    }

    Unblock-DevKitOvmsScripts -OvmsDir $ovmsDir
    $scriptPath = Join-Path $ovmsDir 'ovms_agentic_setup.ps1'
    $result.logs += "ovms_agentic_setup=$scriptPath"

    $ovmsExe = Join-Path $ovmsDir 'ovms\ovms.exe'
    if ($IncludeOvmsRuntime -and -not (Test-Path -LiteralPath $ovmsExe)) {
        $tag = "v$OvmsVersion"
        $zipName = "ovms_windows_${OvmsVersion}_python_on.zip"
        $zipUrl = "https://github.com/openvinotoolkit/model_server/releases/download/$tag/$zipName"
        $result.logs += "ovms_runtime_url=$zipUrl"
        $tempRoot = Join-Path $env:TEMP "ovms-runtime-$OvmsVersion-$(Get-Random)"
        $zipPath = Join-Path $tempRoot $zipName
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
        $extractDir = Join-Path $tempRoot 'extract'
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force
        $newBundle = Join-Path $extractDir 'ovms'
        if (-not (Test-Path -LiteralPath (Join-Path $newBundle 'ovms.exe'))) {
            throw "OVMS runtime zip missing ovms\ovms.exe"
        }
        $bundleDest = Join-Path $ovmsDir 'ovms'
        if (Test-Path -LiteralPath $bundleDest) {
            Remove-Item -LiteralPath $bundleDest -Recurse -Force
        }
        Move-Item -LiteralPath $newBundle -Destination $bundleDest
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        $result.logs += "ovms_exe=$bundleDest\ovms.exe"
    } elseif (-not (Test-Path -LiteralPath $ovmsExe)) {
        $result.warnings += 'ovms\ovms.exe not in Dev Kit slice; run upgrade-ovms-runtime.ps1 -Approve or -IncludeOvmsRuntime'
    }

    $result.functional_status = 'pass'
    $result.exit_code = 0
    $result.warnings += "Set AIPC_DEVKIT_INSTALL_ROOT='$root' if skills do not auto-detect this tree"
    $result.warnings += 'This slice does not include Setup_1/Setup_2 (OpenVINO GenAI); verify V3 may still fail until intel-devkit-install runs'
    $result.warnings += 'Next: invoke-ovms-agentic-setup.ps1 -Approve -Pull -Profile verify (standard user)'
}
catch {
    $result.functional_status = 'fail'
    $result.warnings += $_.Exception.Message
    $result.exit_code = 1
}

$result.overall_status = $result.functional_status
Write-SkillResult -Result $result
