-- M2: Time travel / snapshot demo.

-- 1. List table snapshots.
SELECT snapshot_id, committed_at, operation
FROM iceberg.events.raw_events$snapshots
ORDER BY committed_at DESC;

-- 2. After copying one snapshot_id from the result above, run:
-- SELECT count(*)
-- FROM iceberg.events.raw_events
-- FOR VERSION AS OF <snapshot_id>;
