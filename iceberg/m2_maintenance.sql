-- M2: Iceberg maintenance operations.

-- Compact small files.
ALTER TABLE iceberg.events.raw_events
EXECUTE optimize(file_size_threshold => '64MB');

-- Expire old snapshots.
ALTER TABLE iceberg.events.raw_events
EXECUTE expire_snapshots(retention_threshold => '7d');
