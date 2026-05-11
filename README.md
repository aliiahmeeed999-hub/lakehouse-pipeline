# CSC5356 ASS2 - Realtime CDC to HDFS

This project implements an enterprise-style CDC pipeline:

`PostgreSQL -> Debezium (Kafka Connect Source) -> Kafka -> Kafka Connect HDFS Sink -> HDFS`

## 1) Prerequisites

- Docker Desktop (WSL2 backend)
- Docker resources: at least 12 GB RAM (16 GB recommended)
- PowerShell 7+ or Windows PowerShell 5.1

## 2) Project Structure

- `docker-compose.yml` - full platform stack
- `sql/init.sql` - source schema + seed data
- `connectors/postgres-source.json` - Debezium source connector config
- `connectors/hdfs-sink.json` - HDFS sink connector config
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
docker exec kafka kafka-topics --bootstrap-server kafka:29092 --list
docker exec kafka kafka-console-consumer --bootstrap-server kafka:29092 --topic postgres.public.orders --from-beginning --max-messages 10
docker exec namenode hdfs dfs -ls -R /data/cdc
docker exec connect curl -s http://localhost:8083/connectors/postgres-cdc-source/status
docker exec connect curl -s http://localhost:8083/connectors/hdfs-sink-orders/status
```

## 5) Reliability / Recovery Tests

### Connect restart test
```powershell
docker restart connect
Start-Sleep -Seconds 20
docker exec connect curl -s http://localhost:8083/connectors/postgres-cdc-source/status
docker exec connect curl -s http://localhost:8083/connectors/hdfs-sink-orders/status
```

### Kafka restart test
```powershell
docker restart kafka
Start-Sleep -Seconds 25
docker exec connect curl -s http://localhost:8083/connectors/postgres-cdc-source/status
docker exec connect curl -s http://localhost:8083/connectors/hdfs-sink-orders/status
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
6. HDFS sink connector status (`RUNNING`)
7. HDFS directory listing + sample file content
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
