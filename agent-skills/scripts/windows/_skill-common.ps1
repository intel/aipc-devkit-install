# Shared helpers for Windows invoke scripts
$ErrorActionPreference = 'Stop'

function New-RunId {
    return [guid]::NewGuid().ToString()
}

function Get-SkillResultSkeleton {
    param(
        [string]$SkillId,
        [string]$SkillVersion = '0.1.0',
        [string]$RiskClass = 'read',
        [string]$FunctionalStatus = 'fail'
    )
    $now = (Get-Date).ToUniversalTime().ToString('o')
    return [ordered]@{
        schema_id          = 'skill-result-2026-08'
        run_id             = (New-RunId)
        skill_id           = $SkillId
        skill_version      = $SkillVersion
        started_at         = $now
        finished_at        = $now
        functional_status  = $FunctionalStatus
        overall_status     = $FunctionalStatus
        schema_valid       = $true
        warnings           = @()
        risk_class         = $RiskClass
        checks             = @()
        logs               = @()
        exit_code          = 1
    }
}

function Get-OvmsBaseUrl {
    param([int]$Port = 8000)
    return "http://localhost:$Port/v3"
}

function Invoke-DevKitExternalScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [hashtable]$BoundParameters = @{}
    )
    $scriptDir = Split-Path -Path $ScriptPath -Parent
    $scriptName = Split-Path -Path $ScriptPath -Leaf
    $logLine = "invoke: $ScriptPath"
    Push-Location $scriptDir
    try {
        $output = & ".\$scriptName" @BoundParameters 2>&1
        $exit = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
        return @{
            exit_code = $exit
            output    = @($output | ForEach-Object { "$_" })
            log_line  = $logLine
        }
    } catch {
        return @{
            exit_code = 1
            output    = @($_.Exception.Message)
            log_line  = $logLine
        }
    } finally {
        Pop-Location
    }
}

function Test-DevKitSessionIsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Add-DevKitStandardUserHandoffWarnings {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Result,
        [ValidateSet('post-install', 'elevated-session')]
        [string]$Context = 'elevated-session'
    )
    switch ($Context) {
        'post-install' {
            $Result.warnings += 'Handoff: close Administrator PowerShell when Setup_1 and Setup_2 finish; run verify, OVMS, smoke, and agent configure from a standard-user session'
            $Result.warnings += 'Do not start OVMS with -Pull as Admin against clone .\\models — skill launch defaults to %USERPROFILE%\\OVMS (see docs/admin-vs-user-runtime.md)'
        }
        'elevated-session' {
            $Result.warnings += 'Session is elevated (Administrator). After install completes, use standard-user PowerShell for verify, OVMS, smoke, and configure'
        }
    }
}

function Get-OvmsUserScopedDataPaths {
    $root = Join-Path $env:USERPROFILE 'OVMS'
    return @{
        Root  = $root
        Repo  = Join-Path $root 'models'
        Cache = Join-Path $root '.ovcache'
    }
}

function ConvertTo-OvmsConfigPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    # OVMS may still normalize to backslashes internally; prefer junction + relative paths (see Enable-DevKitOvmsUserDataViaJunctions).
    return ($Path.TrimEnd('\', '/') -replace '\\', '/')
}

function Enable-DevKitOvmsUserDataViaJunctions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OvmsWorkingDirectory,
        [Parameter(Mandatory = $true)]
        [string]$UserModelsPath,
        [Parameter(Mandatory = $true)]
        [string]$UserCachePath,
        [switch]$RepairBlockingDirectories
    )
    foreach ($dir in @($UserModelsPath, $UserCachePath)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
    $links = @(
        @{ Name = 'models'; Target = (Resolve-Path -LiteralPath $UserModelsPath).Path }
        @{ Name = '.ovcache'; Target = (Resolve-Path -LiteralPath $UserCachePath).Path }
    )
    $created = @()
    foreach ($link in $links) {
        $linkPath = Join-Path $OvmsWorkingDirectory $link.Name
        if (Test-Path -LiteralPath $linkPath) {
            $item = Get-Item -LiteralPath $linkPath -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                $created += "$($link.Name)=junction(existing)"
                continue
            }
            if ($RepairBlockingDirectories) {
                $stamp = (Get-Date).ToString('yyyyMMddHHmmss')
                $backup = Join-Path $OvmsWorkingDirectory ($link.Name + '.pre-junction.' + $stamp)
                Rename-Item -LiteralPath $linkPath -NewName (Split-Path -Leaf $backup) -Force
                $created += "$($link.Name)=renamed_to_$(Split-Path -Leaf $backup)"
            } else {
                throw "OVMS user-data junction blocked: '$linkPath' exists as a normal folder (common after reboot or manual runs). Run repair-ovms-user-data-layout.ps1 or re-run invoke-ovms-agentic-setup.ps1 with updated agent-skills (auto-repair). Data under profile: $UserModelsPath / $UserCachePath"
            }
        }
        $out = cmd.exe /c "mklink /J `"$linkPath`" `"$($link.Target)`"" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create junction $linkPath -> $($link.Target): $out"
        }
        $created += "$($link.Name)=junction->$($link.Target)"
    }
    return $created
}

function Initialize-DevKitOvmsUserDataLayout {
    param(
        [string]$InstallRoot,
        [switch]$RepairBlockingDirectories
    )
    if ($env:AIPC_OVMS_USE_CLONE_PATHS -eq '1') {
        return @{
            ok       = $false
            skipped  = $true
            message  = 'AIPC_OVMS_USE_CLONE_PATHS=1 skips junction layout; unset for standard-user profile data'
            junction = @()
        }
    }
    $resolved = Find-DevKitOvmsAgenticScript -InstallRoot $InstallRoot
    if (-not $resolved) {
        return @{ ok = $false; skipped = $true; message = 'ovms_agentic_setup.ps1 not found'; junction = @() }
    }
    $ovmsDir = Split-Path -Path $resolved.script -Parent
    $paths = Get-OvmsUserScopedDataPaths
    try {
        $log = Enable-DevKitOvmsUserDataViaJunctions -OvmsWorkingDirectory $ovmsDir `
            -UserModelsPath $paths.Repo -UserCachePath $paths.Cache -RepairBlockingDirectories:$RepairBlockingDirectories
        $script:LastOvmsUserDataJunctionLog = $log
        return @{ ok = $true; skipped = $false; ovms_dir = $ovmsDir; junction = $log; profile_repo = $paths.Repo; profile_cache = $paths.Cache }
    } catch {
        return @{ ok = $false; skipped = $false; message = $_.Exception.Message; junction = @() }
    }
}

function Get-OvmsAgenticSetupStartProcessArguments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [Parameter(Mandatory = $true)]
        [string]$Model,
        [string]$Target = $script:DefaultOvmsTarget,
        [switch]$Pull,
        [switch]$Test,
        [int]$Port = 8000,
        [switch]$UseUserScopedDataPaths,
        [switch]$ForDetachedWindow
    )
    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass'
    )
    if ($ForDetachedWindow) {
        # Keep the window open when ovms_agentic_setup.ps1 errors so [ERROR] lines are visible.
        $args += '-NoExit'
    }
    $args += @('-File', $ScriptPath)
    if ($Test) { $args += '-Test' }
    if ($Pull) { $args += '-Pull' }
    $args += @('-Model', $Model, '-Target', $Target)
    if ($Port -ne 8000) {
        $args += @('-Port', [string]$Port)
    }
    $useUserPaths = $UseUserScopedDataPaths -or ($env:AIPC_OVMS_USER_DATA -eq '1')
    if ($env:AIPC_OVMS_USE_CLONE_PATHS -eq '1') {
        $useUserPaths = $false
    } elseif (-not $Test -and $ForDetachedWindow) {
        # Default for skill launch: keep models/cache under the signed-in user (avoids Admin-owned .\models under the clone).
        $useUserPaths = $true
    } elseif (-not (Test-DevKitSessionIsElevated) -and -not $Test) {
        $useUserPaths = $true
    }
    if ($useUserPaths) {
        $paths = Get-OvmsUserScopedDataPaths
        $ovmsDir = Split-Path -Path $ScriptPath -Parent
        $junctionLog = Enable-DevKitOvmsUserDataViaJunctions -OvmsWorkingDirectory $ovmsDir `
            -UserModelsPath $paths.Repo -UserCachePath $paths.Cache -RepairBlockingDirectories
        # Do not pass absolute -CacheDir / -ModelRepositoryPath: OVMS embeds them in JSON with broken backslash escaping.
        # Defaults models + .ovcache (relative to OVMS cwd) point at profile data via junctions above.
        $script:LastOvmsUserDataJunctionLog = $junctionLog
    }
    return $args
}

function Wait-OvmsEndpointReady {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,
        [int]$MaxWaitSec = 180,
        [int]$IntervalSec = 3
    )
    $deadline = (Get-Date).AddSeconds($MaxWaitSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $null = Invoke-RestMethod -Uri "$BaseUrl/models" -TimeoutSec 5
            return $true
        } catch {
            Start-Sleep -Seconds $IntervalSec
        }
    }
    return $false
}

function Get-OvmsModelIdsFromResponse {
    param([object]$ModelsResponse)
    if ($null -eq $ModelsResponse) { return @() }

    if ($ModelsResponse -is [string]) {
        try {
            $ModelsResponse = $ModelsResponse | ConvertFrom-Json
        } catch {
            return @()
        }
    }

    $ids = [System.Collections.Generic.List[string]]::new()

    if ($ModelsResponse -is [System.Array]) {
        foreach ($item in $ModelsResponse) {
            Add-OvmsModelIdFromResponseItem -Item $item -Ids $ids
        }
        return @(Get-OvmsModelIdsNormalized -Ids $ids)
    }

    foreach ($prop in @('data', 'models', 'items')) {
        if (-not $ModelsResponse.PSObject.Properties[$prop]) { continue }
        $collection = $ModelsResponse.$prop
        if ($collection -is [string]) {
            Add-OvmsModelIdFromResponseItem -Item $collection -Ids $ids
            continue
        }
        foreach ($item in @($collection)) {
            Add-OvmsModelIdFromResponseItem -Item $item -Ids $ids
        }
    }

    Add-OvmsModelIdFromResponseItem -Item $ModelsResponse -Ids $ids

    return @(Get-OvmsModelIdsNormalized -Ids $ids)
}

function Add-OvmsModelIdFromResponseItem {
    param(
        [object]$Item,
        [System.Collections.Generic.List[string]]$Ids
    )
    if ($null -eq $Item) { return }
    if ($Item -is [string]) {
        $Ids.Add($Item)
        return
    }
    foreach ($field in @('id', 'name', 'model', 'model_name')) {
        if ($Item.PSObject.Properties[$field]) {
            $Ids.Add([string]$Item.$field)
            return
        }
    }
}

function Get-OvmsModelIdsNormalized {
    param([System.Collections.Generic.List[string]]$Ids)
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($raw in $Ids) {
        $n = Normalize-OvmsModelIdForMatch -ModelId $raw
        if ($n) { $out.Add($n) }
    }
    return @($out | Select-Object -Unique)
}

function Normalize-OvmsModelIdForMatch {
    param([string]$ModelId)
    if ([string]::IsNullOrWhiteSpace($ModelId)) { return $null }
    $s = $ModelId.Trim().Trim([char]0xFEFF)
    $s = $s -replace '\\', '/'
    $s = $s -replace '[\u2010-\u2015\u2212]', '-'
    return $s
}

function Get-OvmsModelIdStem {
    param([string]$ModelId)
    if ([string]::IsNullOrWhiteSpace($ModelId)) { return $null }
    $s = Normalize-OvmsModelIdForMatch -ModelId $ModelId
    if ($s -match '[/\\]') { $s = ($s -split '[/\\]')[-1] }
    $s = $s -replace '-int4-ov$', '' -replace '-int8-ov$', ''
    return $s
}

function Get-OvmsRegexPatternForCatalogModel {
    param([string]$CatalogModelId)
    if ([string]::IsNullOrWhiteSpace($CatalogModelId)) { return $null }
    $catalog = Normalize-OvmsModelIdForMatch -ModelId $CatalogModelId
    $patterns = @{
        'OpenVINO/Qwen3.6-35B-A3B-int4-ov' = 'Qwen3\.6-35B-A3B.*'
        'OpenVINO/Muse-Glimmer-30B-int4-ov' = 'Muse-Glimmer-30B.*'
        'OpenVINO/Qwen3.5-0.8B-int4-ov'     = 'Qwen3\.5-0\.8B.*'
        'Qwen3.6-35B-A3B-int4-ov'           = 'Qwen3\.6-35B-A3B.*'
        'Qwen3.5-0.8B-int4-ov'              = 'Qwen3\.5-0\.8B.*'
        'Qwen3.6-35B-A3B'                   = 'Qwen3\.6-35B-A3B.*'
        'Qwen3.5-0.8B'                      = 'Qwen3\.5-0\.8B.*'
        'Qwen3\.6-35B-A3B.*'                = 'Qwen3\.6-35B-A3B.*'
        'Qwen3\.5-0\.8B.*'                  = 'Qwen3\.5-0\.8B.*'
        'OpenVINO/Qwen3-Coder-30B-A3B-Instruct-int4-ov' = 'Qwen3-Coder-30B-A3B-Instruct.*'
        'OpenVINO/Qwen3-Coder-30B-A3B-Instruct-int8-ov' = 'Qwen3-Coder-30B-A3B-Instruct.*'
        'Qwen3-Coder-30B-A3B-Instruct'        = 'Qwen3-Coder-30B-A3B-Instruct.*'
    }
    if ($patterns.ContainsKey($catalog)) { return $patterns[$catalog] }
    $stem = Get-OvmsModelIdStem -ModelId $catalog
    if (-not $stem) { return $null }
    if ($stem -match '35B-A3B') { return 'Qwen3\.6-35B-A3B.*' }
    if ($stem -match '0\.8B') { return 'Qwen3\.5-0\.8B.*' }
    $regexStem = [regex]::Escape($stem)
    return "${regexStem}.*"
}

function Test-OvmsAdvertisedIdMatchesCatalogModel {
    param(
        [string]$AdvertisedId,
        [string]$CatalogModelId,
        [string]$Pattern
    )
    $adv = Normalize-OvmsModelIdForMatch -ModelId $AdvertisedId
    $cat = Normalize-OvmsModelIdForMatch -ModelId $CatalogModelId
    if ([string]::IsNullOrWhiteSpace($adv)) { return $false }
    if ($cat -and ($adv -eq $cat)) { return $true }
    if ($Pattern) {
        try {
            if ([regex]::IsMatch($adv, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
                return $true
            }
        } catch { }
    }
    $catStem = Get-OvmsModelIdStem -ModelId $cat
    $advStem = Get-OvmsModelIdStem -ModelId $adv
    if ($catStem -and $advStem -and ($catStem -eq $advStem)) { return $true }
    if ($catStem -and ($adv -like "*$catStem*")) { return $true }
    $leaf = if ($cat) { ($cat -split '[/\\]')[-1] } else { $null }
    if ($leaf -and ($adv -like "*$leaf*")) { return $true }
    return $false
}

function Find-OvmsAdvertisedModelByCatalog {
    param(
        [AllowNull()]
        [string[]]$AdvertisedIds,
        [string]$CatalogModelId
    )
    $catalogNorm = Normalize-OvmsModelIdForMatch -ModelId $CatalogModelId
    $AdvertisedIds = @(
        $AdvertisedIds |
            ForEach-Object { Normalize-OvmsModelIdForMatch -ModelId $_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $pattern = Get-OvmsRegexPatternForCatalogModel -CatalogModelId $CatalogModelId
    if (-not $pattern) {
        return @{
            matched = $false
            id      = $null
            pattern = $null
            message = "No advertised-model regex for catalog id '$CatalogModelId'"
        }
    }
    foreach ($id in $AdvertisedIds) {
        if (Test-OvmsAdvertisedIdMatchesCatalogModel -AdvertisedId $id -CatalogModelId $catalogNorm -Pattern $pattern) {
            $via = if ($id -eq $catalogNorm) { 'exact' } else { 'regex/stem' }
            return @{
                matched = $true
                id      = $id
                pattern = $pattern
                message = "Advertised '$id' matched catalog '$CatalogModelId' ($via; pattern $pattern)"
            }
        }
    }
    $listed = if ($AdvertisedIds.Count) { $AdvertisedIds -join ', ' } else { 'none' }
    $hint = $null
    if ($AdvertisedIds.Count -gt 0 -and $catalogNorm -match '35B-A3B') {
        $smokePat = Get-OvmsRegexPatternForCatalogModel -CatalogModelId $script:DefaultVerifyModelId
        foreach ($id in $AdvertisedIds) {
            if (Test-OvmsAdvertisedIdMatchesCatalogModel -AdvertisedId $id -CatalogModelId $script:DefaultVerifyModelId -Pattern $smokePat) {
                $hint = " OVMS is serving the smoke model ($id); use -Profile agent (or -Model $($script:DefaultAgentModelId)) on OVMS setup before agent provider configure."
                break
            }
        }
    }
    return @{
        matched = $false
        id      = $null
        pattern = $pattern
        message = "No GET /v3/models id matched catalog '$CatalogModelId' (pattern $pattern; advertised: $listed).$hint"
    }
}

function Resolve-OvmsServingModelId {
    param(
        [AllowNull()]
        [string[]]$AvailableIds,
        [string]$PreferredModel
    )
    $match = Find-OvmsAdvertisedModelByCatalog -AdvertisedIds $AvailableIds -CatalogModelId $PreferredModel
    if ($match.matched) { return $match.id }
    return $null
}

function Get-OvmsAdvertisedModelIdForAgent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,
        [string]$CatalogModelId
    )
    $ids = @(Get-OvmsEndpointModelIdsSafe -BaseUrl $BaseUrl)
    $match = Find-OvmsAdvertisedModelByCatalog -AdvertisedIds $ids -CatalogModelId $CatalogModelId
    return @{
        source                     = 'GET /v3/models'
        advertised_ids             = $ids
        model_for_agent            = $match.id
        catalog_model_id           = $CatalogModelId
        advertised_match           = $match.matched
        advertised_match_pattern   = $match.pattern
        advertised_match_message   = $match.message
    }
}

function Test-AgenticInferenceFromEndpoint {
    param(
        [string]$BaseUrl = $null,
        [string[]]$AdvertisedIds = $null
    )
    $agentCatalog = $script:DefaultAgentModelId
    $verifyCatalog = $script:DefaultVerifyModelId
    $ids = @($AdvertisedIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($ids.Count -eq 0 -and $BaseUrl) {
        $ids = @(Get-OvmsEndpointModelIdsSafe -BaseUrl $BaseUrl)
    }
    $agentMatch = Find-OvmsAdvertisedModelByCatalog -AdvertisedIds $ids -CatalogModelId $agentCatalog
    $smokeMatch = Find-OvmsAdvertisedModelByCatalog -AdvertisedIds $ids -CatalogModelId $verifyCatalog
    return @{
        agent_inference_ready = [bool]$agentMatch.matched
        smoke_inference_ready = [bool]$smokeMatch.matched
        agent_serving_model   = $agentMatch.id
        smoke_serving_model   = $smokeMatch.id
        advertised_ids        = $ids
    }
}

function Apply-InferenceReadinessToResult {
    param(
        [object]$Result,
        [hashtable]$Eval
    )
    if (-not $Eval) { return }
    $Result.agent_inference_ready = [bool]$Eval.agent_inference_ready
    $Result.smoke_inference_ready = [bool]$Eval.smoke_inference_ready
    if ($Eval.agent_serving_model) { $Result.agent_serving_model = $Eval.agent_serving_model }
    if ($Eval.smoke_serving_model) { $Result.smoke_serving_model = $Eval.smoke_serving_model }
    if ($Eval.agent_inference_ready) {
        $Result.readiness_tier = 'agent'
    } elseif ($Eval.smoke_inference_ready) {
        $Result.readiness_tier = 'smoke'
    } else {
        $Result.readiness_tier = 'none'
    }
}

function Add-AgenticInferenceCheck {
    param(
        [object]$Result,
        [string]$CheckId = 'A1-agentic-inference',
        [string]$BaseUrl = $null,
        [string[]]$AdvertisedIds = $null,
        [switch]$OvmsNotRunning
    )
    if ($OvmsNotRunning) {
        Add-VerifyCheck -Result $Result -Check @{
            id      = $CheckId
            status  = 'skip'
            message = 'OVMS not running; agentic inference not evaluated'
        }
        return @{
            agent_inference_ready = $false
            smoke_inference_ready = $false
            agent_serving_model   = $null
            smoke_serving_model   = $null
            advertised_ids        = @()
        }
    }
    $eval = Test-AgenticInferenceFromEndpoint -BaseUrl $BaseUrl -AdvertisedIds $AdvertisedIds
    $checkStatus = if ($eval.agent_inference_ready) { 'pass' } else { 'fail' }
    $checkMessage = if ($eval.agent_inference_ready) {
        "Agentic inference ready (model=$($eval.agent_serving_model))"
    } elseif ($eval.smoke_inference_ready) {
        "Only smoke/verify model on server ($($eval.smoke_serving_model)); large agent model not loaded"
    } else {
        'Agent model not advertised on local OVMS endpoint'
    }
    Add-VerifyCheck -Result $Result -Check @{
        id      = $CheckId
        status  = $checkStatus
        message = $checkMessage
    }
    return $eval
}

function Get-OvmsChatModelCandidates {
    param(
        [AllowNull()]
        [string[]]$AvailableIds,
        [string]$PreferredModel
    )
    $list = [System.Collections.Generic.List[string]]::new()
    if ($AvailableIds) {
        foreach ($id in $AvailableIds) {
            if (-not [string]::IsNullOrWhiteSpace($id)) { $list.Add($id) }
        }
    }
    if ($PreferredModel) {
        $resolved = Find-OvmsAdvertisedModelByCatalog -AdvertisedIds $AvailableIds -CatalogModelId $PreferredModel
        if ($resolved.matched -and $resolved.id) { $list.Insert(0, $resolved.id) }
        $stem = Get-OvmsModelIdStem -ModelId $PreferredModel
        if ($stem) { $list.Add($stem) }
        $leaf = ($PreferredModel -split '/')[-1]
        if ($leaf) { $list.Add($leaf) }
        $list.Add($PreferredModel)
        if ($PreferredModel -match 'Qwen3\.5-0\.8B') { $list.Add('Qwen3.5-0.8B') }
        if ($PreferredModel -match 'Qwen3-8B') { $list.Add('Qwen3-8B') }
    }
    return @($list | Select-Object -Unique)
}

function Get-OvmsChatCompletionsUri {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl
    )
    $base = $BaseUrl.TrimEnd('/')
    if ($base -match '/v3$') {
        return "$base/chat/completions"
    }
    return "$base/v3/chat/completions"
}

function New-OvmsChatCompletionRequestBody {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelId,
        [int]$MaxTokens = 30,
        [string]$UserPrompt = 'Say hello in one sentence.'
    )
    $payload = @{
        model       = $ModelId
        max_tokens  = $MaxTokens
        temperature = 0
        stream      = $false
        messages    = @(
            @{ role = 'system'; content = 'You are a helpful assistant.' }
            @{ role = 'user'; content = $UserPrompt }
        )
    }
    return ($payload | ConvertTo-Json -Depth 5)
}

function Invoke-OvmsChatCompletionSmoke {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,
        [Parameter(Mandatory = $true)]
        [string]$ModelId,
        [int]$MaxTokens = 30,
        [int]$TimeoutSec = 120
    )
    $uri = Get-OvmsChatCompletionsUri -BaseUrl $BaseUrl
    $body = New-OvmsChatCompletionRequestBody -ModelId $ModelId -MaxTokens $MaxTokens
    $response = Invoke-WebRequest -Uri $uri -Method POST -UseBasicParsing `
        -Headers @{ 'Content-Type' = 'application/json' } `
        -Body $body -TimeoutSec $TimeoutSec -ErrorAction Stop
    if ($null -eq $response.Content -or $response.Content.Length -eq 0) {
        return @{}
    }
    return $response.Content | ConvertFrom-Json
}

function Get-OvmsHttpErrorDetail {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)
    $msg = $ErrorRecord.Exception.Message
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        $detail = [string]$ErrorRecord.ErrorDetails.Message
        if ($detail.Length -gt 400) { $detail = $detail.Substring(0, 400) + '...' }
        if ($detail -and ($detail -ne $msg)) {
            return "$msg $detail"
        }
    }
    try {
        $webEx = $ErrorRecord.Exception
        if ($webEx.InnerException -is [System.Net.WebException]) {
            $webEx = $webEx.InnerException
        }
        if ($webEx -is [System.Net.WebException] -and $webEx.Response) {
            $resp = $webEx.Response
        } else {
            $resp = $ErrorRecord.Exception.Response
        }
        if ($null -eq $resp) { return $msg }
        $code = [int]$resp.StatusCode
        $stream = $resp.GetResponseStream()
        if ($null -eq $stream) { return "$msg (HTTP $code)" }
        $reader = New-Object System.IO.StreamReader($stream)
        $text = $reader.ReadToEnd()
        $reader.Close()
        if ([string]::IsNullOrWhiteSpace($text)) { return "$msg (HTTP $code)" }
        if ($text.Length -gt 400) { $text = $text.Substring(0, 400) + '...' }
        return "$msg (HTTP $code) $text"
    } catch {
        return $msg
    }
}

function Invoke-OvmsWebPostJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [Parameter(Mandatory = $true)]
        [string]$BodyJson,
        [int]$TimeoutSec = 120
    )
    $previousExpect = [System.Net.ServicePointManager]::Expect100Continue
    [System.Net.ServicePointManager]::Expect100Continue = $false
    try {
        return Invoke-WebRequest -Uri $Uri -Method POST -UseBasicParsing `
            -Headers @{ 'Content-Type' = 'application/json' } `
            -Body $BodyJson -TimeoutSec $TimeoutSec -ErrorAction Stop
    } finally {
        [System.Net.ServicePointManager]::Expect100Continue = $previousExpect
    }
}

function Test-OvmsHttpStatusFromError {
    param(
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [int[]]$StatusCodes
    )
    $msg = $ErrorRecord.Exception.Message
    foreach ($code in $StatusCodes) {
        if ($msg -match "\(\s*$code\s*\)") { return $true }
        if ($msg -match "HTTP\s+$code") { return $true }
    }
    try {
        $resp = $ErrorRecord.Exception.Response
        if ($null -ne $resp -and ($StatusCodes -contains [int]$resp.StatusCode)) { return $true }
    } catch { }
    return $false
}

function Invoke-OvmsChatCompletionSmokeFirstSuccess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,
        [Parameter(Mandatory = $true)]
        [string[]]$ModelCandidates,
        [int]$MaxTokens = 16,
        [int]$TimeoutSec = 120,
        [int]$Retry412MaxWaitSec = 180,
        [int]$Retry412IntervalSec = 5
    )
    $lastError = $null
    $deadline = (Get-Date).AddSeconds($Retry412MaxWaitSec)
    foreach ($candidate in @($ModelCandidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        do {
            try {
                $resp = Invoke-OvmsChatCompletionSmoke -BaseUrl $BaseUrl -ModelId $candidate -MaxTokens $MaxTokens -TimeoutSec $TimeoutSec
                return @{ ok = $true; model = $candidate; response = $resp }
            } catch {
                $errRecord = $_
                $lastError = Get-OvmsHttpErrorDetail -ErrorRecord $errRecord
                $retry412 = (Test-OvmsHttpStatusFromError -ErrorRecord $errRecord -StatusCodes @(412, 503)) -and ((Get-Date) -lt $deadline)
                if (-not $retry412) { break }
                Start-Sleep -Seconds $Retry412IntervalSec
            }
        } while ($true)
    }
    return @{ ok = $false; model = $null; error = $(if ($lastError) { $lastError } else { 'No model candidates' }) }
}

function Get-OvmsSkillStateDirectory {
    $paths = Get-OvmsUserScopedDataPaths
    $dir = Join-Path $paths.Root '.skill-state'
    try {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    } catch { }
    return $dir
}

function Get-OvmsPullStateFilePath {
    return Join-Path (Get-OvmsSkillStateDirectory) 'pull-state.json'
}

function Get-OvmsPullState {
    $path = Get-OvmsPullStateFilePath
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Set-OvmsPullState {
    param(
        [string]$ModelId,
        [int]$LaunchPid,
        [string]$InstallRoot
    )
    $payload = @{
        model_id    = $ModelId
        launch_pid  = $LaunchPid
        install_root = $InstallRoot
        started_at  = (Get-Date).ToUniversalTime().ToString('o')
    }
    $path = Get-OvmsPullStateFilePath
    $payload | ConvertTo-Json -Compress | Set-Content -LiteralPath $path -Encoding UTF8
}

function Clear-OvmsPullState {
    $path = Get-OvmsPullStateFilePath
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

function Get-OvmsModelDiskRequirements {
    param([string]$ModelId)
    $folder = ($ModelId -split '/')[-1]
    $table = @{
        'OpenVINO/Qwen3.5-0.8B-int4-ov'     = @{ required_gb = 4; recommended_gb = 10 }
        'OpenVINO/Qwen3.6-35B-A3B-int4-ov'  = @{ required_gb = 25; recommended_gb = 45 }
        'OpenVINO/Qwen3-Coder-30B-A3B-Instruct-int4-ov' = @{ required_gb = 16; recommended_gb = 22 }
        'OpenVINO/Qwen3-Coder-30B-A3B-Instruct-int8-ov' = @{ required_gb = 16; recommended_gb = 36 }
    }
    if ($table.ContainsKey($ModelId)) {
        return @{ model_id = $ModelId; required_gb = $table[$ModelId].required_gb; recommended_gb = $table[$ModelId].recommended_gb }
    }
    if ($folder -match 'Coder-30B|Qwen3-Coder') {
        return @{ model_id = $ModelId; required_gb = 16; recommended_gb = 22 }
    }
    if ($folder -match '35B|27B|32B') {
        return @{ model_id = $ModelId; required_gb = 25; recommended_gb = 45 }
    }
    if ($folder -match '0\.8B|0\.6B|4B') {
        return @{ model_id = $ModelId; required_gb = 4; recommended_gb = 10 }
    }
    return @{ model_id = $ModelId; required_gb = 15; recommended_gb = 30 }
}

function Test-OvmsUserDataDiskPreflight {
    param(
        [string]$ModelId,
        [int]$MinFreeDiskGb = 0
    )
    $paths = Get-OvmsUserScopedDataPaths
    $checkPath = $paths.Root
    if (-not (Test-Path -LiteralPath $checkPath)) {
        try {
            New-Item -ItemType Directory -Path $checkPath -Force | Out-Null
        } catch { }
    }
    $req = Get-OvmsModelDiskRequirements -ModelId $ModelId
    $required = if ($MinFreeDiskGb -gt 0) { $MinFreeDiskGb } else { $req.required_gb }
    $recommended = $req.recommended_gb
    $freeGb = Get-DevKitFreeDiskSpaceGb -Path $checkPath
    $ok = ($null -ne $freeGb) -and ($freeGb -ge $required)
    return @{
        ok             = $ok
        volume_path    = $checkPath
        free_gb        = $freeGb
        required_gb    = $required
        recommended_gb = $recommended
        model_id       = $ModelId
        scopes         = @($paths.Repo, $paths.Cache)
    }
}

function Get-OvmsTcpPortListener {
    param([int]$Port = 8000)
    $listeners = @()
    try {
        $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop
        foreach ($c in @($conns)) {
            $procName = $null
            try {
                $procName = (Get-Process -Id $c.OwningProcess -ErrorAction Stop).ProcessName
            } catch { }
            $listeners += @{
                port         = $Port
                pid          = $c.OwningProcess
                process_name = $procName
            }
        }
    } catch {
        try {
            $lines = netstat -ano | Select-String -Pattern ":\s*$Port\s+.*LISTENING"
            foreach ($line in $lines) {
                $parts = ($line -split '\s+') | Where-Object { $_ }
                $listenPid = [int]$parts[-1]
                $procName = $null
                try { $procName = (Get-Process -Id $listenPid -ErrorAction Stop).ProcessName } catch { }
                $listeners += @{ port = $Port; pid = $listenPid; process_name = $procName }
            }
        } catch { }
    }
    return @($listeners | Select-Object -Property port, pid, process_name -Unique)
}

function Get-OvmsEndpointModelIdsSafe {
    param(
        [string]$BaseUrl,
        [int]$TimeoutSec = 5
    )
    try {
        $resp = Invoke-RestMethod -Uri "$BaseUrl/models" -TimeoutSec $TimeoutSec
        return @(Get-OvmsModelIdsFromResponse -ModelsResponse $resp)
    } catch {
        return @()
    }
}

function Test-OvmsModelIntentSatisfied {
    param(
        [string[]]$AvailableIds,
        [string]$PreferredModel
    )
    $match = Find-OvmsAdvertisedModelByCatalog -AdvertisedIds $AvailableIds -CatalogModelId $PreferredModel
    return [bool]$match.matched
}

function Test-OvmsModelPullRetryRequired {
    param(
        [string]$ModelId,
        [string]$InstallRoot
    )
    $state = Get-OvmsPullState
    if ($state) {
        $started = [datetime]::MinValue
        if ($state.started_at) {
            try { $started = [datetime]::Parse($state.started_at) } catch { }
        }
        $ageMin = if ($started -ne [datetime]::MinValue) { ((Get-Date) - $started).TotalMinutes } else { 0 }
        if ($ageMin -lt 240) { return @{ required = $true; reason = 'pull_state_file_present' } }
    }
    $paths = Get-OvmsUserScopedDataPaths
    $onDisk = Test-OvmsModelOnDisk -ModelCacheRoot $paths.Repo -ModelId $ModelId -Strict
    if ($onDisk.found) {
        return @{ required = $true; reason = 'model_already_on_disk' }
    }
    $folderName = ($ModelId -split '/')[-1]
    $partial = Join-Path $paths.Repo (Join-Path 'OpenVINO' $folderName)
    if (Test-Path -LiteralPath $partial) {
        return @{ required = $true; reason = 'partial_model_directory' }
    }
    return @{ required = $false; reason = $null }
}

function Stop-DevKitOvmsListenerProcess {
    param(
        [Parameter(Mandatory = $true)]
        [int]$ProcessId
    )
    try {
        $proc = Get-Process -Id $ProcessId -ErrorAction Stop
    } catch {
        return @{ ok = $false; message = "Process $ProcessId not found" }
    }
    if ($proc.ProcessName -notmatch '^ovms$') {
        return @{
            ok      = $false
            message = "Refusing to stop PID $ProcessId ($($proc.ProcessName)); only ovms.exe is allowed"
        }
    }
    try {
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        Start-Sleep -Seconds 2
        return @{ ok = $true; message = "Stopped ovms.exe PID $ProcessId" }
    } catch {
        return @{ ok = $false; message = $_.Exception.Message }
    }
}

function Resolve-OvmsLaunchPreflight {
    param(
        [object]$Result,
        [string]$InstallRoot,
        [string]$ModelId,
        [string]$Target,
        [switch]$Pull,
        [switch]$Approve,
        [switch]$ApproveRetryPull,
        [switch]$ApproveStopOvms,
        [int]$MinFreeDiskGb = 0,
        [int]$Port = 8000,
        [switch]$SkipLaunch
    )
    $baseUrl = Get-OvmsBaseUrl -Port $Port
    $plan = @{
        proceed_launch   = $true
        effective_pull   = [bool]$Pull
        effective_skip   = [bool]$SkipLaunch
        reuse_endpoint   = $false
        blocked          = $false
        error            = $null
    }

    if ($Pull) {
        $retry = Test-OvmsModelPullRetryRequired -ModelId $ModelId -InstallRoot $InstallRoot
        if ($retry.required -and -not $ApproveRetryPull) {
            $plan.blocked = $true
            $plan.proceed_launch = $false
            $plan.error = @{
                code        = 'RETRY_PULL_REQUIRES_APPROVAL'
                message     = "Model pull requires -ApproveRetryPull (reason=$($retry.reason)); resume uses existing partial data under %USERPROFILE%\OVMS"
                remediation = 'Ask the user to approve retry, then re-run with -Approve -ApproveRetryPull -Pull'
            }
            return $plan
        }
        $disk = Test-OvmsUserDataDiskPreflight -ModelId $ModelId -MinFreeDiskGb $MinFreeDiskGb
        $Result | Add-Member -NotePropertyName ovms_disk_preflight -NotePropertyValue $disk -Force
        if (-not $disk.ok) {
            $plan.blocked = $true
            $plan.proceed_launch = $false
            $plan.error = @{
                code        = 'DISK_INSUFFICIENT'
                message     = "Free $($disk.free_gb) GB on $($disk.volume_path); need >= $($disk.required_gb) GB for $($disk.model_id) (models + .ovcache on same volume)"
                remediation = 'Free disk space or pass -MinFreeDiskGb after user confirms a lower threshold'
            }
            return $plan
        }
        $activePull = Get-OvmsPullState
        if ($activePull) {
            $launcherAlive = $false
            if ($activePull.launch_pid) {
                try {
                    $null = Get-Process -Id ([int]$activePull.launch_pid) -ErrorAction Stop
                    $launcherAlive = $true
                } catch { }
            }
            if ($launcherAlive) {
                $plan.blocked = $true
                $plan.proceed_launch = $false
                $plan.error = @{
                    code        = 'PULL_IN_PROGRESS'
                    message     = "Another OVMS pull may be in progress (state file; model=$($activePull.model_id) pid=$($activePull.launch_pid))"
                    remediation = 'Wait for the other pull window to finish, or re-run with -ApproveRetryPull after user confirms the other job failed'
                }
                return $plan
            }
            $Result.warnings += 'Cleared stale OVMS pull-state (launcher PID not running)'
            Clear-OvmsPullState
        }
    }

    $listeners = @(Get-OvmsTcpPortListener -Port $Port)
    if ($listeners.Count -eq 0) {
        return $plan
    }

    $listener = $listeners[0]
    $advertised = @(Get-OvmsEndpointModelIdsSafe -BaseUrl $baseUrl)
    $intentOk = Test-OvmsModelIntentSatisfied -AvailableIds $advertised -PreferredModel $ModelId
    $Result | Add-Member -NotePropertyName ovms_port_listener -NotePropertyValue $listener -Force
    $Result | Add-Member -NotePropertyName ovms_advertised_models -NotePropertyValue $advertised -Force

    if ($intentOk -and -not $Pull) {
        $plan.reuse_endpoint = $true
        $plan.effective_skip = $true
        $plan.proceed_launch = $false
        $Result.warnings += "Port $Port in use; reusing endpoint serving requested model (PID $($listener.pid) $($listener.process_name))"
        return $plan
    }

    if ($intentOk -and $Pull) {
        $plan.reuse_endpoint = $true
        $plan.effective_skip = $true
        $plan.effective_pull = $false
        $plan.proceed_launch = $false
        $Result.warnings += 'Port already serves requested model; skipping redundant -Pull and launch'
        return $plan
    }

    $plan.proceed_launch = $false
    if (-not $ApproveStopOvms) {
        $plan.blocked = $true
        $plan.error = @{
            code        = 'PORT_CONFLICT'
            message     = "Port $Port in use by PID $($listener.pid) ($($listener.process_name)); advertised=$(if ($advertised.Count) { $advertised -join ', ' } else { '(none or non-OVMS)' }); requested=$ModelId"
            remediation = 'Pass -ApproveStopOvms after user approves stopping the listener (only ovms.exe is stopped)'
        }
        return $plan
    }

    $stop = Stop-DevKitOvmsListenerProcess -ProcessId $listener.pid
    $Result.logs += $stop.message
    if (-not $stop.ok) {
        $plan.blocked = $true
        $plan.error = @{
            code        = 'PORT_CONFLICT'
            message     = $stop.message
            remediation = 'Resolve the port conflict manually, then re-run'
        }
        return $plan
    }
    $Result.warnings += "Stopped listener on port $Port per -ApproveStopOvms"
    $plan.proceed_launch = $true
    return $plan
}

function New-HermesLocalProviderHandoff {
    param(
        [string]$BaseUrl,
        [string]$ModelId,
        [string]$ServingModel,
        [string]$TargetAgent = 'hermes'
    )
    $modelForConfig = if ($ServingModel) { $ServingModel } else { $ModelId }
    $steps = @(
        'Confirm OVMS is ready (O2/O4 pass in intel-ovms-agentic-setup or provider O1).'
        "Run: hermes model - set base URL to $BaseUrl and model to $modelForConfig (copy exact id from GET /v3/models; not the OpenVINO catalog path)."
        'Optional: review staged ~/.hermes/config.yaml diff from this skill before any manual edit.'
        'Start a new chat or /new after switching so the session uses local inference.'
        "Send a test prompt; reply should cite model $modelForConfig."
    )
    return @{
        target_agent          = $TargetAgent
        endpoint              = $BaseUrl
        model_id              = $modelForConfig
        requires_new_session  = $true
        provider_apply_manual = $true
        hermes_cli_steps      = $steps
        ovms_required_before_provider = $true
        next_skill_after_ovms = 'intel-agent-provider-config'
    }
}

function Invoke-DevKitOvmsAgenticSetup {
    param(
        [string]$InstallRoot,
        [Parameter(Mandatory = $true)]
        [string]$Model,
        [string]$Target = $script:DefaultOvmsTarget,
        [switch]$Pull,
        [switch]$Test,
        [int]$Port = 8000
    )
    $resolved = Find-DevKitOvmsAgenticScript -InstallRoot $InstallRoot
    if (-not $resolved) {
        return @{
            ok        = $false
            exit_code = 1
            logs      = @()
            message   = 'ovms_agentic_setup.ps1 not found'
        }
    }
    $ovmsScript = $resolved.script
    $scriptDir = Split-Path -Path $ovmsScript -Parent

    if ($Test) {
        $params = @{
            Model  = $Model
            Target = $Target
            Test   = $true
        }
        if ($Port -and $Port -ne 8000) { $params.Port = $Port }
        $run = Invoke-DevKitExternalScript -ScriptPath $ovmsScript -BoundParameters $params
        return @{
            ok           = ($run.exit_code -eq 0)
            exit_code    = $run.exit_code
            logs         = @($run.log_line) + $run.output
            message      = if ($run.exit_code -eq 0) { 'ovms_agentic_setup.ps1 -Test completed' } else { "ovms_agentic_setup.ps1 -Test exit $($run.exit_code)" }
            script       = $ovmsScript
            discovery    = $resolved.discovery
            install_root = $resolved.install_root
            detached     = $false
        }
    }

    # Launch mode: upstream script runs ovms.exe in the foreground; start in a separate process so the skill can finish O2-O5.
    $procArgs = Get-OvmsAgenticSetupStartProcessArguments -ScriptPath $ovmsScript -Model $Model -Target $Target -Pull:$Pull -Port $Port -ForDetachedWindow
    try {
        Write-Host "Starting ovms_agentic_setup.ps1 in a separate window (server keeps running there after this skill exits)." -ForegroundColor Yellow
        Write-Host "If launch fails, read [ERROR] in that window (-NoExit). Optional: run the same command manually in ...\OVMS" -ForegroundColor Yellow
        $proc = Start-Process -FilePath 'powershell.exe' `
            -ArgumentList $procArgs `
            -WorkingDirectory $scriptDir `
            -PassThru
        if ($Pull) {
            Set-OvmsPullState -ModelId $Model -LaunchPid $proc.Id -InstallRoot $InstallRoot
        }
        $launchLogs = @(
            "ovms_pull_state=$(Get-OvmsPullStateFilePath)"
            "invoke (detached PS): $ovmsScript PID=$($proc.Id)"
            "detached_window=powershell -NoExit (errors remain visible if script exits)"
            "launcher_cwd=$scriptDir"
        )
        $usp = Get-OvmsUserScopedDataPaths
        $launchLogs += "user_model_repo=$($usp.Repo)"
        $launchLogs += "user_cache_dir=$($usp.Cache)"
        if ($script:LastOvmsUserDataJunctionLog) {
            $launchLogs += @($script:LastOvmsUserDataJunctionLog)
        }
        $launchLogs += 'ovms_launch_uses_relative_models_and_dot_ovcache_via_junctions'
        $launchLogs += 'OVMS server blocks the child script until stopped; leave that window open or stop ovms.exe when done'
        return @{
            ok           = $true
            exit_code    = 0
            logs         = $launchLogs
            message      = "ovms_agentic_setup.ps1 started detached (PID $($proc.Id))"
            script       = $ovmsScript
            discovery    = $resolved.discovery
            install_root = $resolved.install_root
            detached     = $true
            launch_pid   = $proc.Id
        }
    } catch {
        return @{
            ok           = $false
            exit_code    = 1
            logs         = @($_.Exception.Message)
            message      = 'Failed to start ovms_agentic_setup.ps1 detached'
            script       = $ovmsScript
            discovery    = $resolved.discovery
            install_root = $resolved.install_root
            detached     = $false
        }
    }
}

function Add-OvmsSetupChecksToResult {
    param(
        [object]$Result,
        [string]$InstallRoot,
        [string]$ModelId,
        [string]$Target,
        [switch]$Pull,
        [switch]$RunToolTest,
        [switch]$SkipLaunch,
        [switch]$Approve,
        [switch]$ApproveRetryPull,
        [switch]$ApproveStopOvms,
        [switch]$SkipChatSmoke,
        [int]$MinFreeDiskGb = 0,
        [int]$Port = 8000
    )
    $baseUrl = Get-OvmsBaseUrl -Port $Port
    $Result.endpoint = $baseUrl
    $Result.model = $ModelId
    $Result | Add-Member -NotePropertyName ovms_skill_state_dir -NotePropertyValue (Get-OvmsSkillStateDirectory) -Force
    $Result | Add-Member -NotePropertyName ovms_pull_state_path -NotePropertyValue (Get-OvmsPullStateFilePath) -Force

    $preflight = Resolve-OvmsLaunchPreflight -Result $Result -InstallRoot $InstallRoot -ModelId $ModelId -Target $Target `
        -Pull:$Pull -Approve:$Approve -ApproveRetryPull:$ApproveRetryPull -ApproveStopOvms:$ApproveStopOvms `
        -MinFreeDiskGb $MinFreeDiskGb -Port $Port -SkipLaunch:$SkipLaunch
    if ($preflight.blocked) {
        $Result.error = $preflight.error
        $Result.functional_status = 'blocked'
        $Result.overall_status = 'blocked'
        $Result.exit_code = 2
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'O0-preflight'
            status  = 'fail'
            message = "$($preflight.error.code): $($preflight.error.message)"
        }
        Add-VerifyCheck -Result $Result -Check @{ id = 'O1-launch'; status = 'skip'; message = 'Blocked by preflight' }
        Add-VerifyCheck -Result $Result -Check @{ id = 'O2-health'; status = 'skip'; message = 'Blocked by preflight' }
        Add-VerifyCheck -Result $Result -Check @{ id = 'O3-tool-test'; status = 'skip'; message = 'Blocked by preflight' }
        Add-VerifyCheck -Result $Result -Check @{ id = 'O4-chat'; status = 'skip'; message = 'Blocked by preflight' }
        return
    }
    $effectivePull = $preflight.effective_pull
    $effectiveSkip = $preflight.effective_skip -or $SkipLaunch
    if ($preflight.reuse_endpoint) {
        $Result | Add-Member -NotePropertyName ovms_reuse_endpoint -NotePropertyValue $true -Force
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'O0-preflight'
            status  = 'pass'
            message = 'Reusing existing OVMS endpoint on requested port'
        }
    }

    Add-OvmsInstallationEvidence -Result $Result -InstallRoot $InstallRoot -Phase 'before'

    if (-not $effectiveSkip) {
        $launch = Invoke-DevKitOvmsAgenticSetup -InstallRoot $InstallRoot -Model $ModelId -Target $Target -Pull:$effectivePull -Port $Port
        if ($launch.script) { $Result.logs += $launch.script }
        if ($launch.discovery) { $Result | Add-Member -NotePropertyName ovms_script_discovery -NotePropertyValue $launch.discovery -Force }
        if ($launch.install_root) { $Result | Add-Member -NotePropertyName devkit_install_root_resolved -NotePropertyValue $launch.install_root -Force }
        foreach ($line in $launch.logs) {
            if ($line) { $Result.logs += $line }
        }
        if ($launch.launch_pid) {
            $Result | Add-Member -NotePropertyName ovms_launch_pid -NotePropertyValue $launch.launch_pid -Force
        }
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'O1-launch'
            status  = $(if ($launch.ok) { 'pass' } else { 'fail' })
            message = $launch.message
        }
        if (-not $launch.ok) {
            $Result.warnings += 'O1 launch failed; continuing health checks if OVMS is already running'
        }
        Add-OvmsInstallationEvidence -Result $Result -InstallRoot $InstallRoot -Phase 'after'
    } else {
        $o1Msg = if ($Result.ovms_reuse_endpoint) {
            'Launch skipped (preflight reuses running OVMS on port)'
        } elseif ($SkipLaunch) {
            'Launch skipped (-SkipLaunch); assuming OVMS already started'
        } else {
            'Launch skipped; assuming OVMS already started'
        }
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'O1-launch'
            status  = 'skip'
            message = $o1Msg
        }
    }

    $healthWaitSec = if ($effectivePull) { 900 } else { 180 }
    $ready = Wait-OvmsEndpointReady -BaseUrl $baseUrl -MaxWaitSec $healthWaitSec
    if (-not $ready) {
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'O2-health'
            status  = 'fail'
            message = "GET $baseUrl/models timed out"
        }
        Add-VerifyCheck -Result $Result -Check @{ id = 'O3-tool-test'; status = 'skip'; message = 'OVMS not reachable' }
        Add-VerifyCheck -Result $Result -Check @{ id = 'O4-chat'; status = 'skip'; message = 'OVMS not reachable' }
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'O5-logs'
            status  = 'pass'
            message = 'See logs[] in skill result for ovms_agentic_setup.ps1 output'
        }
        $Result.warnings += 'O6-teardown: stop the OVMS process started by ovms_agentic_setup.ps1 when finished (Task Manager or installer docs)'
        return
    }

    try {
        # GET /v3/models can succeed before the requested model is registered.
        $modelWaitSec = if ($effectivePull) { 900 } else { 180 }
        $modelDeadline = (Get-Date).AddSeconds($modelWaitSec)
        $modelsResp = $null
        $ids = @()
        $advMatch = $null
        $sawModelList = $false
        do {
            try {
                $modelsResp = Invoke-RestMethod -Uri "$baseUrl/models" -TimeoutSec 10
                $sawModelList = $true
                $ids = @(Get-OvmsModelIdsFromResponse -ModelsResponse $modelsResp)
                $advMatch = Find-OvmsAdvertisedModelByCatalog -AdvertisedIds $ids -CatalogModelId $ModelId
                if ($advMatch.matched) { break }
            } catch {
                $advMatch = @{
                    matched = $false
                    id      = $null
                    pattern = $null
                    message = $_.Exception.Message
                }
            }
            if ((Get-Date) -ge $modelDeadline) { break }
            Start-Sleep -Seconds 5
        } while ($true)
        if (-not $sawModelList) { throw $advMatch.message }
        if ($ids.Count -eq 0) {
            try {
                $Result.logs += ('models_json=' + ($modelsResp | ConvertTo-Json -Depth 8 -Compress))
            } catch {
                $Result.logs += ('models_raw=' + [string]$modelsResp)
            }
        }
        $Result | Add-Member -NotePropertyName ovms_advertised_match_pattern -NotePropertyValue $advMatch.pattern -Force
        $intentOk = $advMatch.matched
        $servingModel = $advMatch.id
        $Result.serving_model = $servingModel
        $chatCandidates = Get-OvmsChatModelCandidates -AvailableIds $ids -PreferredModel $ModelId
        $Result | Add-Member -NotePropertyName chat_model_candidates -NotePropertyValue $chatCandidates -Force
        if (-not $intentOk) {
            Add-VerifyCheck -Result $Result -Check @{
                id      = 'O2-health'
                status  = 'fail'
                message = $advMatch.message
            }
            $Result.error = @{
                code        = 'MODEL_ADVERTISED_MISMATCH'
                message     = $advMatch.message
                remediation = 'Stop wrong OVMS (-ApproveStopOvms) or restart with -Profile/-Model for the catalog id; Hermes must use an id that matches the catalog regex on GET /v3/models'
            }
        } else {
            Add-VerifyCheck -Result $Result -Check @{
                id      = 'O2-health'
                status  = 'pass'
                message = "GET /v3/models OK; ids=$(if ($ids.Count) { ($ids -join ', ') } else { '(none parsed - see logs models_json)' })"
            }
        }
    } catch {
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'O2-health'
            status  = 'fail'
            message = $_.Exception.Message
        }
        $servingModel = $ModelId
        $chatCandidates = Get-OvmsChatModelCandidates -AvailableIds @() -PreferredModel $ModelId
    }

    $toolRun = $null
    $o2Fail = @($Result.checks | Where-Object { $_.id -eq 'O2-health' -and $_.status -eq 'fail' })
    if ($o2Fail.Count -gt 0) {
        Add-VerifyCheck -Result $Result -Check @{ id = 'O3-tool-test'; status = 'skip'; message = 'O2 model intent failed' }
        Add-VerifyCheck -Result $Result -Check @{ id = 'O4-chat'; status = 'skip'; message = 'O2 model intent failed' }
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'O5-logs'
            status  = 'pass'
            message = 'See logs[] in skill result'
        }
        return
    }

    if ($RunToolTest) {
        $chatWarmSec = if ($effectivePull) { 600 } else { 120 }
        $Result.logs += "O3-prep: polling POST /v3/chat/completions up to ${chatWarmSec}s (GET /v3/models can succeed before inference is ready)"
        $warmChat = Invoke-OvmsChatCompletionSmokeFirstSuccess -BaseUrl $baseUrl -ModelCandidates $chatCandidates -MaxTokens 8 -TimeoutSec 90 -Retry412MaxWaitSec $chatWarmSec -Retry412IntervalSec 5
        if ($warmChat.ok) {
            $Result.serving_model = $warmChat.model
            $Result.logs += "O3-prep: chat ready (model=$($warmChat.model))"
        } else {
            $Result.warnings += 'O3-prep: chat smoke did not succeed before ovms_agentic_setup.ps1 -Test; O3 may fail until OVMS finishes compile/warmup'
        }

        $toolRun = Invoke-DevKitOvmsAgenticSetup -InstallRoot $InstallRoot -Model $ModelId -Target $Target -Test -Port $Port
        foreach ($line in $toolRun.logs) {
            if ($line) { $Result.logs += $line }
        }
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'O3-tool-test'
            status  = $(if ($toolRun.ok) { 'pass' } else { 'fail' })
            message = $toolRun.message
        }
    } else {
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'O3-tool-test'
            status  = 'skip'
            message = 'Tool-call test skipped (use -RunToolTest or -Profile verify)'
        }
    }

    try {
        if ($SkipChatSmoke) {
            Add-VerifyCheck -Result $Result -Check @{
                id      = 'O4-chat'
                status  = 'skip'
                message = 'Chat smoke skipped (-SkipChatSmoke); confirm completions in Continue or run invoke-ovms-agentic-setup.ps1 -Profile verify'
            }
        } elseif ($RunToolTest -and $toolRun -and $toolRun.ok) {
            $Result.serving_model = if ($Result.serving_model) { $Result.serving_model } else { $ModelId }
            Clear-OvmsPullState
            Add-VerifyCheck -Result $Result -Check @{
                id      = 'O4-chat'
                status  = 'pass'
                message = "POST /v3/chat/completions OK (ovms_agentic_setup.ps1 -Test; model=$($Result.serving_model))"
            }
        } else {
            $chatRetrySec = if ($effectivePull) { 600 } else { 180 }
            $chatRun = Invoke-OvmsChatCompletionSmokeFirstSuccess -BaseUrl $baseUrl -ModelCandidates $chatCandidates -MaxTokens 30 -TimeoutSec 120 -Retry412MaxWaitSec $chatRetrySec
            if ($chatRun.ok) {
                $Result.serving_model = $chatRun.model
                Clear-OvmsPullState
                Add-VerifyCheck -Result $Result -Check @{
                    id      = 'O4-chat'
                    status  = 'pass'
                    message = "POST /v3/chat/completions OK (model=$($chatRun.model))"
                }
            } else {
                Add-VerifyCheck -Result $Result -Check @{
                    id      = 'O4-chat'
                    status  = 'fail'
                    message = "$($chatRun.error); POST $(Get-OvmsChatCompletionsUri -BaseUrl $baseUrl); tried: $(($chatCandidates -join ', '))"
                }
            }
        }
    } catch {
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'O4-chat'
            status  = 'fail'
            message = $_.Exception.Message
        }
    }

    Add-VerifyCheck -Result $Result -Check @{
        id      = 'O5-logs'
        status  = 'pass'
        message = 'ovms_agentic_setup.ps1 output captured in logs[]'
    }
    $Result.warnings += 'O6-teardown: stop OVMS when done (see Dev Kit OVMS documentation)'
}

function Add-AgentOvmsSetupCheck {
    param(
        [object]$Result,
        [switch]$Approve,
        [switch]$Pull,
        [switch]$ApproveRetryPull,
        [switch]$ApproveStopOvms,
        [string]$ModelId = $null,
        [string]$Target = $script:DefaultAgentOvmsTarget,
        [int]$MinFreeDiskGb = 0,
        [int]$Port = 8000
    )
    if (-not $ModelId) { $ModelId = $script:DefaultAgentModelId }
    $Result.agent_model = $ModelId
    $baseUrl = Get-OvmsBaseUrl -Port $Port
    $Result.endpoint = if ($Result.endpoint) { $Result.endpoint } else { $baseUrl }

    if (-not $Pull) {
        $ids = @(Get-OvmsEndpointModelIdsSafe -BaseUrl $baseUrl)
        $advMatch = Find-OvmsAdvertisedModelByCatalog -AdvertisedIds $ids -CatalogModelId $ModelId
        if ($advMatch.matched) {
            $Result.serving_model = $advMatch.id
            $Result | Add-Member -NotePropertyName ovms_advertised_match_pattern -NotePropertyValue $advMatch.pattern -Force
            Add-VerifyCheck -Result $Result -Check @{
                id      = 'O1-agent-ovms-model'
                status  = 'pass'
                message = "OVMS on port $Port; $($advMatch.message)"
            }
            return
        }
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'O1-agent-ovms-model'
            status  = 'fail'
            message = $advMatch.message
        }
        $Result.functional_status = 'blocked'
        $Result.exit_code = 2
        $Result.next_skill = 'intel-ovms-agentic-setup'
        $Result.error = @{
            code        = 'OVMS_NOT_READY'
            message     = "Local OVMS must serve $ModelId before provider handoff"
            remediation = 'Run invoke-ovms-agentic-setup.ps1 -Approve -Pull -Profile agent (or -ApproveStopOvms if port conflict), then re-run configure with -Pull:$false'
        }
        $Result.warnings += 'Switch-to-local flow: start OVMS first; this skill stages provider config and handoff steps only'
        return
    }

    if (-not (Test-ApprovalRequired -RiskClass 'network' -Approve:$Approve)) {
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'O1-agent-ovms-model'
            status  = 'skip'
            message = 'Agent model download requires -Approve (network)'
        }
        $Result.functional_status = 'blocked'
        $Result.exit_code = 2
        return
    }
    $root = Find-DevKitInstallRoot
    if (-not $root) {
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'O1-agent-ovms-model'
            status  = 'fail'
            message = 'Dev Kit install root not found'
        }
        return
    }
    $Result.devkit_install_root = $root
    $ovmsChecks = Get-SkillResultSkeleton -SkillId 'intel-ovms-agentic-setup-internal' -RiskClass 'network' -FunctionalStatus 'fail'
    Add-OvmsSetupChecksToResult -Result $ovmsChecks -InstallRoot $root -ModelId $ModelId -Target $Target `
        -Pull -Approve:$Approve -ApproveRetryPull:$ApproveRetryPull -ApproveStopOvms:$ApproveStopOvms `
        -MinFreeDiskGb $MinFreeDiskGb -Port $Port
    foreach ($line in $ovmsChecks.logs) { if ($line) { $Result.logs += $line } }
    if ($ovmsChecks.error) { $Result.error = $ovmsChecks.error }
    if ($ovmsChecks.serving_model) { $Result.serving_model = $ovmsChecks.serving_model }
    foreach ($c in $ovmsChecks.checks) {
        if ($c.id -match '^O[0-9]') { Add-VerifyCheck -Result $Result -Check $c }
    }
    $o1 = @($ovmsChecks.checks | Where-Object { $_.id -eq 'O1-launch' } | Select-Object -First 1)
    $o2 = @($ovmsChecks.checks | Where-Object { $_.id -eq 'O2-health' -and $_.status -eq 'pass' })
    $o4 = @($ovmsChecks.checks | Where-Object { $_.id -eq 'O4-chat' -and $_.status -eq 'pass' })
    $agentStatus = 'fail'
    $agentMsg = 'Agent OVMS setup did not complete'
    if ($ovmsChecks.functional_status -eq 'blocked') {
        $Result.functional_status = 'blocked'
        $Result.exit_code = 2
        $agentStatus = 'fail'
        $agentMsg = if ($ovmsChecks.error) { "$($ovmsChecks.error.code): $($ovmsChecks.error.message)" } else { 'Blocked during OVMS setup' }
    } elseif ($o2.Count -gt 0 -and $o4.Count -gt 0) {
        $agentStatus = 'pass'
        $agentMsg = "Agent model ready on local server (catalog: $ModelId)"
    } elseif ($o2.Count -gt 0) {
        $agentStatus = 'partial'
        $agentMsg = "Models listed on server; chat smoke pending or failed (catalog: $ModelId)"
    } elseif ($o1 -and $o1.status -eq 'pass') {
        $agentStatus = 'partial'
        $agentMsg = "OVMS launch started; health/chat checks incomplete (catalog: $ModelId)"
    }
    Add-VerifyCheck -Result $Result -Check @{
        id      = 'O1-agent-ovms-model'
        status  = $agentStatus
        message = $agentMsg
    }
}

function Add-MinimalInferenceVerifyCheck {
    param(
        [object]$Result,
        [string]$ModelId = $script:DefaultVerifyModelId
    )
    $running = @($Result.checks | Where-Object { $_.id -eq 'V4-ovms-running' -and $_.status -eq 'pass' })
    if ($running.Count -eq 0) {
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'V5-minimal-inference'
            status  = 'skip'
            message = 'OVMS not running'
        }
        return
    }
    $baseUrl = if ($Result.endpoint) { $Result.endpoint } else { $script:DefaultOvmsBaseUrl }
    try {
        $modelsResp = Invoke-RestMethod -Uri "$baseUrl/models" -TimeoutSec 10
        $ids = @(Get-OvmsModelIdsFromResponse -ModelsResponse $modelsResp)
        $chatCandidates = Get-OvmsChatModelCandidates -AvailableIds $ids -PreferredModel $ModelId
        $chatRun = Invoke-OvmsChatCompletionSmokeFirstSuccess -BaseUrl $baseUrl -ModelCandidates $chatCandidates -MaxTokens 8 -TimeoutSec 90
        if (-not $chatRun.ok) {
            throw [System.InvalidOperationException]::new($chatRun.error)
        }
        $Result.serving_model = $chatRun.model
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'V5-minimal-inference'
            status  = 'pass'
            message = "Chat completion OK (model=$($chatRun.model))"
        }
    } catch {
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'V5-minimal-inference'
            status  = 'fail'
            message = $_.Exception.Message
        }
    }
}

function Add-VerifyCheck {
    param(
        [object]$Result,
        [hashtable]$Check
    )
    # Reassign so updates persist on [ordered]@{} result objects (not only plain hashtables).
    $Result.checks = @($Result.checks) + @($Check)
}

function Get-SkillCheckRegistryPath {
    $agentSkillsRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    return Join-Path $agentSkillsRoot 'schemas\check-registry.json'
}

function Get-SkillCheckStatus {
    param(
        [object]$Result,
        [string]$CheckId
    )
    if (-not $Result -or -not $CheckId) { return $null }
    $c = @($Result.checks | Where-Object { $_.id -eq $CheckId } | Select-Object -First 1)
    if ($c) { return [string]$c.status }
    return $null
}

function New-IntelDevKitInstallPollAction {
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId
    )
    return @{
        skill_id          = 'intel-devkit-install'
        action            = 'poll_install_job'
        install_job_id    = $JobId
        parameters        = @{
            WaitInstallJob = $true
            InstallJobId   = $JobId
        }
        script_invocation = ".\scripts\windows\invoke-devkit-install.ps1 -WaitInstallJob -InstallJobId $JobId"
    }
}

function Set-IntelDevKitInstallJobPollFields {
    param(
        [object]$Result,
        [Parameter(Mandatory = $true)]
        [string]$JobId
    )
    $poll = New-IntelDevKitInstallPollAction -JobId $JobId
    $Result | Add-Member -NotePropertyName install_poll -NotePropertyValue $poll -Force
}

function Test-DevKitVerifyOvmsOnlyFailures {
    param([object]$Result)
    $ovmsCheckIds = @(
        'V4-ovms-installed'
        'V4-ovms-model'
        'V4-agent-model-on-disk'
        'V4-ovms-running'
        'V5-minimal-inference'
        'V6-agentic-inference'
    )
    $fails = @($Result.checks | Where-Object { $_.status -eq 'fail' })
    if ($fails.Count -eq 0) { return $false }
    if ((Get-SkillCheckStatus -Result $Result -CheckId 'V3-openvino-genai') -ne 'pass') { return $false }
    $nonOvms = @($fails | Where-Object { $ovmsCheckIds -notcontains $_.id })
    return ($nonOvms.Count -eq 0)
}

function Resolve-IntelDevkitVerifyNextSkill {
    param([object]$Result)
    $devkit = [string](Get-ResultProperty -Result $Result -Name 'devkit_status')
    if ($devkit -eq 'absent') { return 'intel-devkit-install' }

    $v3 = Get-SkillCheckStatus -Result $Result -CheckId 'V3-openvino-genai'
    if ($v3 -eq 'fail' -or $v3 -eq 'skip') { return 'intel-devkit-install' }

    $v4Installed = Get-SkillCheckStatus -Result $Result -CheckId 'V4-ovms-installed'
    if ($v4Installed -eq 'fail' -or $v4Installed -eq 'skip') {
        $installRoot = [string](Get-ResultProperty -Result $Result -Name 'devkit_install_root')
        if ($installRoot -and (Test-Path -LiteralPath $installRoot)) {
            if (Get-DevKitOvmsAgenticScriptPath -InstallRoot $installRoot) {
                return 'intel-ovms-agentic-setup'
            }
            return 'intel-devkit-ovms-slice-fetch'
        }
        if (Find-DevKitOvmsAgenticScript -InstallRoot $null) {
            return 'intel-ovms-agentic-setup'
        }
        return 'intel-devkit-install'
    }
    if ($v4Installed -ne 'pass') { return 'intel-devkit-install' }

    $v4Running = Get-SkillCheckStatus -Result $Result -CheckId 'V4-ovms-running'
    if ($v4Running -ne 'pass') { return 'intel-ovms-agentic-setup' }

    $v6 = Get-SkillCheckStatus -Result $Result -CheckId 'V6-agentic-inference'
    if ($v6 -eq 'fail') { return 'intel-ovms-agentic-setup' }

    return $null
}

function Set-IntelAgentProviderConfigNextSkillIfReady {
    param([object]$Result)
    if ([string](Get-ResultProperty -Result $Result -Name 'next_skill')) { return }
    $agentReady = Get-ResultProperty -Result $Result -Name 'agent_inference_ready'
    if ($agentReady -ne $true) { return }
    $status = [string]$Result.functional_status
    if ($status -ne 'pass') { return }
    $Result | Add-Member -NotePropertyName next_skill -NotePropertyValue 'intel-agent-provider-config' -Force
}

function Get-SkillCheckRegistry {
    if ($null -ne $script:SkillCheckRegistry) { return $script:SkillCheckRegistry }
    $path = Get-SkillCheckRegistryPath
    if (-not (Test-Path -LiteralPath $path)) {
        $script:SkillCheckRegistry = @{ skills = @{}; checks = @{}; error_codes = @{}; next_skill_steps = @{} }
        return $script:SkillCheckRegistry
    }
    $script:SkillCheckRegistry = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    return $script:SkillCheckRegistry
}

function Test-SkillWarningIsImplementerNote {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $patterns = @(
        'Never call ovms_agentic_setup',
        'MVP stub',
        'invoke \(detached',
        'ovms_pull_state=',
        'catalog pull id',
        'Provider switch is manual',
        'Never pass -CacheDir',
        'ovms_launch_uses_relative',
        'O6-teardown',
        'Rollback: restore previous config',
        'Agent config uses advertised id',
        'regex ',
        'WaitInstallJob',
        'poll with -WaitInstallJob',
        'poll again with -WaitInstallJob',
        'next_poll_command',
        'terminal\.timeout for poll',
        'Install running in elevated window',
        'Waiting for UAC; poll',
        'Setup_1\.ps1 may take',
        'Setup_2\.ps1 downloads',
        'OVMS is not installed by Setup'
    )
    foreach ($p in $patterns) {
        if ($Text -match $p) { return $true }
    }
    return $false
}

function Get-ResultProperty {
    param(
        [object]$Result,
        [string]$Name
    )
    if ($null -eq $Result) { return $null }
    if ($Result -is [System.Collections.IDictionary]) {
        if ($Result.Contains($Name)) { return $Result[$Name] }
        return $null
    }
    if ($Result.PSObject.Properties.Name -contains $Name) { return $Result.$Name }
    return $null
}

function Get-SkillMilestoneRefsFromResult {
    param([object]$Result)
    $refs = [System.Collections.Generic.List[string]]::new()
    $catalog = [string](Get-ResultProperty -Result $Result -Name 'catalog_model_id')
    if ([string]::IsNullOrWhiteSpace($catalog)) {
        $catalog = [string](Get-ResultProperty -Result $Result -Name 'agent_model')
    }
    if ([string]::IsNullOrWhiteSpace($catalog)) {
        $m = [string](Get-ResultProperty -Result $Result -Name 'model')
        if ($m -match 'OpenVINO/') { $catalog = $m }
    }
    if ($catalog -match '0\.8B') { $refs.Add('D1') }
    if ($catalog -match '35B-A3B') { $refs.Add('D9') }
    return @($refs | Select-Object -Unique)
}

function Get-CheckUserLine {
    param(
        [string]$CheckId,
        [string]$Status
    )
    $reg = Get-SkillCheckRegistry
    if (-not $reg.checks.PSObject.Properties[$CheckId]) { return $null }
    $entry = $reg.checks.$CheckId
    $key = switch ($Status) {
        'pass' { 'user_pass' }
        'fail' { 'user_fail' }
        'skip' { 'user_skip' }
        default { 'user_fail' }
    }
    if ($entry.PSObject.Properties[$key]) { return [string]$entry.$key }
    if ($Status -eq 'skip' -and $entry.PSObject.Properties['user_pass']) { return [string]$entry.user_pass }
    return $null
}

function Build-SkillUserPresentation {
    param([object]$Result)

    $reg = Get-SkillCheckRegistry
    $status = [string]$Result.functional_status
    if ([string]::IsNullOrWhiteSpace($status)) { $status = 'fail' }

    $skillId = [string](Get-ResultProperty -Result $Result -Name 'skill_id')
    $skillBlock = $null
    if ($skillId -and $reg.skills.PSObject.Properties[$skillId]) {
        $skillBlock = $reg.skills.$skillId
    }
    $summary = "Skill $skillId finished with status $status."
    $userMessage = $summary
    $modelProfile = [string](Get-ResultProperty -Result $Result -Name 'model_profile')
    $agentReady = Get-ResultProperty -Result $Result -Name 'agent_inference_ready'
    $smokeReady = Get-ResultProperty -Result $Result -Name 'smoke_inference_ready'

    if ($skillBlock -and $skillBlock.PSObject.Properties[$status]) {
        $block = $skillBlock.$status
        if ($block.summary) { $summary = [string]$block.summary }
        if ($block.user_message) { $userMessage = [string]$block.user_message }
    }
    $nextSkillForPresentation = [string](Get-ResultProperty -Result $Result -Name 'next_skill')
    $v3Verify = Get-SkillCheckStatus -Result $Result -CheckId 'V3-openvino-genai'
    $v4InstalledVerify = Get-SkillCheckStatus -Result $Result -CheckId 'V4-ovms-installed'
    $verifyPostDevkitOvmsGap = (
        $skillId -eq 'intel-devkit-verify' -and
        $v3Verify -eq 'pass' -and
        $v4InstalledVerify -eq 'fail' -and
        $nextSkillForPresentation -in @('intel-ovms-agentic-setup', 'intel-devkit-ovms-slice-fetch')
    )
    if ($skillId -eq 'intel-devkit-verify' -and $nextSkillForPresentation -eq 'intel-devkit-install' -and
        ($v3Verify -eq 'fail' -or $v3Verify -eq 'skip') -and
        $skillBlock -and $skillBlock.PSObject.Properties['partial_needs_install']) {
        $block = $skillBlock.partial_needs_install
        if ($block.summary) { $summary = [string]$block.summary }
        if ($block.user_message) { $userMessage = [string]$block.user_message }
    }
    $installJobObj = Get-ResultProperty -Result $Result -Name 'install_job'
    $installJobPhase = $null
    if ($installJobObj -and $installJobObj.phase) { $installJobPhase = [string]$installJobObj.phase }
    $installJobInProgress = ($skillId -eq 'intel-devkit-install' -and $status -eq 'partial' -and $installJobObj -and $installJobPhase -in @('running', 'awaiting_uac'))
    if ($installJobInProgress -and $skillBlock -and $skillBlock.PSObject.Properties['partial_job_running']) {
        $block = $skillBlock.partial_job_running
        if ($block.summary) { $summary = [string]$block.summary }
        if ($block.user_message) { $userMessage = [string]$block.user_message }
    }
    if ($skillId -eq 'intel-ovms-agentic-setup' -and $skillBlock) {
        if ($status -eq 'partial' -and $skillBlock.PSObject.Properties['partial_smoke_only']) {
            $block = $skillBlock.partial_smoke_only
            if ($block.summary) { $summary = [string]$block.summary }
            if ($block.user_message) { $userMessage = [string]$block.user_message }
        } elseif ($status -eq 'pass' -and $modelProfile -eq 'agent' -and $skillBlock.PSObject.Properties['pass_agent']) {
            $block = $skillBlock.pass_agent
            if ($block.summary) { $summary = [string]$block.summary }
            if ($block.user_message) { $userMessage = [string]$block.user_message }
        } elseif ($status -eq 'pass' -and $modelProfile -eq 'verify' -and $skillBlock.PSObject.Properties['pass_verify']) {
            $block = $skillBlock.pass_verify
            if ($block.summary) { $summary = [string]$block.summary }
            if ($block.user_message) { $userMessage = [string]$block.user_message }
        }
    }

    foreach ($agenticCheckId in @('A1-agentic-inference', 'V6-agentic-inference')) {
        $ac = @($Result.checks | Where-Object { $_.id -eq $agenticCheckId } | Select-Object -First 1)
        if ($ac -and $ac.status -eq 'fail') {
            $line = Get-CheckUserLine -CheckId $agenticCheckId -Status 'fail'
            if ($line) {
                $userMessage = $line
                $summary = $line
            }
        }
    }

    $failedUserLines = @()
    foreach ($c in @($Result.checks)) {
        if ($c.status -eq 'fail') {
            $line = Get-CheckUserLine -CheckId $c.id -Status 'fail'
            if ($line) { $failedUserLines += $line }
        }
    }
    if ($failedUserLines.Count -gt 0 -and -not $installJobInProgress -and -not $verifyPostDevkitOvmsGap) {
        $userMessage = ($failedUserLines | Select-Object -Unique) -join ' '
    }
    if ($verifyPostDevkitOvmsGap -and $skillBlock -and $skillBlock.PSObject.Properties['partial_needs_ovms']) {
        $block = $skillBlock.partial_needs_ovms
        if ($block.summary) { $summary = [string]$block.summary }
        if ($block.user_message) { $userMessage = [string]$block.user_message }
    }
    $verifyAgentHandoff = (
        $skillId -eq 'intel-devkit-verify' -and
        $status -eq 'pass' -and
        $agentReady -eq $true -and
        $nextSkillForPresentation -eq 'intel-agent-provider-config'
    )
    if ($verifyAgentHandoff -and $skillBlock -and $skillBlock.PSObject.Properties['pass_agent_handoff']) {
        $block = $skillBlock.pass_agent_handoff
        if ($block.summary) { $summary = [string]$block.summary }
        if ($block.user_message) { $userMessage = [string]$block.user_message }
    }

    $agentSteps = [System.Collections.Generic.List[string]]::new()
    if ($installJobInProgress -and $skillBlock -and $skillBlock.PSObject.Properties['partial_job_running']) {
        $block = $skillBlock.partial_job_running
        if ($block.next_steps) {
            foreach ($s in @($block.next_steps)) {
                if ($s) { $agentSteps.Add([string]$s) }
            }
        }
    }
    $errCode = $null
    $errorObj = Get-ResultProperty -Result $Result -Name 'error'
    if ($errorObj -and $errorObj.code) {
        $errCode = [string]$errorObj.code
        if ($reg.error_codes.PSObject.Properties[$errCode]) {
            $ec = $reg.error_codes.$errCode
            if ($ec.user_message) { $userMessage = [string]$ec.user_message }
            if ($ec.next_steps) {
                foreach ($s in @($ec.next_steps)) { if ($s) { $agentSteps.Add([string]$s) } }
            }
        }
    }
    $nextSkill = Get-ResultProperty -Result $Result -Name 'next_skill'
    if ($nextSkill -and -not $installJobInProgress) {
        $ns = [string]$nextSkill
        $stepKey = $ns
        if ($skillId -eq 'intel-devkit-verify' -and $ns -eq 'intel-ovms-agentic-setup' -and (Get-SkillCheckStatus -Result $Result -CheckId 'V6-agentic-inference') -eq 'fail') {
            $stepKey = 'intel-ovms-agentic-setup-agent-profile'
        }
        if ($reg.next_skill_steps.PSObject.Properties[$stepKey]) {
            foreach ($s in @($reg.next_skill_steps.$stepKey)) { if ($s) { $agentSteps.Add([string]$s) } }
        } elseif ($reg.next_skill_steps.PSObject.Properties[$ns]) {
            foreach ($s in @($reg.next_skill_steps.$ns)) { if ($s) { $agentSteps.Add([string]$s) } }
        } else {
            $agentSteps.Add("Invoke the $ns skill with user approval when required.")
        }
        if ($skillId -eq 'intel-devkit-verify' -and $ns -eq 'intel-devkit-install') {
            $agentSteps.Insert(0, "Invoke the $ns skill next (Hermes: run that skill; do not give the user a raw .ps1 command).")
        }
    }
    $handoff = Get-ResultProperty -Result $Result -Name 'local_provider_handoff'
    if ($handoff -and $handoff.hermes_cli_steps) {
        foreach ($s in @($handoff.hermes_cli_steps)) {
            if ($s -and ($s -notmatch 'intel-ovms|O2/O4|catalog')) { $agentSteps.Add([string]$s) }
        }
    }
    if ($status -eq 'pass' -and $skillId -eq 'intel-agent-provider-config' -and $agentSteps.Count -eq 0) {
        $agentSteps.Add('Apply the staged Hermes config or use hermes model with the local endpoint and the model name from your server.')
    }
    $ovmsInstalledForAgent = (Get-SkillCheckStatus -Result $Result -CheckId 'V4-ovms-installed') -eq 'pass'
    if ($agentReady -eq $false -and $smokeReady -eq $true -and $ovmsInstalledForAgent -and [string]::IsNullOrWhiteSpace($nextSkillForPresentation)) {
        if ($reg.next_skill_steps.PSObject.Properties['intel-ovms-agentic-setup-agent-profile']) {
            foreach ($s in @($reg.next_skill_steps.'intel-ovms-agentic-setup-agent-profile')) {
                if ($s) { $agentSteps.Add([string]$s) }
            }
        } else {
            $agentSteps.Add('Invoke intel-ovms-agentic-setup with -Approve -Profile agent to load the large agent model.')
        }
    }
    if ($agentReady -eq $false -and $skillId -eq 'intel-agent-provider-config') {
        $userMessage = 'The large agent model is not running yet.'
        $summary = $userMessage
    }
    if ($skillId -eq 'openvino-coding-assistant' -and $status -eq 'pass') {
        $serving = [string](Get-ResultProperty -Result $Result -Name 'serving_model')
        if (-not [string]::IsNullOrWhiteSpace($serving)) {
            $summary = "Continue config is ready for $serving on OVMS."
            $userMessage = "Continue is ready. Select OVMS $serving. It is not the automatic default."
        }
    }

    $blockedReason = $null
    if ($status -in @('blocked', 'fail')) {
        $blockedReason = $userMessage
        if ($errorObj -and $errorObj.message) {
            $blockedReason = [string]$errorObj.message
            if ($errCode -and $reg.error_codes.PSObject.Properties[$errCode] -and $reg.error_codes.$errCode.user_message) {
                $blockedReason = [string]$reg.error_codes.$errCode.user_message
            }
        }
    }

    return @{
        summary          = $summary
        user_message     = $userMessage
        next_steps       = @()
        agent_next_steps = @($agentSteps | Select-Object -Unique)
        blocked_reason   = $blockedReason
    }
}

function Finalize-SkillResultForOutput {
    param([object]$Result)

    $userWarnings = [System.Collections.Generic.List[string]]::new()
    $diagNotes = [System.Collections.Generic.List[string]]::new()
    foreach ($w in @($Result.warnings)) {
        if (Test-SkillWarningIsImplementerNote -Text $w) {
            $diagNotes.Add($w)
        } else {
            $userWarnings.Add($w)
        }
    }
    $Result.warnings = @($userWarnings)

    $errorObj = Get-ResultProperty -Result $Result -Name 'error'
    $diag = [ordered]@{
        checks = @($Result.checks)
        notes  = @($diagNotes)
    }
    if ($errorObj) { $diag.error = $errorObj }
    foreach ($name in @(
            'catalog_model_id', 'advertised_model_ids', 'advertised_match_pattern',
            'model_id_source', 'ovms_advertised_match_pattern', 'ovms_pull_state_path',
            'ovms_skill_state_dir', 'devkit_discovery', 'ovms_script_discovery',
            'agent_inference_ready', 'smoke_inference_ready', 'readiness_tier',
            'model_profile', 'agent_serving_model', 'smoke_serving_model',
            'install_job', 'install_poll', 'next_poll_command'
        )) {
        $val = Get-ResultProperty -Result $Result -Name $name
        if ($null -ne $val) { $diag[$name] = $val }
    }
    if ($Result.PSObject.Properties['next_poll_command']) {
        $Result.PSObject.Properties.Remove('next_poll_command')
    }
    $milestones = Get-SkillMilestoneRefsFromResult -Result $Result
    if ($milestones.Count -gt 0) { $diag.milestone_refs = $milestones }

    $presentation = Build-SkillUserPresentation -Result $Result
    $Result.summary = $presentation.summary
    $Result.user_message = $presentation.user_message
    $Result.next_steps = @()
    if ($presentation.agent_next_steps -and @($presentation.agent_next_steps).Count -gt 0) {
        $diag.agent_next_steps = @($presentation.agent_next_steps)
    }
    if ($presentation.blocked_reason) { $Result.blocked_reason = $presentation.blocked_reason }
    $Result.diagnostics = $diag
}

function Write-SkillResult {
    param(
        [object]$Result,
        [switch]$ValidateSchema
    )
    $Result.finished_at = (Get-Date).ToUniversalTime().ToString('o')
    if (-not $Result.overall_status) {
        $Result.overall_status = $Result.functional_status
    }
    Finalize-SkillResultForOutput -Result $Result
    $json = $Result | ConvertTo-Json -Depth 12 -Compress:$false
    if ($ValidateSchema) {
        # TODO: invoke schema validator (P1); D8 allows warn-only
    }
    Write-Output $json
    if ($Result.exit_code -ne 0) { exit $Result.exit_code }
    exit 0
}

function Test-ApprovalRequired {
    param(
        [string]$RiskClass,
        [switch]$Approve
    )
    if ($RiskClass -eq 'read') { return $true }
    return [bool]$Approve
}

function Get-DevKitInstallRootCandidatePaths {
    $list = @()

    # 1) Environment override (highest priority)
    if ($env:AIPC_DEVKIT_INSTALL_ROOT) {
        $list += $env:AIPC_DEVKIT_INSTALL_ROOT.TrimEnd('\', '/')
    }

    # 2) C:\Intel layout
    $list += @(
        'C:\Intel\training.developer.aipc',
        'C:\Intel\aipc-devkit-install',
        'C:\Intel\AI_PC_Developer_Kit',
        'C:\Intel\DevKit',
        'C:\Intel\developer.aipc'
    )
    if (Test-Path 'C:\Intel') {
        Get-ChildItem -Path 'C:\Intel' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $list += $_.FullName
        }
    }

    # 3) First-match: script walk, then other known clone locations
    $fromScript = Find-DevKitInstallRootFromScript
    if ($fromScript) { $list += $fromScript }
    $list += @(
        "$env:USERPROFILE\source\aipc-devkit-install",
        "$env:USERPROFILE\source\training.developer.aipc",
        "$env:USERPROFILE\source\devkit4.0",
        "$env:USERPROFILE\aipc-devkit-install",
        "$env:USERPROFILE\training.developer.aipc"
    )
    $downloads = Join-Path $env:USERPROFILE 'Downloads'
    if (Test-Path -LiteralPath $downloads) {
        Get-ChildItem -Path $downloads -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'aipc-devkit-install*' -or $_.Name -like '*developer*aipc*' } |
            ForEach-Object {
                $list += $_.FullName
                $nested = Join-Path $_.FullName $_.Name
                if (Test-Path -LiteralPath $nested) { $list += $nested }
            }
    }

    return @($list | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)
}

function Get-OvmsSearchPathsFromEnvironment {
    $paths = @()
    if ($env:AIPC_OVMS_ROOT) {
        $ovmsRoot = $env:AIPC_OVMS_ROOT.TrimEnd('\', '/')
        if (Test-Path -LiteralPath $ovmsRoot) {
            $paths += $ovmsRoot
            $paths += Join-Path $ovmsRoot 'ovms'
        }
    }
    if ($env:AIPC_DEVKIT_INSTALL_ROOT) {
        $installRoot = $env:AIPC_DEVKIT_INSTALL_ROOT.TrimEnd('\', '/')
        if (Test-Path -LiteralPath $installRoot) {
            $paths += Join-Path $installRoot 'OVMS'
            $paths += Join-Path $installRoot 'OVMS\ovms'
            $paths += Join-Path $installRoot 'Windows_Software_Installation\OVMS'
        }
    }
    return @($paths | Select-Object -Unique)
}

function Get-OvmsSearchPathsUnderCIntel {
    return @(
        'C:\Intel\OVMS'
        'C:\Intel\OVMS\ovms'
    )
}

function Resolve-DevKitInstallRootFromApplicationsJson {
    param([Parameter(Mandatory = $true)][string]$ApplicationsJsonPath)
    $wingetDir = Split-Path -Path $ApplicationsJsonPath -Parent
    $wsiDir = Split-Path -Path $wingetDir -Parent
    if ((Split-Path -Leaf $wsiDir) -ne 'Windows_Software_Installation') { return $null }
    return Split-Path -Path $wsiDir -Parent
}

function Resolve-DevKitInstallRootFromOvmsAgenticScript {
    param([Parameter(Mandatory = $true)][string]$ScriptPath)
    $normalized = $ScriptPath -replace '/', '\'
    $needle = '\Windows_Software_Installation\OVMS\'
    $idx = $normalized.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase)
    if ($idx -gt 0) {
        return $normalized.Substring(0, $idx)
    }
    return $null
}

function Get-DevKitApplicationsJsonSearchPaths {
    $paths = @()
    foreach ($root in (Get-DevKitInstallRootCandidatePaths)) {
        $paths += Join-Path $root 'Windows_Software_Installation\WingetGUI_Installer\JSON\install\applications.json'
        $paths += Join-Path $root 'Windows_Software_Installation\WingetGUI_Installer\applications.json'
    }
    return @($paths | Select-Object -Unique)
}

function Find-DevKitApplicationsJson {
    foreach ($path in (Get-DevKitApplicationsJsonSearchPaths)) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

function Get-DevKitOvmsAgenticScriptSearchPaths {
    param([string]$InstallRoot = $null)
    $paths = @()

    if ($env:AIPC_DEVKIT_INSTALL_ROOT) {
        $envRoot = $env:AIPC_DEVKIT_INSTALL_ROOT.TrimEnd('\', '/')
        $paths += Join-Path $envRoot 'Windows_Software_Installation\OVMS\ovms_agentic_setup.ps1'
    }
    $paths += @(
        'C:\Intel\Windows_Software_Installation\OVMS\ovms_agentic_setup.ps1'
    )

    if ($InstallRoot) {
        $paths += Join-Path $InstallRoot 'Windows_Software_Installation\OVMS\ovms_agentic_setup.ps1'
    }
    foreach ($root in (Get-DevKitInstallRootCandidatePaths)) {
        $paths += Join-Path $root 'Windows_Software_Installation\OVMS\ovms_agentic_setup.ps1'
    }
    foreach ($ovmsDir in (Get-OvmsSearchPaths -InstallRoot $InstallRoot)) {
        $paths += Join-Path $ovmsDir 'ovms_agentic_setup.ps1'
        $parent = Split-Path $ovmsDir -Parent
        if ($parent) {
            $paths += Join-Path $parent 'ovms_agentic_setup.ps1'
            $paths += Join-Path $parent 'Windows_Software_Installation\OVMS\ovms_agentic_setup.ps1'
        }
    }
    $paths += "$env:ProgramFiles\Intel\Windows_Software_Installation\OVMS\ovms_agentic_setup.ps1"
    return @($paths | Select-Object -Unique)
}

function Find-DevKitOvmsAgenticScript {
    param([string]$InstallRoot = $null)
    foreach ($path in (Get-DevKitOvmsAgenticScriptSearchPaths -InstallRoot $InstallRoot)) {
        if (Test-Path $path) {
            $root = Resolve-DevKitInstallRootFromOvmsAgenticScript -ScriptPath $path
            if (-not $root) {
                $root = Find-DevKitInstallRoot -SkipOvmsScriptSearch
            }
            return @{
                script       = $path
                install_root = $root
                discovery    = 'ovms_agentic_setup.ps1'
            }
        }
    }
    return $null
}

function Get-OvmsExeInstallations {
    param([string]$InstallRoot = $null)
    $installs = @()
    foreach ($dir in (Get-OvmsSearchPaths -InstallRoot $InstallRoot)) {
        $exe = Join-Path $dir 'ovms.exe'
        if (-not (Test-Path $exe)) { continue }
        $item = Get-Item -LiteralPath $exe
        $installs += [ordered]@{
            directory    = $dir
            ovms_exe     = $exe
            file_version = $item.VersionInfo.FileVersion
            last_write   = $item.LastWriteTimeUtc.ToString('o')
        }
    }
    return $installs
}

function Add-OvmsInstallationEvidence {
    param(
        [object]$Result,
        [string]$InstallRoot,
        [string]$Phase
    )
    $installs = Get-OvmsExeInstallations -InstallRoot $InstallRoot
    $prop = "ovms_installations_$Phase"
    $Result | Add-Member -NotePropertyName $prop -NotePropertyValue $installs -Force
    foreach ($inst in $installs) {
        $Result.logs += "OVMS $Phase`: $($inst.ovms_exe) version=$($inst.file_version)"
    }
    if ($installs.Count -gt 1) {
        $Result.warnings += "Multiple ovms.exe copies detected ($Phase): $(($installs | ForEach-Object { $_.ovms_exe }) -join '; ')"
    }
}

function Get-DevKitApplicationsJsonPath {
    param([string]$InstallRoot)
    if (-not $InstallRoot) { return $null }
    foreach ($rel in @(
            'Windows_Software_Installation\WingetGUI_Installer\JSON\install\applications.json',
            'Windows_Software_Installation\WingetGUI_Installer\applications.json'
        )) {
        $candidate = Join-Path $InstallRoot $rel
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

function Get-DevKitInstallLogPath {
    return 'C:\temp\logs\install\install_log.txt'
}

function Get-DevKitUninstallJsonPath {
    param([string]$InstallRoot)
    if (-not $InstallRoot) { return $null }
    foreach ($rel in @(
            'Windows_Software_Installation\WingetGUI_Installer\JSON\uninstall\uninstall.json',
            'Windows_Software_Installation\WingetGUI_Installer\JSON\install\uninstall.json'
        )) {
        $candidate = Join-Path $InstallRoot $rel
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

function Test-DevKitAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DevKitInstallJobRootDirectory {
    $root = 'C:\temp\logs\install\jobs'
    try {
        if (-not (Test-Path -LiteralPath $root)) {
            New-Item -ItemType Directory -Path $root -Force | Out-Null
        }
    } catch { }
    return $root
}

function Get-DevKitInstallJobDirectory {
    param([Parameter(Mandatory = $true)][string]$JobId)
    return Join-Path (Get-DevKitInstallJobRootDirectory) $JobId
}

function Write-DevKitInstallJobProgress {
    param(
        [Parameter(Mandatory = $true)][string]$JobId,
        [Parameter(Mandatory = $true)][ValidateSet('awaiting_uac', 'running', 'completed', 'failed', 'uac_denied')]
        [string]$Phase,
        [string]$Message = '',
        [int]$ProcessId = 0,
        [string]$ResultPath = '',
        [int]$ExitCode = 0
    )
    $jobDir = Get-DevKitInstallJobDirectory -JobId $JobId
    if (-not (Test-Path -LiteralPath $jobDir)) {
        New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
    }
    $now = (Get-Date).ToUniversalTime().ToString('o')
    $progressPath = Join-Path $jobDir 'progress.json'
    $startedAt = $now
    if (Test-Path -LiteralPath $progressPath) {
        try {
            $existing = Get-Content -LiteralPath $progressPath -Raw | ConvertFrom-Json
            if ($existing.started_at) { $startedAt = $existing.started_at }
        } catch { }
    }
    $payload = [ordered]@{
        job_id       = $JobId
        phase        = $Phase
        message      = $Message
        started_at   = $startedAt
        updated_at   = $now
        pid          = $ProcessId
        result_path  = $ResultPath
        exit_code    = $ExitCode
        install_log  = (Get-DevKitInstallLogPath)
    }
    ($payload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $progressPath -Encoding utf8
}

function Save-DevKitInstallJobResult {
    param(
        [Parameter(Mandatory = $true)][string]$JobId,
        [Parameter(Mandatory = $true)][object]$Result
    )
    $jobDir = Get-DevKitInstallJobDirectory -JobId $JobId
    $resultPath = Join-Path $jobDir 'skill-result.json'
    if (-not $Result.finished_at) {
        $Result.finished_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    if (-not $Result.overall_status) {
        $Result.overall_status = $Result.functional_status
    }
    ($Result | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $resultPath -Encoding utf8
    $phase = if ($Result.functional_status -eq 'pass') { 'completed' } else { 'failed' }
    Write-DevKitInstallJobProgress -JobId $JobId -Phase $phase -Message 'Install job finished' `
        -ResultPath $resultPath -ExitCode ([int]$Result.exit_code)
    return $resultPath
}

function Write-DevKitInstallJobManifest {
    param(
        [Parameter(Mandatory = $true)][string]$JobId,
        [Parameter(Mandatory = $true)][string]$InstallerScriptPath,
        [hashtable]$Parameters
    )
    $jobDir = Get-DevKitInstallJobDirectory -JobId $JobId
    if (-not (Test-Path -LiteralPath $jobDir)) {
        New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
    }
    $manifest = [ordered]@{
        job_id                = $JobId
        installer_script_path = $InstallerScriptPath
        created_at            = (Get-Date).ToUniversalTime().ToString('o')
        parameters            = $Parameters
    }
    $manifestPath = Join-Path $jobDir 'manifest.json'
    ($manifest | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $manifestPath -Encoding utf8
    return $manifestPath
}

function Import-DevKitInstallJobParameters {
    param([Parameter(Mandatory = $true)][string]$JobId)
    $manifestPath = Join-Path (Get-DevKitInstallJobDirectory -JobId $JobId) 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Install job manifest not found: $manifestPath"
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $out = @{}
    if ($manifest.parameters) {
        foreach ($prop in $manifest.parameters.PSObject.Properties) {
            $out[$prop.Name] = $prop.Value
        }
    }
    return $out
}

function Get-DevKitInstallJobStatus {
    param([Parameter(Mandatory = $true)][string]$JobId)
    $jobDir = Get-DevKitInstallJobDirectory -JobId $JobId
    if (-not (Test-Path -LiteralPath $jobDir)) {
        return @{
            ok      = $false
            job_id  = $JobId
            phase   = 'unknown'
            message = 'Install job not found'
        }
    }
    $progressPath = Join-Path $jobDir 'progress.json'
    $resultPath = Join-Path $jobDir 'skill-result.json'
    if (-not (Test-Path -LiteralPath $progressPath)) {
        return @{
            ok      = $false
            job_id  = $JobId
            phase   = 'unknown'
            message = 'progress.json missing'
            job_dir = $jobDir
        }
    }
    $progress = Get-Content -LiteralPath $progressPath -Raw | ConvertFrom-Json
    $status = @{
        ok          = $true
        job_id      = $JobId
        job_dir     = $jobDir
        phase       = "$($progress.phase)"
        message     = "$($progress.message)"
        started_at  = "$($progress.started_at)"
        updated_at  = "$($progress.updated_at)"
        pid         = [int]$progress.pid
        result_path = "$($progress.result_path)"
        exit_code   = [int]$progress.exit_code
        install_log = "$($progress.install_log)"
    }
    if (Test-Path -LiteralPath $resultPath) {
        $status.result_ready = $true
    } else {
        $status.result_ready = $false
    }
    $installLog = $status.install_log
    if ($installLog -and (Test-Path -LiteralPath $installLog)) {
        $status.install_log_tail = @(Get-DevKitInstallLogTailLines -InstallLogPath $installLog -LineCount 15)
    }
    if ($status.pid -gt 0) {
        try {
            $proc = Get-Process -Id $status.pid -ErrorAction SilentlyContinue
            $status.process_alive = ($null -ne $proc)
        } catch {
            $status.process_alive = $false
        }
    } else {
        $status.process_alive = $false
    }
    return $status
}

function Start-DevKitInstallElevationJob {
    param(
        [Parameter(Mandatory = $true)][string]$InstallerScriptPath,
        [Parameter(Mandatory = $true)][hashtable]$InvokeParameters,
        [int]$UacAcceptanceSeconds = 90
    )
    $jobId = [guid]::NewGuid().ToString()
    Write-DevKitInstallJobManifest -JobId $jobId -InstallerScriptPath $InstallerScriptPath -Parameters $InvokeParameters
    Write-DevKitInstallJobProgress -JobId $jobId -Phase 'awaiting_uac' `
        -Message 'Waiting for user to approve the Windows UAC elevation prompt'

    $agentSkillsRoot = (Resolve-Path (Join-Path (Split-Path -Parent $InstallerScriptPath) '..\..')).Path
    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $InstallerScriptPath,
        '-ElevatedChild',
        '-Approve',
        '-InstallJobId', $jobId
    )

    $proc = $null
    try {
        $proc = Start-Process -FilePath 'powershell.exe' `
            -Verb RunAs `
            -ArgumentList $argList `
            -WorkingDirectory $agentSkillsRoot `
            -PassThru
    } catch {
        Write-DevKitInstallJobProgress -JobId $jobId -Phase 'uac_denied' -Message $_.Exception.Message -ExitCode 1
        return @{
            ok      = $false
            job_id  = $jobId
            phase   = 'uac_denied'
            message = $_.Exception.Message
        }
    }

    if (-not $proc) {
        Write-DevKitInstallJobProgress -JobId $jobId -Phase 'uac_denied' -Message 'Elevation was not started (user may have declined UAC)' -ExitCode 1
        return @{
            ok      = $false
            job_id  = $jobId
            phase   = 'uac_denied'
            message = 'Elevation was not started (user may have declined UAC)'
        }
    }

    Write-DevKitInstallJobProgress -JobId $jobId -Phase 'awaiting_uac' `
        -Message 'UAC prompt shown; waiting for elevated install window' -ProcessId $proc.Id

    $deadline = (Get-Date).AddSeconds($UacAcceptanceSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 400
        $st = Get-DevKitInstallJobStatus -JobId $jobId
        if ($st.phase -eq 'running' -or $st.phase -eq 'completed' -or $st.phase -eq 'failed') {
            return @{
                ok      = $true
                job_id  = $jobId
                phase   = $st.phase
                pid     = $proc.Id
                message = $st.message
            }
        }
        if ($proc.HasExited) {
            $st2 = Get-DevKitInstallJobStatus -JobId $jobId
            if ($st2.phase -ne 'running' -and $st2.phase -ne 'completed') {
                Write-DevKitInstallJobProgress -JobId $jobId -Phase 'uac_denied' `
                    -Message 'Elevated process exited before install started (UAC declined or launch failed)' -ExitCode 1
                return @{
                    ok      = $false
                    job_id  = $jobId
                    phase   = 'uac_denied'
                    message = 'Elevated process exited before install started (UAC declined or launch failed)'
                }
            }
        }
    }

    return @{
        ok      = $true
        job_id  = $jobId
        phase   = 'awaiting_uac'
        pid     = $proc.Id
        message = 'Install job started; poll with -WaitInstallJob -InstallJobId'
    }
}

function Write-DevKitInstallJobPollSkillResult {
    param(
        [Parameter(Mandatory = $true)][string]$JobId,
        [object]$Status
    )
    $result = Get-SkillResultSkeleton -SkillId 'intel-devkit-install' -RiskClass 'install' -FunctionalStatus 'partial'
    $result.approval_granted = $true
    $result | Add-Member -NotePropertyName install_job -NotePropertyValue $Status -Force

    $resultPath = Join-Path (Get-DevKitInstallJobDirectory -JobId $JobId) 'skill-result.json'
    if ($Status.result_ready -and (Test-Path -LiteralPath $resultPath)) {
        $finalJson = Get-Content -LiteralPath $resultPath -Raw
        Write-Output $finalJson
        try {
            $final = $finalJson | ConvertFrom-Json
            if ($final.exit_code -ne 0) { exit [int]$final.exit_code }
        } catch { }
        exit 0
    }

    if ($Status.phase -eq 'uac_denied') {
        $result.functional_status = 'blocked'
        $result.overall_status = 'blocked'
        $result.exit_code = 2
        $result.error = @{
            code        = 'UAC_DENIED'
            message     = $Status.message
            remediation = 'User must click Yes on the Windows UAC prompt when the agent starts elevation, then re-run with -Approve -Elevate'
        }
    } elseif ($Status.phase -eq 'completed') {
        $result.functional_status = 'pass'
        $result.overall_status = 'pass'
        $result.exit_code = 0
    } elseif ($Status.phase -eq 'failed') {
        $result.functional_status = 'fail'
        $result.overall_status = 'fail'
        $result.exit_code = 1
    } else {
        $result.functional_status = 'partial'
        $result.overall_status = 'partial'
        $result.exit_code = 0
        $result.warnings += 'Install still running; poll again with -WaitInstallJob -InstallJobId ' + $JobId
        $result.warnings += 'Hermes: increase terminal.timeout for poll commands only; install runs in a separate elevated window (hours)'
    }

    Set-IntelDevKitInstallJobPollFields -Result $result -JobId $JobId

    Write-SkillResult -Result $result
}

function Test-DevKitInstallNetwork {
    try {
        $null = Test-NetConnection -ComputerName 'www.microsoft.com' -Port 443 -WarningAction SilentlyContinue -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Get-DevKitFreeDiskSpaceGb {
    param([string]$Path = (Get-Location).Path)
    if (-not $Path) { return $null }
    $driveName = $Path.Substring(0, 1)
    $drive = Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue
    if (-not $drive) { return $null }
    return [math]::Round($drive.Free / 1GB, 2)
}

function Invoke-DevKitSetup1 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SetupScriptPath,
        [ValidateSet('install', 'gui', 'uninstall')]
        [string]$Command = 'install',
        [switch]$Silent
    )
    $scriptDir = Split-Path -Path $SetupScriptPath -Parent
    $scriptName = Split-Path -Path $SetupScriptPath -Leaf

    if ($Silent -and $Command -eq 'install') {
        # Child process isolates Setup_1 "exit" from terminating the skill host.
        # Avoid -NonInteractive: Setup_1 bootstraps NuGet/WinGet.Client and may need PackageManagement prompts suppressed via its internal Pre_Req path instead.
        Push-Location $scriptDir
        $stdoutFile = Join-Path $env:TEMP ("devkit-setup1-out-{0}.log" -f [guid]::NewGuid().ToString('N'))
        $stderrFile = Join-Path $env:TEMP ("devkit-setup1-err-{0}.log" -f [guid]::NewGuid().ToString('N'))
        try {
            $argList = @(
                '-NoProfile',
                '-ExecutionPolicy', 'Bypass',
                '-File', ".\$scriptName",
                'install'
            )
            $proc = Start-Process -FilePath 'powershell.exe' `
                -ArgumentList $argList `
                -WorkingDirectory $scriptDir `
                -Wait -PassThru -NoNewWindow `
                -RedirectStandardOutput $stdoutFile `
                -RedirectStandardError $stderrFile
            $output = @()
            foreach ($f in @($stdoutFile, $stderrFile)) {
                if (Test-Path -LiteralPath $f) {
                    $output += Get-Content -LiteralPath $f -ErrorAction SilentlyContinue
                }
            }
            return @{
                exit_code = [int]$proc.ExitCode
                output    = @($output | ForEach-Object { "$_" })
                log_line  = "invoke (child PS): $SetupScriptPath install ExitCode=$($proc.ExitCode)"
                silent    = $true
            }
        } catch {
            return @{
                exit_code = 1
                output    = @($_.Exception.Message)
                log_line  = "invoke (child PS): $SetupScriptPath install failed to start"
                silent    = $true
            }
        } finally {
            Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
            Pop-Location
        }
    }

    $params = @{ command = $Command }
    $run = Invoke-DevKitExternalScript -ScriptPath $SetupScriptPath -BoundParameters $params
    $run.silent = $false
    return $run
}

function Get-DevKitInstallLogTailLines {
    param(
        [string]$InstallLogPath = (Get-DevKitInstallLogPath),
        [int]$LineCount = 30
    )
    if (-not (Test-Path -LiteralPath $InstallLogPath)) { return @() }
    return @(Get-Content -LiteralPath $InstallLogPath -Tail $LineCount -ErrorAction SilentlyContinue)
}

function Get-DevKitSetup1FailureHint {
    param([string[]]$OutputLines)
    $text = ($OutputLines -join "`n")
    if ($text -match 'not digitally signed|cannot run this script on the current system|PSSecurityException|ExecutionPolicy') {
        return 'PowerShell blocked Setup_1 (policy or Mark-of-the-Web). Re-run skill after sync, or Admin PS: Unblock-File on WingetGUI_Installer\*.ps1, or: powershell -ExecutionPolicy Bypass -File .\Setup_1.ps1 install'
    }
    if ($text -match 'Pre-requisites not met') {
        return 'Setup_1 prereq check failed (admin, winget >= 1.10.390, Microsoft.WinGet.Client). Run elevated: winget upgrade winget; Install-Module Microsoft.WinGet.Client -Force -Scope CurrentUser'
    }
    if ($text -match 'JSON file does not exist|Alternative path also not found|Error loading JSON') {
        return 'applications.json missing or invalid under WingetGUI_Installer\JSON\install\ - verify clone path and AIPC_DEVKIT_INSTALL_ROOT'
    }
    if ($text -match 'Eula not accepted') {
        return 'EULA declined (external mode); use internal Setup_1 or accept EULA in GUI mode'
    }
    if ($text -match 'Get-WinGetPackage|Microsoft\.WinGet\.Client') {
        return 'WinGet PowerShell module unavailable; from Admin PS: Install-Module Microsoft.WinGet.Client -Force -Scope CurrentUser, then re-run install'
    }
    if ($text -match 'Failed installations\s+:\s+([1-9]\d*)') {
        return "Setup_1 finished but reported $($Matches[1]) failed winget package(s); see install_log.txt and Failed installations in setup output"
    }
    if ($text -match 'Administrator Required|requires administrator') {
        return 'Setup_1 did not run elevated; re-run invoke-devkit-install from Administrator PowerShell (I1-admin must pass in same session)'
    }
    return $null
}

function Get-DevKitSetupInstallSummaryFromOutput {
    param([string[]]$OutputLines)
    $text = ($OutputLines -join "`n")
    $summary = @{}
    if ($text -match 'Failed installations\s+:\s+(\d+)') {
        $summary['failed_installs'] = [int]$Matches[1]
    }
    if ($text -match 'Successfully installed\s+:\s+(\d+)') {
        $summary['successful_installs'] = [int]$Matches[1]
    }
    if ($text -match 'Already installed/skipped:\s+(\d+)') {
        $summary['already_present'] = [int]$Matches[1]
    }
    return $summary
}

function Get-DevKitSetupScriptPath {
    param([string]$InstallRoot)
    if (-not $InstallRoot) { return $null }
    $setup = Join-Path $InstallRoot 'Windows_Software_Installation\WingetGUI_Installer\Setup_1.ps1'
    if (Test-Path $setup) { return $setup }
    return $null
}

function Get-DevKitSetup2ScriptPath {
    param([string]$InstallRoot)
    if (-not $InstallRoot) { return $null }
    $setup = Join-Path $InstallRoot 'Windows_Software_Installation\WingetGUI_Installer\Setup_2.ps1'
    if (Test-Path $setup) { return $setup }
    return $null
}

function Test-DevKitOpenVinoGenAiReady {
    param([string]$DevKitWorkingDir = 'C:\Intel')
    $genaiRoot = Join-Path $DevKitWorkingDir 'openvino_genai'
    if (-not (Test-Path -LiteralPath $genaiRoot)) {
        return @{ ready = $false; path = $genaiRoot }
    }
    $markers = @(
        (Join-Path $genaiRoot 'setupvars.ps1')
        (Join-Path $genaiRoot 'samples')
    )
    $ready = ($markers | Where-Object { Test-Path -LiteralPath $_ }).Count -gt 0
    return @{ ready = $ready; path = $genaiRoot }
}

function Invoke-DevKitEnsureOpenVinoGenAiMinimal {
    param(
        [string]$DevKitWorkingDir = 'C:\Intel',
        [switch]$RunGenAiDependencies
    )
    $logDir = 'C:\temp\logs\setup2'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    $output = @()
    $genaiUri = 'https://storage.openvinotoolkit.org/repositories/openvino_genai/packages/2026.0/windows/openvino_genai_windows_2026.0.0.0_x86_64.zip'
    $zipName = 'openvino_genai.zip'
    $extractedFolder = 'openvino_genai_windows_2026.0.0.0_x86_64'
    $genaiRoot = Join-Path $DevKitWorkingDir 'openvino_genai'

    $existing = Test-DevKitOpenVinoGenAiReady -DevKitWorkingDir $DevKitWorkingDir
    if ($existing.ready) {
        $output += "openvino_genai already ready at $($existing.path)"
        return @{
            exit_code = 0
            output    = $output
            log_line  = 'invoke (genai-minimal): skipped; tree already satisfies V3'
            mode      = 'genai-minimal-skip'
        }
    }

    if (-not (Test-Path -LiteralPath $DevKitWorkingDir)) {
        New-Item -Path $DevKitWorkingDir -ItemType Directory -Force | Out-Null
    }

    Push-Location $DevKitWorkingDir
    try {
        if (-not (Test-Path -LiteralPath $genaiRoot)) {
            $zipPath = Join-Path $DevKitWorkingDir $zipName
            if (-not (Test-Path -LiteralPath $zipPath)) {
                $output += "Downloading openvino_genai package..."
                Write-Host "Downloading openvino_genai (minimal Setup_2 path)..." -ForegroundColor Cyan
                Invoke-WebRequest -Uri $genaiUri -OutFile $zipPath -UseBasicParsing
            }
            $output += "Extracting $zipName"
            Expand-Archive -Path $zipPath -DestinationPath $DevKitWorkingDir -Force
            Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath (Join-Path $DevKitWorkingDir $extractedFolder)) {
                Rename-Item -LiteralPath (Join-Path $DevKitWorkingDir $extractedFolder) -NewName 'openvino_genai'
            }
        }

        if (-not (Test-Path -LiteralPath $genaiRoot)) {
            return @{
                exit_code = 1
                output    = @($output + "openvino_genai folder missing after extract")
                log_line  = 'invoke (genai-minimal): extract failed'
                mode      = 'genai-minimal'
            }
        }

        if ($RunGenAiDependencies) {
            $dependenciesScript = Join-Path $genaiRoot 'install_dependencies\install_openvino_dependencies.ps1'
            if (Test-Path -LiteralPath $dependenciesScript) {
                $output += "Running install_openvino_dependencies.ps1"
                & $dependenciesScript 2>&1 | ForEach-Object { $output += "$_" }
            } else {
                $output += 'install_openvino_dependencies.ps1 not found; skipped'
            }
        }

        $check = Test-DevKitOpenVinoGenAiReady -DevKitWorkingDir $DevKitWorkingDir
        return @{
            exit_code = $(if ($check.ready) { 0 } else { 1 })
            output    = $output
            log_line  = "invoke (genai-minimal): DevKitWorkingDir=$DevKitWorkingDir ready=$($check.ready)"
            mode      = 'genai-minimal'
        }
    } catch {
        return @{
            exit_code = 1
            output    = @($output + $_.Exception.Message)
            log_line  = 'invoke (genai-minimal): failed'
            mode      = 'genai-minimal'
        }
    } finally {
        Pop-Location
    }
}

function Invoke-DevKitSetup2 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SetupScriptPath,
        [string]$DevKitWorkingDir = 'C:\Intel',
        [switch]$InProcess,
        [switch]$StopWhenGenAiReady,
        [int]$PollIntervalSec = 60
    )
    $scriptDir = Split-Path -Path $SetupScriptPath -Parent
    $scriptName = Split-Path -Path $SetupScriptPath -Leaf
    $logDir = 'C:\temp\logs\setup2'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    $metaLog = Join-Path $logDir 'invoke-meta.txt'

    if ($InProcess) {
        Push-Location $scriptDir
        try {
            $started = (Get-Date).ToString('o')
            @(
                "started=$started"
                "mode=in-process"
                "script=$SetupScriptPath"
                "DevKitWorkingDir=$DevKitWorkingDir"
            ) | Set-Content -LiteralPath $metaLog -Encoding UTF8
            Write-Host "Setup_2 running in this window (InProcess). Can take several hours (pip/CMake/LlamaCpp)." -ForegroundColor Yellow
            $output = & ".\$scriptName" -DevKitWorkingDir $DevKitWorkingDir 2>&1
            $exit = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
            return @{
                exit_code = $exit
                output    = @($output | ForEach-Object { "$_" })
                log_line  = "invoke (in-process): $SetupScriptPath -DevKitWorkingDir $DevKitWorkingDir ExitCode=$exit"
                meta_log  = $metaLog
            }
        } catch {
            return @{
                exit_code = 1
                output    = @($_.Exception.Message)
                log_line  = "invoke (in-process): $SetupScriptPath failed"
                meta_log  = $metaLog
            }
        } finally {
            Pop-Location
        }
    }

    Push-Location $scriptDir
    $stdoutFile = Join-Path $logDir 'setup2-child-stdout.log'
    $stderrFile = Join-Path $logDir 'setup2-child-stderr.log'
    try {
        $started = (Get-Date).ToString('o')
        @(
            "started=$started"
            "mode=child-window"
            "script=$SetupScriptPath"
            "DevKitWorkingDir=$DevKitWorkingDir"
            "stdout=$stdoutFile"
            "stderr=$stderrFile"
        ) | Set-Content -LiteralPath $metaLog -Encoding UTF8

        $argList = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', ".\$scriptName",
            '-DevKitWorkingDir', $DevKitWorkingDir
        )
        Write-Host "Setup_2 started (separate window). Tail logs: $stdoutFile" -ForegroundColor Yellow
        Write-Host "Setup_2 often runs 1-8+ hours (GenAI deps, venvs, LlamaCpp/Vulkan builds). Check Task Manager for cmake, cl, pip, msbuild." -ForegroundColor Yellow
        if ($StopWhenGenAiReady) {
            Write-Host "StopWhenGenAiReady: will stop Setup_2 once openvino_genai satisfies verify V3 (notebooks/LlamaCpp may be skipped)." -ForegroundColor Yellow
        }

        if ($StopWhenGenAiReady) {
            $proc = Start-Process -FilePath 'powershell.exe' `
                -ArgumentList $argList `
                -WorkingDirectory $scriptDir `
                -PassThru
            $truncated = $false
            while (-not $proc.HasExited) {
                Start-Sleep -Seconds $PollIntervalSec
                $ready = Test-DevKitOpenVinoGenAiReady -DevKitWorkingDir $DevKitWorkingDir
                if ($ready.ready) {
                    Write-Host "openvino_genai ready; stopping Setup_2 child (PID $($proc.Id))." -ForegroundColor Yellow
                    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                    $truncated = $true
                    break
                }
            }
            if (-not $proc.HasExited) {
                $proc.WaitForExit()
            }
            $exitCode = if ($truncated) { 0 } else { [int]$proc.ExitCode }
            $output = @()
            if ($truncated) {
                $output += 'Setup_2 stopped after openvino_genai became ready (StopWhenGenAiReady). Full Setup_2 did not run to completion.'
            } else {
                $output += @(
                    'Setup_2 ran in a separate PowerShell window; console output was not captured.'
                    "See $metaLog and monitor C:\Intel\openvino_genai"
                )
            }
            return @{
                exit_code = $exitCode
                output    = $output
                log_line  = "invoke (child window, StopWhenGenAiReady=$truncated): ExitCode=$exitCode"
                meta_log  = $metaLog
                truncated = $truncated
            }
        }

        # No stdout/stderr redirect: native builds (CMake, MSBuild, pip) can hang when the parent PS stream is redirected.
        $proc = Start-Process -FilePath 'powershell.exe' `
            -ArgumentList $argList `
            -WorkingDirectory $scriptDir `
            -Wait -PassThru

        $output = @()
        if (Test-Path -LiteralPath $stdoutFile) {
            $output += Get-Content -LiteralPath $stdoutFile -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $stderrFile) {
            $output += Get-Content -LiteralPath $stderrFile -ErrorAction SilentlyContinue
        }
        if ($output.Count -eq 0) {
            $output += @(
                'Setup_2 ran in a separate PowerShell window; console output was not captured.'
                "See $metaLog and monitor C:\Intel\openvino_genai"
            )
        }
        return @{
            exit_code = [int]$proc.ExitCode
            output    = @($output | ForEach-Object { "$_" })
            log_line  = "invoke (child window): $SetupScriptPath -DevKitWorkingDir $DevKitWorkingDir ExitCode=$($proc.ExitCode)"
            meta_log  = $metaLog
        }
    } catch {
        return @{
            exit_code = 1
            output    = @($_.Exception.Message)
            log_line  = "invoke (child window): $SetupScriptPath failed to start"
            meta_log  = $metaLog
        }
    } finally {
        Pop-Location
    }
}

function Test-DevKitInstallerRepoRoot {
    param([string]$Path)
    return [bool](Get-DevKitSetupScriptPath -InstallRoot $Path)
}

function Find-DevKitInstallRootFromScript {
    param([string]$StartDir = $PSScriptRoot)
    $dir = $StartDir
    while ($dir) {
        if (Test-DevKitInstallerRepoRoot -Path $dir) {
            return $dir
        }
        $parent = Split-Path -Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

function Find-DevKitInstallRoot {
    param([switch]$SkipOvmsScriptSearch)

    foreach ($p in (Get-DevKitInstallRootCandidatePaths)) {
        if (Test-DevKitInstallerRepoRoot -Path $p) { return $p }
    }

    $appsJson = Find-DevKitApplicationsJson
    if ($appsJson) {
        $root = Resolve-DevKitInstallRootFromApplicationsJson -ApplicationsJsonPath $appsJson
        if ($root -and (Test-Path $root)) { return $root }
    }

    if (-not $SkipOvmsScriptSearch) {
        $ovms = Find-DevKitOvmsAgenticScript -InstallRoot $null
        if ($ovms -and $ovms.install_root -and (Test-Path $ovms.install_root)) {
            return $ovms.install_root
        }
    }

    return $null
}

function Get-DevKitOvmsAgenticScriptPath {
    param([string]$InstallRoot)
    if (-not $InstallRoot) { return $null }
    $script = Join-Path $InstallRoot 'Windows_Software_Installation\OVMS\ovms_agentic_setup.ps1'
    if (Test-Path $script) { return $script }
    return $null
}

function Get-DevKitStatus {
    param(
        [string]$InstallRoot,
        [switch]$LocalOnly
    )
    $tracker = Get-DevKitApplicationsJsonPath -InstallRoot $InstallRoot
    if (-not $tracker -and -not $LocalOnly) {
        $tracker = Find-DevKitApplicationsJson
    }
    if ($tracker -and (Test-Path $tracker)) {
        return @{ status = 'present'; applications_json = $tracker }
    }
    if (Find-OvmsInstallDirectory -InstallRoot $InstallRoot -LocalOnly:$LocalOnly) {
        return @{ status = 'present'; applications_json = $null; evidence = 'ovms.exe in standard path' }
    }
    if (-not $LocalOnly -and (Test-OpenVinoGenAiPresent -InstallRoot $InstallRoot).found) {
        return @{ status = 'partial'; applications_json = $null; evidence = 'openvino_genai without install tracker' }
    }
    if ($InstallRoot -and (Test-Path $InstallRoot)) {
        return @{ status = 'partial'; applications_json = $null }
    }
    return @{ status = 'absent'; applications_json = $null }
}

# MVP defaults (DECISIONS.md D1 verify, D9 agent)
$script:DefaultVerifyModelId = 'OpenVINO/Qwen3.5-0.8B-int4-ov'
$script:DefaultAgentModelId = 'OpenVINO/Qwen3.6-35B-A3B-int4-ov'
$script:DefaultModelId = $script:DefaultVerifyModelId
$script:DefaultOvmsBaseUrl = 'http://localhost:8000/v3'
$script:DefaultOvmsTarget = 'CPU'
$script:DefaultAgentOvmsTarget = 'GPU'

# Continue on port 8000 accepts the model already serving: Qwen3.6 35B or Muse-Glimmer.
# Qwen3.6 remains the download default when neither is advertised.
$script:DefaultCodingCatalogModelId = $script:DefaultAgentModelId
$script:DefaultCodingServingModelId = 'Qwen3.6-35B-A3B'
$script:CodingAcceptedCatalogModelIds = @(
    'OpenVINO/Qwen3.6-35B-A3B-int4-ov',
    'OpenVINO/Muse-Glimmer-30B-int4-ov'
)
$script:DefaultCodingOvmsPort = 8000
$script:DefaultCodingOvmsTarget = 'GPU'
$script:IntelContinueConfigMarker = 'intel-openvino-coding-assistant'

function Resolve-CodingCatalogModelFromEndpoint {
    param(
        [string]$BaseUrl,
        [string]$RequestedCatalogModelId
    )
    $ids = @(Get-OvmsEndpointModelIdsSafe -BaseUrl $BaseUrl)
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($RequestedCatalogModelId)) {
        $candidates = @($RequestedCatalogModelId)
    } else {
        $candidates = @($script:CodingAcceptedCatalogModelIds)
    }
    foreach ($catalog in $candidates) {
        $match = Find-OvmsAdvertisedModelByCatalog -AdvertisedIds $ids -CatalogModelId $catalog
        if ($match.matched) {
            return @{
                catalog_model_id = $catalog
                serving_model    = $match.id
                advertised       = $true
                advertised_ids   = $ids
            }
        }
    }
    $fallback = if (-not [string]::IsNullOrWhiteSpace($RequestedCatalogModelId)) {
        $RequestedCatalogModelId
    } else {
        $script:DefaultCodingCatalogModelId
    }
    return @{
        catalog_model_id = $fallback
        serving_model    = $null
        advertised       = $false
        advertised_ids   = $ids
    }
}

function Get-OvmsModelForProfile {
    param(
        [ValidateSet('verify', 'agent')]
        [string]$Profile = 'verify'
    )
    if ($Profile -eq 'agent') { return $script:DefaultAgentModelId }
    return $script:DefaultVerifyModelId
}

function Get-OvmsTargetForProfile {
    param(
        [ValidateSet('verify', 'agent')]
        [string]$Profile = 'verify'
    )
    if ($Profile -eq 'agent') { return $script:DefaultAgentOvmsTarget }
    return $script:DefaultOvmsTarget
}

function Get-OpenVinoGenAiSearchPaths {
    param([string]$InstallRoot)
    $paths = @(
        'C:\Intel\openvino_genai',
        "$env:USERPROFILE\openvino_genai"
    )
    if ($env:AIPC_DEVKIT_WORKING_DIR) {
        $paths += Join-Path $env:AIPC_DEVKIT_WORKING_DIR.TrimEnd('\', '/') 'openvino_genai'
    }
    if ($InstallRoot) {
        $paths += Join-Path $InstallRoot 'openvino_genai'
    }
    return $paths | Select-Object -Unique
}

function Test-OpenVinoGenAiPresent {
    param([string]$InstallRoot)
    foreach ($p in (Get-OpenVinoGenAiSearchPaths -InstallRoot $InstallRoot)) {
        if (Test-Path $p) {
            return @{ found = $true; path = $p }
        }
    }
    return @{ found = $false; path = $null }
}

function Get-OvmsSearchPaths {
    param(
        [string]$InstallRoot,
        [switch]$LocalOnly
    )
    if ($LocalOnly) {
        if (-not $InstallRoot) { return @() }
        return @(
            Join-Path $InstallRoot 'OVMS'
            Join-Path $InstallRoot 'OVMS\ovms'
            Join-Path $InstallRoot 'Windows_Software_Installation\OVMS'
        ) | Select-Object -Unique
    }

    $paths = @()
    # 1) Environment (AIPC_OVMS_ROOT, then OVMS paths under AIPC_DEVKIT_INSTALL_ROOT)
    $paths += Get-OvmsSearchPathsFromEnvironment
    # 2) C:\Intel
    $paths += Get-OvmsSearchPathsUnderCIntel
    # 3) Explicit InstallRoot parameter (e.g. verify -InstallRoot)
    if ($InstallRoot) {
        $paths += Join-Path $InstallRoot 'OVMS'
        $paths += Join-Path $InstallRoot 'OVMS\ovms'
        $paths += Join-Path $InstallRoot 'Windows_Software_Installation\OVMS'
    }
    # 4) First-match under discovered installer roots, then profile defaults
    foreach ($root in (Get-DevKitInstallRootCandidatePaths)) {
        if ($InstallRoot -and ($root -eq $InstallRoot)) { continue }
        $paths += Join-Path $root 'OVMS'
        $paths += Join-Path $root 'OVMS\ovms'
        $paths += Join-Path $root 'Windows_Software_Installation\OVMS'
    }
    $paths += @(
        "$env:USERPROFILE\OVMS"
        "$env:USERPROFILE\OVMS\ovms"
    )
    return @($paths | Select-Object -Unique)
}

function Find-OvmsInstallDirectory {
    param(
        [string]$InstallRoot,
        [switch]$LocalOnly
    )
    foreach ($p in (Get-OvmsSearchPaths -InstallRoot $InstallRoot -LocalOnly:$LocalOnly)) {
        if (-not $p) { continue }
        $directExe = Join-Path $p 'ovms.exe'
        if (Test-Path -LiteralPath $directExe) {
            return $p
        }
        $nestedExe = Join-Path $p 'ovms\ovms.exe'
        if (Test-Path -LiteralPath $nestedExe) {
            return (Join-Path $p 'ovms')
        }
    }
    return $null
}

function Get-OvmsModelCacheRoot {
    param([string]$OvmsDir)
    if (-not $OvmsDir) { return $null }
    $parent = Split-Path $OvmsDir -Parent
    if (-not $parent) { return $null }
    return Join-Path $parent 'models'
}

function Test-OvmsModelOnDisk {
    param(
        [string]$ModelCacheRoot,
        [string]$ModelId,
        [switch]$Strict
    )
    if (-not $ModelCacheRoot) {
        return @{ found = $false; message = 'Model cache root unknown' }
    }
    $folderName = ($ModelId -split '/')[-1]
    $direct = Join-Path $ModelCacheRoot ($ModelId -replace '/', '\')
    $openVinoDir = Join-Path $ModelCacheRoot 'OpenVINO'
    $named = Join-Path $openVinoDir $folderName
    if (Test-Path $direct) {
        return @{ found = $true; message = "Model found at $direct"; model_id = $ModelId }
    }
    if (Test-Path $named) {
        return @{ found = $true; message = "Model found at $named"; model_id = $ModelId }
    }
    if (-not $Strict) {
        if (Test-Path $openVinoDir) {
            $any = Get-ChildItem $openVinoDir -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($any) {
                return @{
                    found    = $true
                    message  = "Other model on disk: $($any.Name) (expected $folderName)"
                    model_id = $ModelId
                }
            }
        }
    }
    return @{ found = $false; message = "Model not found: $ModelId"; model_id = $ModelId }
}

function Test-DefaultOvmsModelOnDisk {
    param(
        [string]$ModelCacheRoot,
        [string]$ModelId = $script:DefaultVerifyModelId,
        [switch]$Strict
    )
    if (-not $Strict) { $Strict = $true }
    return Test-OvmsModelOnDisk -ModelCacheRoot $ModelCacheRoot -ModelId $ModelId -Strict:$Strict
}

function Add-OvmsVerifyChecks {
    param(
        [object]$Result,
        [string]$InstallRoot
    )
    $ovmsDir = Find-OvmsInstallDirectory -InstallRoot $InstallRoot
    if ($ovmsDir) {
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'V4-ovms-installed'
            status  = 'pass'
            message = "OVMS installed at $ovmsDir"
        }
        $modelRoot = Get-OvmsModelCacheRoot -OvmsDir $ovmsDir
        $verifyModel = $script:DefaultVerifyModelId
        $modelTest = Test-OvmsModelOnDisk -ModelCacheRoot $modelRoot -ModelId $verifyModel -Strict
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'V4-ovms-model'
            status  = $(if ($modelTest.found) { 'pass' } else { 'fail' })
            message = "$($modelTest.message) [verify model D1]"
        }
        $agentTest = Test-OvmsModelOnDisk -ModelCacheRoot $modelRoot -ModelId $script:DefaultAgentModelId -Strict
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'V4-agent-model-on-disk'
            status  = $(if ($agentTest.found) { 'pass' } else { 'skip' })
            message = $(if ($agentTest.found) { $agentTest.message } else { "$($agentTest.message); run configure-hermes-ovms or configure-openclaw-ovms with -Approve -Pull" })
        }
        try {
            $baseUrl = $script:DefaultOvmsBaseUrl
            $null = Invoke-RestMethod -Uri "$baseUrl/models" -TimeoutSec 5
            Add-VerifyCheck -Result $Result -Check @{
                id      = 'V4-ovms-running'
                status  = 'pass'
                message = 'OVMS running - GET /v3/models OK'
            }
            $Result.endpoint = $baseUrl
        } catch {
            Add-VerifyCheck -Result $Result -Check @{
                id      = 'V4-ovms-running'
                status  = 'skip'
                message = 'OVMS not running (not a failure)'
            }
        }
    } else {
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'V4-ovms-installed'
            status  = 'fail'
            message = 'OVMS not installed in standard locations'
        }
        Add-VerifyCheck -Result $Result -Check @{ id = 'V4-ovms-model'; status = 'skip'; message = 'OVMS not installed' }
        Add-VerifyCheck -Result $Result -Check @{ id = 'V4-agent-model-on-disk'; status = 'skip'; message = 'OVMS not installed' }
        Add-VerifyCheck -Result $Result -Check @{ id = 'V4-ovms-running'; status = 'skip'; message = 'OVMS not installed' }
    }
}

function Get-ContinueConfigPath {
    return Join-Path $env:USERPROFILE '.continue\config.yaml'
}

function Test-VscodeContinuePrereq {
    $codeCmd = Get-Command code -ErrorAction SilentlyContinue
    if (-not $codeCmd) {
        return @{
            ok      = $false
            message = 'VS Code CLI (code) not on PATH; Dev Kit install should add Code or use "Shell Command: Install code command in PATH"'
        }
    }
    try {
        $ext = & code --list-extensions 2>&1 | ForEach-Object { "$_" }
        if (@($ext | Where-Object { $_ -match '(?i)^Continue\.continue$' }).Count -gt 0) {
            return @{ ok = $true; message = 'Continue.continue extension listed' }
        }
        return @{
            ok      = $false
            message = 'Continue.continue not in code --list-extensions; install Continue from VS Code marketplace if missing'
        }
    } catch {
        return @{ ok = $false; message = "Could not list VS Code extensions: $($_.Exception.Message)" }
    }
}

function Get-ContinueOvmsCoderModelYamlLines {
    param(
        [string]$ServingModel = $script:DefaultCodingServingModelId,
        [string]$ApiBase = $(Get-OvmsBaseUrl -Port $script:DefaultCodingOvmsPort)
    )
    $displayName = "OVMS $ServingModel"
    return @(
        "  # $($script:IntelContinueConfigMarker)"
        "  - name: $displayName"
        '    provider: openai'
        "    model: $ServingModel"
        '    apiKey: unused'
        "    apiBase: $ApiBase"
        '    roles:'
        '      - chat'
        '      - edit'
        '      - apply'
        '      - autocomplete'
        '    capabilities:'
        '      - tool_use'
        '    requestOptions:'
        '      extraBodyProperties:'
        '        chat_template_kwargs:'
        '          enable_thinking: false'
        '    autocompleteOptions:'
        '      maxPromptTokens: 500'
        '      debounceDelay: 124'
        '      modelTimeout: 400'
        '      onlyMyCode: true'
        '      useCache: true'
    )
}

function New-ContinueConfigScaffold {
    param([string[]]$ModelLines)
    return @(
        'name: Intel AI PC Local Assistant'
        'version: 1.0.0'
        'schema: v1'
        'models:'
    ) + $ModelLines
}

function Merge-ContinueConfigWithOvmsCoder {
    param(
        [string]$ExistingContent,
        [string[]]$ModelLines
    )
    $block = ($ModelLines -join "`n").TrimEnd()
    $marker = $script:IntelContinueConfigMarker
    if ([string]::IsNullOrWhiteSpace($ExistingContent)) {
        return (New-ContinueConfigScaffold -ModelLines $ModelLines) -join "`n"
    }
    $content = $ExistingContent -replace "`r`n", "`n"

    # Continue default config often has `models: []` — a second `models:` block makes the parser keep [] (empty).
    if ($content -match '(?m)^models:\s*\[\s*\]\s*$') {
        $content = [regex]::Replace($content, '(?m)^models:\s*\[\s*\]\s*$', "models:`n$block", 1)
        $content = Remove-ContinueDuplicateEmptyModelsLine -Content $content
        return $content.TrimEnd() + "`n"
    }

    $servingForReplace = $script:DefaultCodingServingModelId
    foreach ($modelLine in @($ModelLines)) {
        if ($modelLine -match '^\s*model:\s*(\S+)\s*$') {
            $servingForReplace = $Matches[1]
            break
        }
    }
    $patternServing = '(?ms)^\s*-\s*name:[^\n]*\n(?:[ \t].*\n)*?[ \t]+model:\s*' + [regex]::Escape($servingForReplace) + '\s*$.*?(?=^\s*-\s*name:|^\s*context:|^[a-zA-Z][\w-]*:\s|\z)'
    if ($content -match $patternServing) {
        $content = [regex]::Replace($content, $patternServing, ($block + "`n"), 1)
        $content = Remove-ContinueDuplicateEmptyModelsLine -Content $content
        return $content.TrimEnd() + "`n"
    }

    if ($content -match '(?ms)^\s*#?\s*' + [regex]::Escape($marker)) {
        $pattern = '(?ms)^\s*#?\s*' + [regex]::Escape($marker) + '.*?^\s*-\s*name:.*?(?=^\s*-\s*name:|^\s*context:|^[a-zA-Z][\w-]*:\s|\z)'
        if ($content -match $pattern) {
            $content = [regex]::Replace($content, $pattern, ($block + "`n"), 1)
            $content = Remove-ContinueDuplicateEmptyModelsLine -Content $content
            return $content.TrimEnd() + "`n"
        }
    }

    # Replace empty `models:` section (no entries yet)
    if ($content -match '(?ms)^models:\s*\n(?=^[a-zA-Z#]|\z)') {
        $content = [regex]::Replace($content, '(?ms)^models:\s*\n', "models:`n$block`n", 1)
        $content = Remove-ContinueDuplicateEmptyModelsLine -Content $content
        return $content.TrimEnd() + "`n"
    }

    # Replace entire models section when we can find a bounded block
    if ($content -match '(?ms)^models:\s*\n') {
        $content = [regex]::Replace($content, '(?ms)^models:\s*\n.*?(?=^[a-zA-Z][\w-]*:\s|\z)', "models:`n$block`n", 1)
        $content = Remove-ContinueDuplicateEmptyModelsLine -Content $content
        return $content.TrimEnd() + "`n"
    }

    $content = ($content.TrimEnd() + "`n`nmodels:`n" + $block + "`n")
    $content = Remove-ContinueDuplicateEmptyModelsLine -Content $content
    return $content.TrimEnd() + "`n"
}

function Remove-ContinueDuplicateEmptyModelsLine {
    param([string]$Content)
    # Drop stray `models: []` left from Continue defaults (duplicate YAML key).
    return [regex]::Replace($Content, '(?m)^models:\s*\[\s*\]\s*\n?', '')
}

function Backup-ContinueConfigFile {
    param([string]$ConfigPath)
    if (-not (Test-Path -LiteralPath $ConfigPath)) { return $null }
    $dir = Split-Path -Path $ConfigPath -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $dir "config.yaml.bak.$stamp"
    Copy-Item -LiteralPath $ConfigPath -Destination $backup -Force
    return $backup
}

function Add-ContinueOvmsConfigToResult {
    param(
        [object]$Result,
        [switch]$Approve,
        [switch]$Apply,
        [string]$CatalogModelId = $script:DefaultCodingCatalogModelId,
        [string]$ServingModel = $script:DefaultCodingServingModelId,
        [int]$Port = $script:DefaultCodingOvmsPort
    )
    $baseUrl = Get-OvmsBaseUrl -Port $Port
    $configPath = Get-ContinueConfigPath

    $vscode = Test-VscodeContinuePrereq
    Add-VerifyCheck -Result $Result -Check @{
        id      = 'P1-vscode-continue'
        status  = $(if ($vscode.ok) { 'pass' } else { 'partial' })
        message = $vscode.message
    }
    if (-not $vscode.ok) {
        $Result.warnings += $vscode.message
    }

    $live = Get-OvmsAdvertisedModelIdForAgent -BaseUrl $baseUrl -CatalogModelId $CatalogModelId
    $serving = if ($live.model_for_agent) { $live.model_for_agent } else { $ServingModel }
    $Result.endpoint = $baseUrl
    $Result.catalog_model_id = $CatalogModelId
    $Result.serving_model = $serving
    $Result.continue_config_path = $configPath

    if (-not $live.advertised_match) {
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'P2-ovms-coder-endpoint'
            status  = 'fail'
            message = $live.advertised_match_message
        }
        $Result.functional_status = 'fail'
        $Result.exit_code = 1
        $Result.error = @{
            code        = 'OVMS_CODER_NOT_READY'
            message     = $live.advertised_match_message
            remediation = "Run invoke-ovms-agentic-setup.ps1 -Approve -Pull -Model '$CatalogModelId' -Target GPU -Port $Port first"
        }
        return
    }

    Add-VerifyCheck -Result $Result -Check @{
        id      = 'P2-ovms-coder-endpoint'
        status  = 'pass'
        message = "$serving on $baseUrl"
    }

    $modelLines = Get-ContinueOvmsCoderModelYamlLines -ServingModel $serving -ApiBase $baseUrl
    $existing = $null
    if (Test-Path -LiteralPath $configPath) {
        $existing = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    }
    $merged = Merge-ContinueConfigWithOvmsCoder -ExistingContent $existing -ModelLines $modelLines
    $staged = @{
        path           = $configPath
        merged_preview = $merged
        merge_policy   = 'add_or_update_model_no_default_change'
        serving_model  = $serving
        api_base       = $baseUrl
    }
    Add-VerifyCheck -Result $Result -Check @{ id = 'P3-continue-config-staged'; status = 'pass'; evidence = $staged }

    if ($Apply) {
        if (-not (Test-ApprovalRequired -RiskClass 'write-config' -Approve:$Approve)) {
            $Result.functional_status = 'blocked'
            $Result.exit_code = 2
            $Result.warnings += 'Writing Continue config requires -Approve'
            Add-VerifyCheck -Result $Result -Check @{ id = 'P4-continue-config-apply'; status = 'skip'; message = 'Apply blocked without approval' }
            return
        }
        $backup = Backup-ContinueConfigFile -ConfigPath $configPath
        if ($backup) { $Result.continue_config_backup = $backup }
        $dir = Split-Path -Path $configPath -Parent
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($configPath, $merged, $utf8NoBom)
        Add-VerifyCheck -Result $Result -Check @{
            id      = 'P4-continue-config-apply'
            status  = 'pass'
            message = "Wrote merged config to $configPath"
        }
        $Result.next_steps = @(
            'Reload VS Code (Developer: Reload Window) or restart VS Code.'
            "In Continue, select model 'OVMS $serving' (not set as default automatically)."
            'Try chat in Continue; enable autocomplete in Continue UI if desired (off by default).'
        )
        $Result.functional_status = 'pass'
        $Result.exit_code = 0
    } else {
        $Result.warnings += 'Continue config staged only; re-run with -Apply -Approve to write ~/.continue/config.yaml'
        $Result.next_steps = @(
            'Review staged merged_preview in check P3-continue-config-staged evidence.'
            "Run configure-continue-ovms.ps1 -Approve -Apply (or invoke-openvino-coding-assistant-setup.ps1 -Apply) to write config."
        )
        $Result.functional_status = 'pass'
        $Result.exit_code = 0
    }
}
