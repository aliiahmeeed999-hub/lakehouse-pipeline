-- M2: Partition pruning validation.

EXPLAIN
SELECT count(*)
FROM iceberg.events.raw_events
WHERE year = '2024'
  AND month = '06'
  AND day = '15';
