#!/usr/bin/env bash
set -euo pipefail

CONNECT_URL="http://localhost:8083"
CONNECTOR_NAME="minio-parquet-sink"
STATUS_URL="${CONNECT_URL}/connectors/${CONNECTOR_NAME}/status"

if ! status_json="$(curl -sf "${STATUS_URL}")"; then
  echo "ERROR: Kafka Connect is unreachable or connector status could not be read."
  exit 1
fi

connector_state="$(echo "${status_json}" | jq -r '.connector.state')"
echo "Connector: ${CONNECTOR_NAME} state=${connector_state}"

echo "${status_json}" | jq -r '.tasks[] | "Task \(.id): state=\(.state)"'

echo "${status_json}" | jq -r '.tasks[] | select(.state == "FAILED" and .trace != null) | .trace'

failed_task_count="$(echo "${status_json}" | jq '[.tasks[] | select(.state != "RUNNING")] | length')"

if [ "${connector_state}" = "RUNNING" ] && [ "${failed_task_count}" -eq 0 ]; then
  echo "M1 HEALTHY"
  exit 0
fi

echo "M1 DEGRADED"
exit 1
