# CSC5356 ASS2 - Realtime CDC to MinIO + Iceberg

This project implements an enterprise-style CDC pipeline:

`PostgreSQL -> Debezium (Kafka Connect Source) -> Kafka -> Kafka Connect S3 Sink -> MinIO`

Iceberg metadata is managed through Nessie and queried by Spark and Trino.

## 1) Prerequisites

- Docker Desktop (WSL2 backend)
- Docker resources: at least 12 GB RAM (16 GB recommended)
- PowerShell 7+ or Windows PowerShell 5.1

## 2) Project Structure

- `docker-compose.yml` - full platform stack
- `sql/init.sql` - source schema + seed data
- `connectors/postgres-source.json` - Debezium source connector config
- `connectors/minio-parquet-sink.json` - MinIO/S3 sink connector config
- `scripts/bootstrap.ps1` - startup + connector registration
- `scripts/run_test_changes.ps1` - CRUD + schema evolution + benchmark load
- `scripts/collect_evidence.ps1` - command outputs for report appendix
- `report/ASS2_Report_Template.md` - report template content

## 3) Start Everything

From project root:

```powershell
docker compose up -d
.\scripts\bootstrap.ps1 -SkipComposeUp
```

Or run one command:

```powershell
.\scripts\bootstrap.ps1
```

## 4) Validate CDC Pipeline

Run:

```powershell
.\scripts\run_test_changes.ps1 -BenchmarkRows 1000
```

Then verify:

```powershell
docker exec broker kafka-topics --bootstrap-server broker:29092 --list
docker exec broker kafka-console-consumer --bootstrap-server broker:29092 --topic postgres.public.orders --from-beginning --max-messages 10
docker exec kafka-connect curl -s http://localhost:8083/connectors/postgres-cdc-source/status
docker exec kafka-connect curl -s http://localhost:8083/connectors/minio-parquet-sink/status
docker exec mc-init mc ls local/raw-events
```

You can also inspect object storage through the MinIO console at `http://localhost:9001`.

## 5) Reliability / Recovery Tests

### Connect restart test
```powershell
docker restart kafka-connect
Start-Sleep -Seconds 20
docker exec kafka-connect curl -s http://localhost:8083/connectors/postgres-cdc-source/status
docker exec kafka-connect curl -s http://localhost:8083/connectors/minio-parquet-sink/status
```

### Kafka restart test
```powershell
docker restart broker
Start-Sleep -Seconds 25
docker exec kafka-connect curl -s http://localhost:8083/connectors/postgres-cdc-source/status
docker exec kafka-connect curl -s http://localhost:8083/connectors/minio-parquet-sink/status
```

Note: Connect startup can take a few minutes because plugins are installed on container boot.

## 6) Evidence Collection for Report

Run:

```powershell
.\scripts\collect_evidence.ps1
```

This stores text outputs in `evidence/` to support screenshots and appendix.

## 7) Screenshot Checklist

Capture these for the report:

1. `docker ps` showing healthy services
2. Postgres rows before/after CRUD
3. Debezium connector status (`RUNNING`)
4. Kafka topic records showing insert/update/delete
5. Schema Registry subjects (`http://localhost:8081/subjects`)
6. MinIO/S3 sink connector status (`RUNNING`)
7. MinIO bucket listing + sample file content
8. Recovery test (service restart + recovered connector state)
9. Benchmark summary (rows/s + row counts)

## 8) Clean Up

```powershell
docker compose down
```

To remove volumes too:

```powershell
docker compose down -v
```

## M3 - Trino Query Engine

This extension adds Trino and Nessie to the lakehouse stack for Iceberg analytics.

Start the M3 services from the project root:

```powershell
.\scripts\start_m3.ps1
```

Open the Trino UI at:

`http://localhost:8084`

Run the analytics queries from `queries/analytics.sql` using Trino, for example:

```powershell
docker exec trino trino --execute "SELECT * FROM information_schema.tables WHERE table_schema = 'iceberg'"
# or
cat queries/analytics.sql | docker exec -i trino trino --file -
```

## Delivery Semantics

The Kafka Connect S3 Sink connector provides **at-least-once** delivery.
Exactly-once delivery is not supported by the S3/MinIO sink because S3
object writes are not transactional — the connector cannot atomically
commit an offset and a file write together.

Duplicate records are handled at the Iceberg layer: the Spark ETL job
uses INSERT INTO (append), and Iceberg snapshots allow deduplication
queries if needed. For a production system, deduplication would be
enforced with a MERGE INTO statement keyed on order_id before
exposing data to Trino.

The Nessie catalog is configured with in-memory persistence
(QUARKUS_DATASOURCE_DB_KIND=in-memory) for local development.
In production, replace with a PostgreSQL or DynamoDB backend to
persist catalog metadata across restarts.
