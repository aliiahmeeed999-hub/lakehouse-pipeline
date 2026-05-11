$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$evidenceDir = Join-Path $projectRoot "evidence"
if (-not (Test-Path $evidenceDir)) {
    New-Item -ItemType Directory -Path $evidenceDir | Out-Null
}

function Save-CommandOutput {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    $path = Join-Path $evidenceDir $FileName
    & $Action | Out-File -FilePath $path -Encoding utf8
    Write-Host "Saved: $path"
}

Save-CommandOutput -FileName "01_docker_ps.txt" -Action { docker ps }
Save-CommandOutput -FileName "02_topics.txt" -Action { docker exec kafka kafka-topics --bootstrap-server kafka:29092 --list }
Save-CommandOutput -FileName "03_postgres_connector_status.json" -Action { docker exec connect curl -s http://localhost:8083/connectors/postgres-cdc-source/status }
Save-CommandOutput -FileName "04_hdfs_connector_status.json" -Action { docker exec connect curl -s http://localhost:8083/connectors/hdfs-sink-orders/status }
Save-CommandOutput -FileName "05_schema_subjects.json" -Action { curl.exe -s http://localhost:8081/subjects }
Save-CommandOutput -FileName "06_postgres_orders.txt" -Action { docker exec postgres psql -U postgres -d cdcdb -c "SELECT * FROM public.orders ORDER BY order_id LIMIT 30;" }
Save-CommandOutput -FileName "07_hdfs_ls.txt" -Action { docker exec namenode hdfs dfs -ls -R /data/cdc }
Save-CommandOutput -FileName "08_connector_plugins.json" -Action { docker exec connect curl -s http://localhost:8083/connector-plugins }

Write-Host "Evidence collection completed."
