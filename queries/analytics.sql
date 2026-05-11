-- Query 1: hourly event count for the last 24 hours
SELECT date_trunc('hour', order_ts) AS hour_bucket,
       COUNT(*) AS order_count
FROM iceberg.events.orders
WHERE order_ts >= current_timestamp - interval '24' hour
GROUP BY date_trunc('hour', order_ts)
ORDER BY hour_bucket;

-- Query 2: daily count with a rolling 7-day window
SELECT order_date,
       daily_count,
       SUM(daily_count) OVER (ORDER BY order_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS rolling_7_day_count
FROM (
  SELECT cast(order_ts AS date) AS order_date,
         COUNT(*) AS daily_count
  FROM iceberg.events.orders
  GROUP BY cast(order_ts AS date)
) t
ORDER BY order_date;

-- Query 3: month-over-month percentage change using LAG()
SELECT year,
       month,
       month_count,
       LAG(month_count) OVER (ORDER BY year, month) AS prev_month_count,
       CASE WHEN LAG(month_count) OVER (ORDER BY year, month) IS NULL THEN NULL
            ELSE ROUND(100.0 * (month_count - LAG(month_count) OVER (ORDER BY year, month)) / LAG(month_count) OVER (ORDER BY year, month), 2)
       END AS pct_change
FROM (
  SELECT extract(year FROM order_ts) AS year,
         extract(month FROM order_ts) AS month,
         COUNT(*) AS month_count
  FROM iceberg.events.orders
  GROUP BY extract(year FROM order_ts), extract(month FROM order_ts)
) t
ORDER BY year, month;

-- Query 4: EXPLAIN a partition-pruned query by year and month
EXPLAIN (TYPE DISTRIBUTED)
SELECT *
FROM iceberg.events.orders
WHERE year = 2025 AND month = 6;
