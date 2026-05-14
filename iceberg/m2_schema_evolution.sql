-- M2: Schema evolution test.
-- Iceberg allows adding a column without breaking existing data.

ALTER TABLE iceberg.events.raw_events
ADD COLUMN user_agent VARCHAR;

SELECT order_id, customer_id, user_agent
FROM iceberg.events.raw_events
LIMIT 10;
