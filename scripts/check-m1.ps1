$ErrorActionPreference = "Stop"

$connectorName = "minio-parquet-sink"
$statusUrl = "http://localhost:8083/connectors/$connectorName/status"

try {
    $status = Invoke-RestMethod -Uri $statusUrl -Method Get -TimeoutSec 10
}
catch {
    Write-Host "ERROR: Kafka Connect is unreachable or connector status could not be read: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$connectorState = $status.connector.state
$connectorColor = if ($connectorState -eq "RUNNING") { "Green" } else { "Red" }
Write-Host "Connector: $connectorName state=$connectorState" -ForegroundColor $connectorColor

$allTasksRunning = $true
foreach ($task in $status.tasks) {
    $taskState = $task.state
    $taskColor = if ($taskState -eq "RUNNING") { "Green" } else { "Red" }

    Write-Host "Task $($task.id): state=$taskState" -ForegroundColor $taskColor

    if ($taskState -ne "RUNNING") {
        $allTasksRunning = $false
    }

    if ($taskState -eq "FAILED" -and $task.trace) {
        Write-Host $task.trace -ForegroundColor Red
    }
}

if ($connectorState -eq "RUNNING" -and $allTasksRunning) {
    Write-Host "M1 HEALTHY" -ForegroundColor Green
    exit 0
}

Write-Host "M1 DEGRADED" -ForegroundColor Red
exit 1
