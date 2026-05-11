$ErrorActionPreference = "Stop"

$smallFiles = 0
$bigFiles = 0
$fileCount = 0
$totalMb = 0.0

function Convert-ToMb {
    param(
        [Parameter(Mandatory = $true)][double]$Size,
        [Parameter(Mandatory = $true)][string]$Unit
    )

    switch ($Unit) {
        "B" { return $Size / 1024 / 1024 }
        "KiB" { return $Size / 1024 }
        "MiB" { return $Size }
        "GiB" { return $Size * 1024 }
        default { throw "Unsupported size unit: $Unit" }
    }
}

Write-Host "Auditing Parquet files in MinIO raw-events bucket..."

try {
    $listing = docker run --rm --network lakehouse minio/mc:latest sh -c "mc alias set local http://minio1:9000 minioadmin minioadmin123 --quiet && mc ls --recursive local/raw-events" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ($listing -join [Environment]::NewLine)
    }
}
catch {
    Write-Host "ERROR: Failed to list MinIO bucket: $($_.Exception.Message)"
    exit 1
}

foreach ($line in $listing) {
    if ($line -notmatch '\.parquet\s*$') {
        continue
    }

    if ($line -notmatch '(?<size>[0-9]+(?:\.[0-9]+)?)\s*(?<unit>B|KiB|MiB|GiB)\s+(?:\S+\s+)?(?<path>.+\.parquet)\s*$') {
        Write-Host "WARNING: Could not parse parquet listing line: $line"
        continue
    }

    $size = [double]$Matches.size
    $unit = $Matches.unit
    $path = $Matches.path
    $sizeMb = Convert-ToMb -Size $size -Unit $unit
    $flag = ""

    if ($sizeMb -lt 10) {
        $flag = "SMALL FILE"
        $smallFiles++
    }
    elseif ($sizeMb -gt 512) {
        $flag = "OVERSIZED"
        $bigFiles++
    }

    $fileCount++
    $totalMb += $sizeMb

    $displaySize = [math]::Round($sizeMb, 2)
    if ($flag) {
        Write-Host "$path - $displaySize MB - $flag"
    }
    else {
        Write-Host "$path - $displaySize MB"
    }
}

if ($fileCount -eq 0) {
    Write-Host "WARNING: No Parquet files found. The bucket may be empty."
    exit 0
}

$totalGb = $totalMb / 1024
$averageMb = $totalMb / $fileCount

Write-Host "Summary:"
Write-Host "Total Parquet file count: $fileCount"
Write-Host "Total data size in GB: $([math]::Round($totalGb, 2))"
Write-Host "Average file size in MB: $([math]::Round($averageMb, 2))"
Write-Host "Small file count: $smallFiles"
Write-Host "Oversized file count: $bigFiles"

if ($smallFiles -gt 0) {
    Write-Host "AUDIT FAILED"
    exit 1
}

Write-Host "AUDIT PASSED"
exit 0
