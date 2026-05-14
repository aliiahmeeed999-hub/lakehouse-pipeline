-- M2: Iceberg table creation with year/month/day partitioning.
-- This matches analytics.sql, which expects pruning by year/month/day.

CREATE SCHEMA IF NOT EXISTS iceberg.events;

CREATE TABLE IF NOT EXISTS iceberg.events.raw_events (
    order_id BIGINT,
    customer_id BIGINT,
    product_id BIGINT,
    quantity INTEGER,
    price DOUBLE,
    event_time TIMESTAMP,
    year VARCHAR,
    month VARCHAR,
    day VARCHAR
)
WITH (
    format = 'PARQUET',
    partitioning = ARRAY['year', 'month', 'day']
);
