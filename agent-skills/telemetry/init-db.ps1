param(
    [string]$DbPath = (Join-Path $env:USERPROFILE '.aipc-agent-skills\telemetry.db')
)

$dir = Split-Path $DbPath -Parent
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

$sqlFile = Join-Path $PSScriptRoot 'init-db.sql'
$sql = Get-Content $sqlFile -Raw

# Requires sqlite3 on PATH, or System.Data.SQLite in P1
$sqlite = Get-Command sqlite3 -ErrorAction SilentlyContinue
if (-not $sqlite) {
    Write-Warning 'sqlite3 not found; create DB manually or install SQLite tools'
    exit 1
}

& sqlite3 $DbPath $sql
Write-Output "Initialized $DbPath"
