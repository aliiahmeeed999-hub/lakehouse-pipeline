#!/usr/bin/env bash
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$ROOT/connectors/minio-parquet-sink.json"
CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"
CONNECTOR_NAME="minio-parquet-sink"

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

extract_config_json() {
  export CONFIG_FILE
  if command -v jq >/dev/null 2>&1; then
    jq '.config' "$CONFIG_FILE"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json, os; p=os.environ["CONFIG_FILE"]; print(json.dumps(json.load(open(p))["config"]))'
  else
    fail "Need jq or python3 to extract connector config from JSON"
  fi
}

parse_connector_state() {
  local json="$1"
  if command -v jq >/dev/null 2>&1; then
    echo "$json" | jq -r '.connector.state // empty' 2>/dev/null || true
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys
try:
  d=json.load(sys.stdin)
  print(d.get("connector",{}).get("state",""))
except Exception:
  pass' <<<"$json" 2>/dev/null || true
  else
    fail "Need jq or python3 to parse connector status JSON"
  fi
}

curl_body_file="$(mktemp "${TMPDIR:-/tmp}/deploy-connector.XXXXXX" 2>/dev/null)" || true
if [[ -z "$curl_body_file" ]]; then
  curl_body_file="${TMPDIR:-/tmp}/deploy-connector.$$.$RANDOM.tmp"
fi
: >"$curl_body_file"
cleanup() { rm -f "$curl_body_file"; }
trap cleanup EXIT

echo "Step 1: Wait for Kafka Connect REST API at ${CONNECT_URL} (GET /connectors, max 60s)"
deadline=$(( $(date +%s) + 60 ))
while true; do
  code="$(curl -s -S -o /dev/null -w "%{http_code}" "${CONNECT_URL}/connectors" || echo "000")"
  if [[ "$code" == "200" ]]; then
    echo "[OK] Kafka Connect returned HTTP 200 on GET /connectors"
    break
  fi
  now=$(date +%s)
  if (( now >= deadline )); then
    fail "Kafka Connect not ready within 60 seconds (last HTTP code: ${code})"
  fi
  sleep 2
done

echo "Step 2: Check if connector '${CONNECTOR_NAME}' exists (GET /connectors/${CONNECTOR_NAME})"
exists_code="$(curl -s -S -o /dev/null -w "%{http_code}" "${CONNECT_URL}/connectors/${CONNECTOR_NAME}" || echo "000")"

if [[ "$exists_code" == "200" ]]; then
  echo "[OK] Connector '${CONNECTOR_NAME}' exists — updating configuration"
  echo "Step 3: PUT ${CONNECT_URL}/connectors/${CONNECTOR_NAME}/config (config object only)"
  http_code="$(extract_config_json | curl -s -S -o "$curl_body_file" -w "%{http_code}" \
    -X PUT \
    -H "Content-Type: application/json" \
    --data-binary @- \
    "${CONNECT_URL}/connectors/${CONNECTOR_NAME}/config" || echo "000")"
  if [[ "$http_code" != "200" ]]; then
    [[ -s "$curl_body_file" ]] && cat "$curl_body_file" >&2
    fail "PUT config failed with HTTP ${http_code}"
  fi
  echo "[OK] Connector configuration updated (HTTP ${http_code})"
elif [[ "$exists_code" == "404" ]]; then
  echo "[OK] Connector '${CONNECTOR_NAME}' does not exist — creating"
  echo "Step 4: POST ${CONNECT_URL}/connectors (full ${CONFIG_FILE})"
  http_code="$(curl -s -S -o "$curl_body_file" -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    --data-binary @"${CONFIG_FILE}" \
    "${CONNECT_URL}/connectors" || echo "000")"
  if [[ "$http_code" != "200" && "$http_code" != "201" ]]; then
    [[ -s "$curl_body_file" ]] && cat "$curl_body_file" >&2
    fail "POST connector failed with HTTP ${http_code}"
  fi
  echo "[OK] Connector created (HTTP ${http_code})"
else
  fail "Unexpected HTTP ${exists_code} when checking connector existence"
fi

echo "Step 5: Poll GET /connectors/${CONNECTOR_NAME}/status every 5s (max 60s) until connector state is RUNNING"
deadline=$(( $(date +%s) + 60 ))
final_status=""
while true; do
  final_status="$(curl -s -S "${CONNECT_URL}/connectors/${CONNECTOR_NAME}/status" || true)"
  state="$(parse_connector_state "$final_status")"
  if [[ "$state" == "RUNNING" ]]; then
    echo "[OK] Connector state is RUNNING"
    break
  fi
  now=$(date +%s)
  if (( now >= deadline )); then
    echo "Step 6: Final status (connector did not reach RUNNING within 60s)"
    echo "$final_status"
    exit 1
  fi
  echo "[wait] connector.state=${state:-unknown}; sleeping 5s ..."
  sleep 5
done

echo "Step 6: Final status JSON"
echo "$final_status"
exit 0
