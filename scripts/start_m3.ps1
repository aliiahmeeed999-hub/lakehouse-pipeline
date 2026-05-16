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

if (-not ($trinoHealthy -and $nessieHealthy)) {
    Write-Error "M3 stack did not start correctly. Check container logs for details."
    exit 1
}

Write-Host "Running Spark ETL: raw Parquet -> Iceberg..."
docker exec spark /opt/spark/bin/spark-submit `
    --master local[*] `
    /opt/spark-apps/m2_register_or_append_iceberg.py
if ($LASTEXITCODE -ne 0) {
    Write-Error "Spark ETL failed. Check spark container logs."
    exit 1
}
Write-Host "Spark ETL complete." -ForegroundColor Green

Write-Host "Validating Iceberg catalog connection..."
docker exec spark /opt/spark/bin/spark-submit `
    --master local[*] `
    /opt/spark-apps/m2_spark_setup.py

Write-Host "Running Trino analytics queries..."
New-Item -ItemType Directory -Force -Path "evidence" | Out-Null
docker exec trino trino --catalog iceberg --schema events `
    --execute (Get-Content queries/analytics.sql -Raw) `
    | Out-File -FilePath "evidence/analytics_output.txt" -Encoding utf8
Write-Host "Query output saved to evidence/analytics_output.txt" -ForegroundColor Green

Write-Host "M3 stack ready"
