<#
Starts the M3 Trino + Nessie stack with MinIO and checks Trino/Nessie health.
#>

Write-Host "Starting M3 services: nessie, minio1, minio2, minio3, mc-init, trino"
docker compose up -d nessie minio1 minio2 minio3 mc-init trino

Write-Host "Waiting 20 seconds for the services to initialize..."
Start-Sleep -Seconds 20

$trinoHealthy = $false
$nessieHealthy = $false

try {
    docker exec trino trino --execute "SHOW CATALOGS" | Out-Null
    Write-Host "Trino is responding."
    $trinoHealthy = $true
} catch {
    Write-Warning "Trino health check failed."
}

try {
    Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:19120/api/v1/config' -TimeoutSec 15 | Out-Null
    Write-Host "Nessie is responding."
    $nessieHealthy = $true
} catch {
    Write-Warning "Nessie health check failed."
}

if ($trinoHealthy -and $nessieHealthy) {
    Write-Host "M3 stack ready"
    exit 0
} else {
    Write-Error "M3 stack did not start correctly. Check container logs for details."
    exit 1
}
