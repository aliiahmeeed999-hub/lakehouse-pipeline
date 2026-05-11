param(
    [switch]$SkipComposeUp = $false
)

$ErrorActionPreference = "Stop"

function Wait-ForHttp {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$Retries = 60,
        [int]$DelaySeconds = 5
    )

    for ($i = 1; $i -le $Retries; $i++) {
        try {
            $null = Invoke-RestMethod -Uri $Url -Method Get -TimeoutSec 5
            Write-Host "Ready: $Url"
            return
        }
        catch {
            Write-Host "Waiting for $Url ($i/$Retries)..."
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    throw "Service did not become ready: $Url"
}

function Upsert-Connector {
    param(
        [Parameter(Mandatory = $true)][string]$ConnectorFile
    )

    $jsonText = Get-Content $ConnectorFile -Raw
    $payload = $jsonText | ConvertFrom-Json
    $name = $payload.name

    try {
        $null = Invoke-RestMethod -Uri "http://localhost:8083/connectors/$name" -Method Get -TimeoutSec 5
        Write-Host "Updating connector: $name"
        $updateBody = $payload.config | ConvertTo-Json -Depth 20
        $null = Invoke-RestMethod -Uri "http://localhost:8083/connectors/$name/config" -Method Put -ContentType "application/json" -Body $updateBody
    }
    catch {
        Write-Host "Creating connector: $name"
        $null = Invoke-RestMethod -Uri "http://localhost:8083/connectors" -Method Post -ContentType "application/json" -Body $jsonText
    }
}

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

if (-not $SkipComposeUp) {
    Write-Host "Starting all services..."
    docker compose up -d
}

Write-Host "Waiting for platform services..."
Wait-ForHttp -Url "http://localhost:8081/subjects"
Wait-ForHttp -Url "http://localhost:8083/connectors"

Write-Host "Registering connectors..."
Upsert-Connector -ConnectorFile "$projectRoot/connectors/postgres-source.json"
Start-Sleep -Seconds 3
Upsert-Connector -ConnectorFile "$projectRoot/connectors/hdfs-sink.json"

Write-Host "Connector status snapshot:"
Invoke-RestMethod -Uri "http://localhost:8083/connectors/postgres-cdc-source/status" -Method Get | ConvertTo-Json -Depth 8
Invoke-RestMethod -Uri "http://localhost:8083/connectors/hdfs-sink-orders/status" -Method Get | ConvertTo-Json -Depth 8

Write-Host "Bootstrap completed."
