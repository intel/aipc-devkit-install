#!/usr/bin/env powershell
<#
.SYNOPSIS
    Minimal prerequisites for OVMS launcher scripts (ovms_setup.ps1 / ovms_agentic_setup.ps1).

.DESCRIPTION
    Inspired by Setup_1 (winget + execution policy) and Setup_2 (preflight checks), but scoped to
    what OVMS needs without Visual Studio, Python, OpenVINO GenAI, or other Dev Kit packages.

    Installs (when elevated):
      - VC++ 2015-2022 x64 redistributable (required for ovms.exe)
      - App Installer / winget if missing
      - Git for Windows (Git.Git via winget -e --source winget)

    Always (no admin):
      - CurrentUser execution policy RemoteSigned (if Restricted)
      - Unblock-File on OVMS *.ps1 in this folder

    Does NOT install Setup_2 openvino_genai or download OVMS — run ovms_agentic_setup.ps1 after this.

.PARAMETER VerifyOnly
    Run checks only; do not invoke winget install.

.PARAMETER Target
    GPU (default), CPU, or NPU — adds target-specific warnings in verify output.

.PARAMETER WhatIf
    Show what would be installed without winget install.

.EXAMPLE
    .\Setup_OVMS_Prerequisites.ps1

.EXAMPLE
    .\Setup_OVMS_Prerequisites.ps1 -VerifyOnly -Target GPU

.NOTES
    Winget installs require an elevated PowerShell session (same expectation as Setup_1 install).
    Run OVMS model pull/start as a standard user after drivers and VC++ are in place.
#>

param(
    [ValidateSet('GPU', 'CPU', 'NPU')]
    [string]$Target = 'GPU',
    [switch]$VerifyOnly,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
$JsonPath = Join-Path $ScriptDir 'JSON\ovms_prerequisites.json'
$LogDir = Join-Path $env:TEMP 'ovms-prereq-logs'
$LogFile = Join-Path $LogDir ("setup-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    Add-Content -LiteralPath $LogFile -Value $line
    switch ($Level) {
        'OK'    { Write-Host $Message -ForegroundColor Green }
        'WARN'  { Write-Host $Message -ForegroundColor Yellow }
        'ERR'   { Write-Host $Message -ForegroundColor Red }
        default { Write-Host $Message -ForegroundColor Cyan }
    }
}

function Test-IsAdministrator {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-IsOs64Bit {
    return [Environment]::Is64BitOperatingSystem -and [Environment]::Is64BitProcess
}

function Get-WingetPath {
    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidate = "${env:ProgramFiles}\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe"
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    return $null
}

function Test-VcRedist2015PlusX64 {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'
    )
    foreach ($key in $keys) {
        if (Test-Path -LiteralPath $key) {
            $installed = (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).Installed
            if ($installed -eq 1) { return $true }
        }
    }
    return $false
}

function Test-GitInstalled {
    return [bool](Get-Command git -ErrorAction SilentlyContinue)
}

function Invoke-WingetInstallPackage {
    param(
        [string]$PackageId,
        [string]$FriendlyName,
        [string]$ExtraFlags
    )

    $winget = Get-WingetPath
    if (-not $winget) {
        Write-Log "winget not found; cannot install $FriendlyName" 'ERR'
        return $false
    }

    Write-Log "Installing $FriendlyName ($PackageId) via winget..."
    if ($WhatIf) {
        Write-Log "WhatIf: winget install --id $PackageId $ExtraFlags" 'WARN'
        return $true
    }

    $args = @(
        'install', '--id', $PackageId,
        '--accept-package-agreements', '--accept-source-agreements',
        '--disable-interactivity'
    )
    if ($ExtraFlags) { $args += $ExtraFlags.Trim().Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries) }

    & $winget @args 2>&1 | ForEach-Object { Write-Log $_ }
    if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
        Write-Log "$FriendlyName install succeeded or already present (exit $LASTEXITCODE)" 'OK'
        return $true
    }
    Write-Log "$FriendlyName winget install failed with exit $LASTEXITCODE" 'ERR'
    return $false
}

function Test-OvmsRuntimeSmoke {
    $ovmsExe = Join-Path $ScriptDir 'ovms\ovms.exe'
    if (-not (Test-Path -LiteralPath $ovmsExe)) {
        Write-Log 'ovms\ovms.exe not present yet (expected before first ovms_agentic_setup.ps1 run)' 'WARN'
        return $null
    }
    $setupVars = Join-Path $ScriptDir 'ovms\setupvars.ps1'
    if (Test-Path -LiteralPath $setupVars) {
        try { . $setupVars } catch { Write-Log "setupvars.ps1 failed: $_" 'WARN' }
    }
    try {
        $out = & $ovmsExe --version 2>&1
        Write-Log "ovms.exe --version: $out" 'OK'
        return $true
    }
    catch {
        Write-Log "ovms.exe failed to start: $_ (check VC++ x64 and setupvars)" 'ERR'
        return $false
    }
}

function Write-TargetGuidance {
    param([string]$DeviceTarget)
    switch ($DeviceTarget) {
        'GPU' {
            Write-Log 'GPU target: ensure current Intel Arc / Core Ultra graphics driver (OEM or Intel DSA).' 'WARN'
        }
        'NPU' {
            Write-Log 'NPU target: requires Intel AI PC NPU drivers (platform/OEM); not installed by this script.' 'WARN'
            Write-Log 'Use NPU-optimized OpenVINO models (-cw-ov). Qwen3.8-27B is GPU-oriented.' 'WARN'
        }
        'CPU' {
            Write-Log 'CPU target: no GPU driver required; large models need substantial system RAM.' 'WARN'
        }
    }
}

# --- Main ---
Write-Log 'OVMS minimal prerequisites (Setup_1/Setup_2 inspired, OVMS-only scope)'
Write-Log "Log file: $LogFile"

$results = [ordered]@{
    Os64Bit           = $false
    ExecutionPolicy   = $false
    ScriptsUnblocked  = $false
    WingetAvailable   = $false
    VcRedistX64       = $false
    GitInstalled      = $false
    OvmsSmoke         = 'skipped'
    WingetInstalls    = 'skipped'
}

if (-not (Test-IsOs64Bit)) {
    Write-Log '64-bit Windows and 64-bit PowerShell are required.' 'ERR'
    exit 1
}
$results.Os64Bit = $true

try {
    $policy = Get-ExecutionPolicy -Scope CurrentUser
    if ($policy -in @('Restricted', 'AllSigned')) {
        if (-not $VerifyOnly) {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            Write-Log "Execution policy set to RemoteSigned (CurrentUser) from $policy" 'OK'
        } else {
            Write-Log "Execution policy is $policy; run without -VerifyOnly to set RemoteSigned" 'WARN'
        }
    } else {
        Write-Log "Execution policy (CurrentUser): $policy" 'OK'
    }
    $results.ExecutionPolicy = $true
}
catch {
    Write-Log "Could not adjust execution policy: $_" 'WARN'
}

Get-ChildItem -LiteralPath $ScriptDir -Filter '*.ps1' -File | ForEach-Object {
    Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue
}
$results.ScriptsUnblocked = $true

$results.WingetAvailable = [bool](Get-WingetPath)
$results.VcRedistX64 = Test-VcRedist2015PlusX64
$results.GitInstalled = Test-GitInstalled

Write-TargetGuidance -DeviceTarget $Target

if (-not (Test-Path -LiteralPath $JsonPath)) {
    Write-Log "Missing config: $JsonPath" 'ERR'
    exit 1
}
$config = Get-Content -LiteralPath $JsonPath -Raw | ConvertFrom-Json
$globalFlags = $config.global_install_flags

if (-not $results.VcRedistX64) {
    Write-Log 'VC++ 2015-2022 x64 not detected — ovms.exe may exit with -1073741515 until installed.' 'WARN'
} else {
    Write-Log 'VC++ 2015-2022 x64 appears installed.' 'OK'
}

if (-not $VerifyOnly) {
    if (-not (Test-IsAdministrator)) {
        Write-Log 'Winget package installs need Administrator. Re-run this script from an elevated PowerShell.' 'ERR'
        Write-Log 'You can still run: Set-ExecutionPolicy, Unblock-File, and ovms_agentic_setup.ps1 without admin after VC++ is installed.' 'WARN'
        exit 2
    }

    $results.WingetInstalls = 'attempted'
    foreach ($app in $config.winget_applications) {
        if ($app.skip_install -eq 'yes') { continue }
        if ($app.install_only_if_winget_missing -and $results.WingetAvailable) { continue }
        if ($app.id -eq 'Microsoft.VCRedist.2015+.x64' -and $results.VcRedistX64) {
            Write-Log 'Skipping VC++ redist — already detected.' 'OK'
            continue
        }
        if ($app.id -eq 'Git.Git' -and (Test-GitInstalled)) {
            Write-Log 'Skipping Git — git already on PATH.' 'OK'
            continue
        }
        $extraFlags = $globalFlags
        if ($app.PSObject.Properties['override_flags'] -and $app.override_flags) {
            $extraFlags = "$extraFlags $($app.override_flags)".Trim()
        }
        $ok = Invoke-WingetInstallPackage -PackageId $app.id -FriendlyName $app.friendly_name -ExtraFlags $extraFlags
        if (-not $ok) { exit 3 }
    }

    $results.VcRedistX64 = Test-VcRedist2015PlusX64
    $results.GitInstalled = Test-GitInstalled
    $results.WingetAvailable = [bool](Get-WingetPath)
}

$smoke = Test-OvmsRuntimeSmoke
if ($null -ne $smoke) { $results.OvmsSmoke = [string]$smoke }

Write-Log '--- Summary ---'
$results.GetEnumerator() | ForEach-Object { Write-Log ("  {0}: {1}" -f $_.Key, $_.Value) }

$ready = $results.Os64Bit -and $results.VcRedistX64
if ($ready) {
    Write-Log 'Prerequisites look ready. Next (standard user):' 'OK'
    Write-Log "  cd `"$ScriptDir`"" 'OK'
    Write-Log '  .\ovms_agentic_setup.ps1 -Pull -Model qwen3.8-27b -Target GPU' 'OK'
} else {
    Write-Log 'One or more prerequisites still missing — see warnings above.' 'WARN'
}

if ($VerifyOnly) { exit $(if ($ready) { 0 } else { 1 }) }
exit $(if ($ready) { 0 } else { 1 })
