<#
.SYNOPSIS
    Start OVMS with Muse Glimmer and point Hermes at it.

.DESCRIPTION
    Not a skill. Assumes Hermes is already installed and agent-skills sits beside
    Windows_Software_Installation. Asks before downloading the model, before
    stopping another server on port 8000, and before editing Hermes config.
    Pass -Yes to skip those prompts.
#>
param(
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_skill-common.ps1"

$CatalogModelId = 'OpenVINO/Muse-Glimmer-30B-int4-ov'
$OvmsPort = 8000
$OvmsBaseUrl = Get-OvmsBaseUrl -Port $OvmsPort

function Write-SetupLine {
    param([string]$Message)
    Write-Host $Message
}

function Exit-Setup {
    param(
        [Parameter(Mandatory = $true)][int]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )
    Write-SetupLine $Message
    exit $Code
}

function Test-SetupAnswerYes {
    param([Parameter(Mandatory = $true)][string]$Prompt)
    if ($Yes) {
        Write-SetupLine "$Prompt yes (-Yes)"
        return $true
    }
    $answer = Read-Host "$Prompt (yes/no)"
    return ($answer -match '^(?i:y|yes)$')
}

function Get-HermesConfigCandidates {
    $candidates = @()
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'hermes\config.yaml') }
    if ($env:USERPROFILE) { $candidates += (Join-Path $env:USERPROFILE '.hermes\config.yaml') }
    if ($env:APPDATA) { $candidates += (Join-Path $env:APPDATA 'hermes\config.yaml') }
    return $candidates
}

function Find-HermesConfigPath {
    foreach ($path in (Get-HermesConfigCandidates)) {
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $null
}

function Get-PortableSkillsDirectory {
    $agentSkillsRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    return (Join-Path $agentSkillsRoot 'skills')
}

function Format-YamlPath {
    param([string]$Path)
    return (($Path -replace '\\', '/').TrimEnd('/'))
}

function Test-SameSkillsPath {
    param([string]$Left, [string]$Right)
    $a = (Format-YamlPath $Left).ToLowerInvariant()
    $b = (Format-YamlPath $Right).ToLowerInvariant()
    return ($a -eq $b)
}

function ConvertFrom-SetupJsonText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $start = $Text.IndexOf('{')
    $end = $Text.LastIndexOf('}')
    if ($start -lt 0 -or $end -le $start) { return $null }
    try {
        return $Text.Substring($start, $end - $start + 1) | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Read-SetupProcessText {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0) { return '' }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes)
    }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    return $utf8.GetString($bytes)
}

function Test-MuseGlimmerAdvertised {
    $live = Get-OvmsAdvertisedModelIdForAgent -BaseUrl $OvmsBaseUrl -CatalogModelId $CatalogModelId
    return $live
}

function Invoke-MuseGlimmerOvmsSetup {
    param([switch]$StopExisting)

    $scriptPath = Join-Path $PSScriptRoot 'invoke-ovms-agentic-setup.ps1'
    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    $proc = $null
    try {
        $escapedPath = $scriptPath.Replace("'", "''")
        # Profile agent skips the verify tool test. SkipChatSmoke skips the chat
        # poll. Both can keep running long after GET /v3/models already lists the model.
        $tail = "-Approve -ApproveRetryPull -Pull -Profile agent -SkipChatSmoke -Model '$CatalogModelId' -Target GPU -Port $OvmsPort"
        if ($StopExisting) { $tail += ' -ApproveStopOvms' }
        $inner = '[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false; $OutputEncoding = [Console]::OutputEncoding; & ''' + $escapedPath + ''' ' + $tail
        $argList = '-NoProfile -ExecutionPolicy Bypass -Command "' + $inner + '"'
        Write-SetupLine 'Starting OVMS. The Muse Glimmer download can take a long time.'
        Write-SetupLine 'When the model is listed, this script continues and configures Hermes. Leave the OVMS window open.'
        $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList `
            -PassThru -NoNewWindow `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $deadline = (Get-Date).AddHours(3)
        $sawExit = $false
        $exitCodeName = $null
        $portQuietSince = $null
        while ((Get-Date) -lt $deadline) {
            $listed = Test-MuseGlimmerAdvertised
            if ($listed.advertised_match) {
                $grace = (Get-Date).AddSeconds(30)
                while (-not $proc.HasExited -and (Get-Date) -lt $grace) { Start-Sleep -Seconds 2 }
                if (-not $proc.HasExited) {
                    Write-SetupLine 'Muse Glimmer is listed on port 8000. Configuring Hermes without waiting for more OVMS checks.'
                }
                break
            }
            if ($proc.HasExited -and -not $sawExit) {
                $sawExit = $true
                $earlyJson = ConvertFrom-SetupJsonText -Text (Read-SetupProcessText -Path $outFile)
                if ($earlyJson -and $earlyJson.error -and $earlyJson.error.code) {
                    $exitCodeName = [string]$earlyJson.error.code
                }
                if ($exitCodeName -and $exitCodeName -ne 'MODEL_ADVERTISED_MISMATCH') { break }
                Write-SetupLine 'OVMS answered before Muse Glimmer was listed. Waiting for OpenVINO/Muse-Glimmer-30B-int4-ov on port 8000.'
            }
            if ($sawExit) {
                $stillListening = @(Get-OvmsTcpPortListener -Port $OvmsPort)
                if ($stillListening.Count -eq 0) {
                    if (-not $portQuietSince) { $portQuietSince = Get-Date }
                    if (((Get-Date) - $portQuietSince).TotalSeconds -ge 60) { break }
                } else {
                    $portQuietSince = $null
                }
            }
            Start-Sleep -Seconds 5
        }
        $stdout = Read-SetupProcessText -Path $outFile
        $stderr = Read-SetupProcessText -Path $errFile
        $exitCode = $null
        if ($proc.HasExited) { $exitCode = $proc.ExitCode }
        return @{
            exit_code = $exitCode
            json      = (ConvertFrom-SetupJsonText -Text $stdout)
            stderr    = $stderr
            muse      = (Test-MuseGlimmerAdvertised)
        }
    } finally {
        if (-not $proc -or $proc.HasExited) {
            Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-SetupChildMessage {
    param($Child)
    if ($Child.json -and $Child.json.user_message) { return [string]$Child.json.user_message }
    if ($Child.json -and $Child.json.error -and $Child.json.error.message) { return [string]$Child.json.error.message }
    if ($Child.stderr) { return [string]$Child.stderr }
    return 'OVMS setup did not return a result.'
}

function Invoke-HermesConfigSet {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )
    & hermes config set $Key $Value
    if ($LASTEXITCODE -ne 0) {
        Exit-Setup -Code 1 -Message "hermes config set $Key failed (exit $LASTEXITCODE). Hermes skills directory was not changed."
    }
}

function Update-HermesExternalSkillsDir {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$SkillsDir
    )

    $dir = Format-YamlPath $SkillsDir
    $bytes = [System.IO.File]::ReadAllBytes($ConfigPath)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $utf8 = New-Object System.Text.UTF8Encoding $hasBom
    $text = $utf8.GetString($bytes)
    if ($hasBom) { $text = $text.TrimStart([char]0xFEFF) }
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($text -split "`r?`n", -1)) { [void]$lines.Add($line) }
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }

    $skillsIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^skills\s*:\s*(#.*)?$') { $skillsIndex = $i; break }
    }

    $changed = $false
    if ($skillsIndex -lt 0) {
        if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
            [void]$lines.Add('')
        }
        [void]$lines.Add('skills:')
        [void]$lines.Add('  external_dirs:')
        [void]$lines.Add("    - '$dir'")
        $changed = $true
    } else {
        $blockEnd = $lines.Count
        for ($i = $skillsIndex + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*$' -or $lines[$i] -match '^\s*#') { continue }
            if ($lines[$i] -match '^\S') { $blockEnd = $i; break }
        }

        $extIndex = -1
        $indent = '  '
        $rest = ''
        for ($i = $skillsIndex + 1; $i -lt $blockEnd; $i++) {
            if ($lines[$i] -match '^(\s*)external_dirs\s*:\s*(.*)$') {
                $extIndex = $i
                if ($Matches[1]) { $indent = $Matches[1] }
                $rest = ($Matches[2] -replace '\s+#.*$', '').Trim()
                break
            }
        }

        if ($extIndex -lt 0) {
            $lines.Insert($skillsIndex + 1, "    - '$dir'")
            $lines.Insert($skillsIndex + 1, '  external_dirs:')
            $changed = $true
        } elseif ($rest -match '^\[(.*)\]$') {
            $items = @()
            $inner = $Matches[1].Trim()
            if ($inner) {
                $items = @($inner -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ })
            }
            $already = $false
            foreach ($item in $items) {
                if (Test-SameSkillsPath -Left $item -Right $dir) { $already = $true; break }
            }
            if (-not $already) {
                $items += $dir
                $lines.RemoveAt($extIndex)
                $block = New-Object System.Collections.Generic.List[string]
                [void]$block.Add("${indent}external_dirs:")
                foreach ($item in $items) {
                    $quoted = Format-YamlPath $item
                    [void]$block.Add("$indent  - '$quoted'")
                }
                for ($k = $block.Count - 1; $k -ge 0; $k--) { $lines.Insert($extIndex, $block[$k]) }
                $changed = $true
            }
        } else {
            $existing = @()
            if ($rest -and $rest -notmatch '^(?i:null|~)$') {
                $existing += $rest.Trim().Trim('"').Trim("'")
            }
            $lastItem = $extIndex
            $itemIndent = $indent + '  '
            for ($i = $extIndex + 1; $i -lt $blockEnd; $i++) {
                if ($lines[$i] -match '^\s*$' -or $lines[$i] -match '^\s*#') { $lastItem = $i; continue }
                if ($lines[$i] -match "^$([regex]::Escape($indent))\S") { break }
                if ($lines[$i] -match '^\s*-\s+(.*)$') {
                    $existing += ($Matches[1].Trim().Trim('"').Trim("'"))
                    $lastItem = $i
                    if ($Matches[0] -match '^(\s+)') { $itemIndent = $Matches[1] }
                    continue
                }
                break
            }
            $already = $false
            foreach ($item in $existing) {
                if (Test-SameSkillsPath -Left $item -Right $dir) { $already = $true; break }
            }
            if (-not $already) {
                if ($rest -and $rest -notmatch '^(?i:null|~)$') {
                    $lines[$extIndex] = "${indent}external_dirs:"
                    $scalar = $rest.Trim().Trim('"').Trim("'")
                    $lines.Insert($extIndex + 1, "$itemIndent- '$(Format-YamlPath $scalar)'")
                    $lines.Insert($extIndex + 2, "$itemIndent- '$dir'")
                } else {
                    $lines.Insert($lastItem + 1, "$itemIndent- '$dir'")
                }
                $changed = $true
            }
        }
    }

    if (-not $changed) { return 'present' }

    $backup = "$ConfigPath.bak-muse-glimmer"
    Copy-Item -LiteralPath $ConfigPath -Destination $backup -Force
    $output = ($lines -join $newline)
    if (-not $output.EndsWith($newline)) { $output += $newline }
    [System.IO.File]::WriteAllText($ConfigPath, $output, $utf8)
    return 'added'
}

function Show-HermesRestart {
    param([string]$SkillsDir)
    $shown = Format-YamlPath $SkillsDir
    Write-SetupLine ''
    Write-SetupLine 'OVMS is serving Muse Glimmer on port 8000, and Hermes config was updated.'
    Write-SetupLine "skills.external_dirs includes $shown"
    Write-SetupLine ''
    Write-SetupLine 'Exit any open Hermes session, then start hermes again from PowerShell.'
    Write-SetupLine 'At the hermes> prompt, run /skills list.'
    Write-SetupLine 'Start a new chat so Hermes uses Muse Glimmer.'
}

if ($MyInvocation.InvocationName -eq '.') {
    return
}

if (Test-DevKitSessionIsElevated) {
    Exit-Setup -Code 1 -Message 'Run this from a standard user PowerShell. An Administrator session can leave OVMS files owned by Admin.'
}

$hermesCmd = Get-Command hermes -ErrorAction SilentlyContinue
if (-not $hermesCmd) {
    Exit-Setup -Code 1 -Message 'hermes was not found on PATH. Install Hermes, then run this script again.'
}

$hermesConfig = Find-HermesConfigPath
if (-not $hermesConfig) {
    $looked = (Get-HermesConfigCandidates) -join ', '
    Exit-Setup -Code 1 -Message "Hermes config.yaml was not found. Looked in: $looked"
}

$portableSkills = Get-PortableSkillsDirectory
$categoryDir = Join-Path $portableSkills 'software-development'
if (-not (Test-Path -LiteralPath $categoryDir)) {
    Exit-Setup -Code 1 -Message "Skills directory was not found at $portableSkills. Keep this script under agent-skills\scripts\windows."
}

$root = Find-DevKitInstallRoot
$ovmsResolved = Find-DevKitOvmsAgenticScript -InstallRoot $root
if (-not $ovmsResolved) {
    Exit-Setup -Code 1 -Message 'ovms_agentic_setup.ps1 was not found. Place agent-skills beside Windows_Software_Installation in the Dev Kit clone.'
}

$live = Test-MuseGlimmerAdvertised
if ($live.advertised_match) {
    Write-SetupLine "OVMS is already serving $($live.model_for_agent) on port $OvmsPort. Skipping the download."
} else {
    $listeners = @(Get-OvmsTcpPortListener -Port $OvmsPort)
    $stopExisting = $false
    if ($listeners.Count -gt 0) {
        $who = ($listeners | ForEach-Object { "$($_.process_name) pid $($_.pid)" }) -join ', '
        $listed = if ($live.advertised_ids -and @($live.advertised_ids).Count -gt 0) { (@($live.advertised_ids) -join ', ') } else { 'no OVMS model list' }
        $stopPrompt = "Port $OvmsPort is in use ($who; advertised: $listed). Stop it and start Muse Glimmer?"
        if (-not (Test-SetupAnswerYes -Prompt $stopPrompt)) {
            Exit-Setup -Code 0 -Message 'Stopped. The current server was left running, and Hermes was not changed.'
        }
        $stopExisting = $true
    } else {
        $downloadPrompt = "Download $CatalogModelId if needed and start OVMS on port $OvmsPort? This can take a long time."
        if (-not (Test-SetupAnswerYes -Prompt $downloadPrompt)) {
            Exit-Setup -Code 0 -Message 'Stopped. OVMS was not started, and Hermes was not changed.'
        }
    }

    $child = Invoke-MuseGlimmerOvmsSetup -StopExisting:$stopExisting
    $errorCode = ''
    if ($child.json -and $child.json.error -and $child.json.error.code) { $errorCode = [string]$child.json.error.code }
    $live = if ($child.muse) { $child.muse } else { Test-MuseGlimmerAdvertised }
    if ($errorCode -eq 'PORT_CONFLICT' -and -not $stopExisting -and -not $live.advertised_match) {
        $conflictPrompt = "Port $OvmsPort is already in use. Stop that server and start Muse Glimmer?"
        if (-not (Test-SetupAnswerYes -Prompt $conflictPrompt)) {
            Exit-Setup -Code 0 -Message 'Stopped. The current server was left running, and Hermes was not changed.'
        }
        $child = Invoke-MuseGlimmerOvmsSetup -StopExisting
        $live = if ($child.muse) { $child.muse } else { Test-MuseGlimmerAdvertised }
    }

    if (-not $live.advertised_match) {
        $listed = if ($live.advertised_ids -and @($live.advertised_ids).Count -gt 0) { (@($live.advertised_ids) -join ', ') } else { 'none' }
        Exit-Setup -Code 1 -Message "$(Get-SetupChildMessage -Child $child) Advertised on port ${OvmsPort}: $listed."
    }
    Write-SetupLine "OVMS is serving $($live.model_for_agent) on port $OvmsPort."
}

Write-SetupLine ''
Write-SetupLine 'Next step: configure Hermes to use this OVMS server. Hermes does not switch until you answer yes.'

$skillsForward = Format-YamlPath $portableSkills
Write-SetupLine 'Hermes config will be changed:'
Write-SetupLine '  model.provider = custom'
Write-SetupLine "  model.base_url = $OvmsBaseUrl"
Write-SetupLine "  model.default = $CatalogModelId"
Write-SetupLine "  skills.external_dirs will include $skillsForward"
if (-not (Test-SetupAnswerYes -Prompt 'Apply these Hermes config changes?')) {
    Exit-Setup -Code 0 -Message 'OVMS is running. Hermes was not changed.'
}

Invoke-HermesConfigSet -Key 'model.provider' -Value 'custom'
Invoke-HermesConfigSet -Key 'model.base_url' -Value $OvmsBaseUrl
Invoke-HermesConfigSet -Key 'model.default' -Value $CatalogModelId

$hermesConfig = Find-HermesConfigPath
if (-not $hermesConfig) {
    Exit-Setup -Code 1 -Message 'Hermes model settings were written, but config.yaml could not be found to add the skills directory.'
}
$dirResult = Update-HermesExternalSkillsDir -ConfigPath $hermesConfig -SkillsDir $portableSkills
if ($dirResult -eq 'present') {
    Write-SetupLine "skills.external_dirs already includes $skillsForward"
} else {
    Write-SetupLine "Added $skillsForward to skills.external_dirs"
    Write-SetupLine "Backup: $hermesConfig.bak-muse-glimmer"
}

Write-SetupLine ''
Write-SetupLine 'hermes config get model.provider'
& hermes config get model.provider
Write-SetupLine 'hermes config get model.base_url'
& hermes config get model.base_url
Write-SetupLine 'hermes config get model.default'
& hermes config get model.default
Write-SetupLine 'hermes config get skills.external_dirs'
& hermes config get skills.external_dirs

Show-HermesRestart -SkillsDir $portableSkills
exit 0
