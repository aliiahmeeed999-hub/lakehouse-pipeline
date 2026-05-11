#!/usr/bin/env bash
set -u
set -o pipefail

NETWORK="${MINIO_DOCKER_NETWORK:-lakehouse}"
ROOT_USER="${MINIO_ROOT_USER:-minioadmin}"
ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-minioadmin123}"
BASE_URL="http://minio1:9000"
HEALTH_URL="${MINIO_HEALTH_URL:-${BASE_URL}/minio/health/live}"
WAIT_INTERVAL="${MINIO_WAIT_INTERVAL:-2}"
WAIT_MAX_ATTEMPTS="${MINIO_WAIT_MAX_ATTEMPTS:-90}"

CURL_IMAGE="${MINIO_CURL_IMAGE:-curlimages/curl:8.11.1}"
MC_IMAGE="${MINIO_MC_IMAGE:-minio/mc:latest}"

curl_http_code() {
  docker run --rm --network "$NETWORK" "$CURL_IMAGE" \
    -s -S -o /dev/null -w "%{http_code}" "$1"
}

run_mc() {
  docker run --rm --network "$NETWORK" "$MC_IMAGE" "$@"
}

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

echo "Step: wait for MinIO (${BASE_URL})"
attempt=0
while true; do
  code="$(curl_http_code "$HEALTH_URL" || echo "000")"
  if [[ "$code" == "200" ]]; then
    echo "[OK] MinIO responded with HTTP 200 (${HEALTH_URL})"
    break
  fi
  attempt=$((attempt + 1))
  if [[ "$attempt" -ge "$WAIT_MAX_ATTEMPTS" ]]; then
    fail "MinIO did not become ready (last HTTP code: ${code})"
  fi
  sleep "$WAIT_INTERVAL"
done

echo "Step: mc alias set local"
if run_mc alias set local "$BASE_URL" "$ROOT_USER" "$ROOT_PASSWORD"; then
  echo "[OK] mc alias set local"
else
  fail "mc alias set local"
fi

echo "Step: create bucket local/raw-events"
if run_mc mb --ignore-existing "local/raw-events"; then
  echo "[OK] bucket local/raw-events"
else
  fail "create bucket local/raw-events"
fi

echo "Step: create bucket local/iceberg-warehouse"
if run_mc mb --ignore-existing "local/iceberg-warehouse"; then
  echo "[OK] bucket local/iceberg-warehouse"
else
  fail "create bucket local/iceberg-warehouse"
fi

echo "Step: anonymous set public local/raw-events"
if run_mc anonymous set public "local/raw-events"; then
  echo "[OK] anonymous set public local/raw-events"
else
  fail "anonymous set public local/raw-events"
fi

echo "Step: anonymous set public local/iceberg-warehouse"
if run_mc anonymous set public "local/iceberg-warehouse"; then
  echo "[OK] anonymous set public local/iceberg-warehouse"
else
  fail "anonymous set public local/iceberg-warehouse"
fi

echo "[OK] MinIO initialization finished successfully"
exit 0
