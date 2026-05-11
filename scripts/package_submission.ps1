$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$zipPath = Join-Path $projectRoot "CSC5356_ASS2_configs_and_scripts.zip"

if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

$includePaths = @(
    (Join-Path $projectRoot "docker-compose.yml"),
    (Join-Path $projectRoot "README.md"),
    (Join-Path $projectRoot "connectors"),
    (Join-Path $projectRoot "sql"),
    (Join-Path $projectRoot "scripts"),
    (Join-Path $projectRoot "evidence"),
    (Join-Path $projectRoot "report/ASS2_Report_Template.md")
)

Compress-Archive -Path $includePaths -DestinationPath $zipPath -Force
Write-Host "Created: $zipPath"
