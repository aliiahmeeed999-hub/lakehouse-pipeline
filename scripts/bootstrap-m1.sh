#!/usr/bin/env bash
set -euo pipefail

CONNECT_URL="http://localhost:8083"
CONNECTOR_NAME="minio-parquet-sink"
CONNECTOR_JSON="$(dirname "$0")/../connectors/minio-parquet-sink.json"

echo "Waiting for Kafka Connect..."
for attempt in $(seq 1 24); do
  echo "Waiting for Kafka Connect HTTP 200 (${attempt}/24)..."
  if curl -sf "${CONNECT_URL}/connectors" >/dev/null; then
    echo "Kafka Connect is ready."
    break
  fi

  if [ "${attempt}" -eq 24 ]; then
    echo "Kafka Connect did not respond with HTTP 200 within 120 seconds."
    exit 1
  fi

  sleep 5
done

echo "Upserting ${CONNECTOR_NAME} connector..."
if curl -sf "${CONNECT_URL}/connectors/${CONNECTOR_NAME}" >/dev/null; then
  echo "Connector ${CONNECTOR_NAME} exists. Updating configuration..."
  jq '.config' "${CONNECTOR_JSON}" | curl -sf \
    -X PUT \
    -H "Content-Type: application/json" \
    --data-binary @- \
    "${CONNECT_URL}/connectors/${CONNECTOR_NAME}/config" >/dev/null
  echo "Connector ${CONNECTOR_NAME} updated."
else
  echo "Connector ${CONNECTOR_NAME} does not exist. Creating..."
  curl -sf \
    -X POST \
    -H "Content-Type: application/json" \
    --data-binary @"${CONNECTOR_JSON}" \
    "${CONNECT_URL}/connectors" >/dev/null
  echo "Connector ${CONNECTOR_NAME} created."
fi

echo "Waiting for ${CONNECTOR_NAME} health..."
for attempt in $(seq 1 18); do
  status_json="$(curl -sf "${CONNECT_URL}/connectors/${CONNECTOR_NAME}/status")"
  connector_state="$(echo "${status_json}" | jq -r '.connector.state')"
  failed_task_count="$(echo "${status_json}" | jq '[.tasks[] | select(.state != "RUNNING")] | length')"
  task_states="$(echo "${status_json}" | jq -r '[.tasks[] | .state] | join(", ")')"

  echo "Poll ${attempt}/18 - connector.state=${connector_state}; tasks=${task_states}; failed_task_count=${failed_task_count}"

  if [ "${connector_state}" = "RUNNING" ] && [ "${failed_task_count}" -eq 0 ]; then
    echo "M1 HEALTHY"
    exit 0
  fi

  sleep 5
done

echo "M1 DEGRADED"
exit 1
