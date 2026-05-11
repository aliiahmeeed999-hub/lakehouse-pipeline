#!/usr/bin/env bash
set -euo pipefail

echo "Auditing Parquet files in MinIO raw-events bucket..."

mc_output="$(
  docker run --rm --network lakehouse minio/mc:latest sh -c \
    "mc alias set local http://minio1:9000 minioadmin minioadmin123 --quiet && mc ls --recursive local/raw-events"
)"

if [ -z "${mc_output}" ]; then
  echo "WARNING: No output from mc ls. The bucket may be empty."
  exit 0
fi

total_files=0
small=0
big=0
total_mb="0"

while IFS= read -r line; do
  [[ "${line}" == *.parquet ]] || continue

  size_value="$(echo "${line}" | awk '{print $(NF-2)}')"
  size_unit="$(echo "${line}" | awk '{print $(NF-1)}')"
  file_path="$(echo "${line}" | awk '{print $NF}')"

  case "${size_unit}" in
    B)
      size_mb="$(echo "scale=6; ${size_value} / 1024 / 1024" | bc)"
      ;;
    KiB)
      size_mb="$(echo "scale=6; ${size_value} / 1024" | bc)"
      ;;
    MiB)
      size_mb="$(echo "scale=6; ${size_value}" | bc)"
      ;;
    GiB)
      size_mb="$(echo "scale=6; ${size_value} * 1024" | bc)"
      ;;
    *)
      echo "WARNING: Unsupported size unit in line: ${line}"
      continue
      ;;
  esac

  flag=""
  if [ "$(echo "${size_mb} < 10" | bc)" -eq 1 ]; then
    flag="SMALL FILE"
    small=$((small + 1))
  elif [ "$(echo "${size_mb} > 512" | bc)" -eq 1 ]; then
    flag="OVERSIZED"
    big=$((big + 1))
  fi

  total_files=$((total_files + 1))
  total_mb="$(echo "scale=6; ${total_mb} + ${size_mb}" | bc)"

  if [ -n "${flag}" ]; then
    printf "%s - %.2f MB - %s\n" "${file_path}" "${size_mb}" "${flag}"
  else
    printf "%s - %.2f MB\n" "${file_path}" "${size_mb}"
  fi
done <<< "${mc_output}"

if [ "${total_files}" -eq 0 ]; then
  echo "WARNING: No Parquet files found. The bucket may be empty."
  exit 0
fi

total_gb="$(echo "scale=6; ${total_mb} / 1024" | bc)"
average_mb="$(echo "scale=6; ${total_mb} / ${total_files}" | bc)"

echo "Summary:"
printf "Total files: %d\n" "${total_files}"
printf "Total GB: %.2f\n" "${total_gb}"
printf "Average MB: %.2f\n" "${average_mb}"
printf "Small count: %d\n" "${small}"
printf "Oversized count: %d\n" "${big}"

if [ "${small}" -gt 0 ]; then
  echo "AUDIT FAILED"
  exit 1
fi

echo "AUDIT PASSED"
exit 0
