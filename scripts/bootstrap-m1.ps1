$ErrorActionPreference = "Stop"

$connectUrl = "http://localhost:8083"
$connectorName = "minio-parquet-sink"
$connectorPath = Join-Path $PSScriptRoot "..\connectors\minio-parquet-sink.json"

function Write-Section {
    param(
        [Parameter(Mandatory = $true)][string]$Message
    )

    Write-Host $Message -ForegroundColor Cyan
}

function Wait-ForKafkaConnect {
    param(
        [int]$MaxSeconds = 120,
        [int]$DelaySeconds = 5
    )

    Write-Section "Waiting for Kafka Connect"
    $deadline = (Get-Date).AddSeconds($MaxSeconds)
    $attempt = 1

    while ((Get-Date) -lt $deadline) {
        Write-Host "Waiting for Kafka Connect HTTP 200 ($attempt)..."

        try {
            $response = Invoke-WebRequest -Uri "$connectUrl/connectors" -Method Get -TimeoutSec 5
            if ($response.StatusCode -eq 200) {
                Write-Host "Kafka Connect is ready." -ForegroundColor Green
                return
            }
        }
        catch {
            Write-Host "Kafka Connect not ready yet: $($_.Exception.Message)"
        }

        $attempt++
        Start-Sleep -Seconds $DelaySeconds
    }

    Write-Host "Kafka Connect did not respond with HTTP 200 within $MaxSeconds seconds." -ForegroundColor Red
    exit 1
}

function Upsert-MinioParquetSink {
    Write-Section "Upserting minio-parquet-sink connector"

    $jsonText = Get-Content $connectorPath -Raw
    $payload = $jsonText | ConvertFrom-Json
    $exists = $false

    try {
        $response = Invoke-WebRequest -Uri "$connectUrl/connectors/$connectorName" -Method Get -TimeoutSec 5
        $exists = ($response.StatusCode -eq 200)
    }
    catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }

        if ($statusCode -eq 404) {
            $exists = $false
        }
        else {
            Write-Host "Failed to check connector $connectorName`: $($_.Exception.Message)" -ForegroundColor Red
            throw
        }
    }

    if ($exists) {
        Write-Host "Connector $connectorName exists. Updating configuration..."
        $configBody = $payload.config | ConvertTo-Json -Depth 20
        $null = Invoke-RestMethod `
            -Uri "$connectUrl/connectors/$connectorName/config" `
            -Method Put `
            -ContentType "application/json" `
            -Body $configBody

        Write-Host "Connector $connectorName updated." -ForegroundColor Green
    }
    else {
        Write-Host "Connector $connectorName does not exist. Creating..."
        $null = Invoke-RestMethod `
            -Uri "$connectUrl/connectors" `
            -Method Post `
            -ContentType "application/json" `
            -Body $jsonText

        Write-Host "Connector $connectorName created." -ForegroundColor Green
    }
}

function Wait-ForM1Health {
    param(
        [int]$MaxSeconds = 90,
        [int]$DelaySeconds = 5
    )

    Write-Section "Waiting for minio-parquet-sink health"
    $deadline = (Get-Date).AddSeconds($MaxSeconds)
    $attempt = 1

    while ((Get-Date) -lt $deadline) {
        try {
            $status = Invoke-RestMethod -Uri "$connectUrl/connectors/$connectorName/status" -Method Get -TimeoutSec 5
            $connectorState = $status.connector.state
            $taskStates = @($status.tasks | ForEach-Object { $_.state })
            $tasksRunning = ($taskStates.Count -gt 0) -and (@($taskStates | Where-Object { $_ -ne "RUNNING" }).Count -eq 0)

            Write-Host "Poll $attempt - connector.state=$connectorState; tasks=$($taskStates -join ', ')"

            if ($connectorState -eq "RUNNING" -and $tasksRunning) {
                Write-Host "M1 HEALTHY" -ForegroundColor Green
                return
            }
        }
        catch {
            Write-Host "Poll $attempt - unable to read connector status: $($_.Exception.Message)" -ForegroundColor Red
        }

        $attempt++
        Start-Sleep -Seconds $DelaySeconds
    }

    Write-Host "M1 DEGRADED" -ForegroundColor Red
    exit 1
}

try {
    Wait-ForKafkaConnect
    Upsert-MinioParquetSink
    Wait-ForM1Health
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
