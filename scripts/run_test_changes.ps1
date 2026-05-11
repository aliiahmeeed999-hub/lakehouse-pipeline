param(
    [int]$BenchmarkRows = 1000
)

$ErrorActionPreference = "Stop"

function Exec-Psql {
    param(
        [Parameter(Mandatory = $true)][string]$Sql
    )
    docker exec postgres psql -U postgres -d cdcdb -c $Sql
}

Write-Host "Initial data snapshot:"
Exec-Psql -Sql "SELECT order_id, customer_id, product_code, quantity, unit_price, order_status, updated_at FROM public.orders ORDER BY order_id;"

Write-Host "Applying CRUD changes for CDC evidence..."
Exec-Psql -Sql "INSERT INTO public.orders (customer_id, product_code, quantity, unit_price, order_status) VALUES (2001, 'HEADSET-H1', 1, 79.99, 'NEW');"
Exec-Psql -Sql "UPDATE public.orders SET order_status='SHIPPED', quantity=3 WHERE order_id=1;"
Exec-Psql -Sql "DELETE FROM public.orders WHERE order_id=2;"

Write-Host "Applying schema evolution change..."
Exec-Psql -Sql "ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS promo_code VARCHAR(20);"
Exec-Psql -Sql "UPDATE public.orders SET promo_code='SPRING26' WHERE order_id=1;"

Write-Host "Running mini benchmark inserts: $BenchmarkRows rows..."
$benchmarkSql = @"
INSERT INTO public.orders (customer_id, product_code, quantity, unit_price, order_status, promo_code)
SELECT
  5000 + g,
  'BULK-' || g,
  1 + (g % 5),
  (10 + (g % 90))::numeric(10,2),
  'NEW',
  CASE WHEN g % 2 = 0 THEN 'LOAD26' ELSE NULL END
FROM generate_series(1, $BenchmarkRows) AS g;
"@

$started = Get-Date
Exec-Psql -Sql $benchmarkSql
$ended = Get-Date
$elapsed = ($ended - $started).TotalSeconds
if ($elapsed -eq 0) { $elapsed = 1 }
$rate = [math]::Round($BenchmarkRows / $elapsed, 2)
Write-Host "Inserted $BenchmarkRows rows in $([math]::Round($elapsed,2)) seconds (~$rate rows/s)"

Write-Host "Current table row count:"
Exec-Psql -Sql "SELECT COUNT(*) AS total_rows FROM public.orders;"

Write-Host "Wait 30-90 seconds for connector flush, then validate HDFS files."
