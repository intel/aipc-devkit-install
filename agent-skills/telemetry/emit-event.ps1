param(
    [Parameter(Mandatory = $true)][string]$RunId,
    [Parameter(Mandatory = $true)][string]$SkillId,
    [Parameter(Mandatory = $true)][string]$EventType,
    [Parameter(Mandatory = $true)][hashtable]$Payload,
    [string]$DbPath = (Join-Path $env:USERPROFILE '.aipc-agent-skills\telemetry.db')
)

$sqlite = Get-Command sqlite3 -ErrorAction SilentlyContinue
if (-not $sqlite) {
    Write-Warning 'sqlite3 not on PATH; event not persisted'
    return
}

$json = ($Payload | ConvertTo-Json -Compress -Depth 10) -replace "'", "''"
$q = @"
INSERT INTO skill_events (run_id, skill_id, event_type, payload_json)
VALUES ('$RunId', '$SkillId', '$EventType', '$json');
"@
& sqlite3 $DbPath $q
