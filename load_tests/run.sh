#!/usr/bin/env bash
set -uo pipefail

# On Docker Desktop (macOS/Windows), k6 in a container reaches the host via host.docker.internal
if [[ "$(uname)" == "Darwin" ]] || [[ "$(uname)" == MINGW* ]] || [[ "$(uname)" == MSYS* ]]; then
  DEFAULT_BASE_URL="http://host.docker.internal:3000"
else
  DEFAULT_BASE_URL="http://127.0.0.1:3000"
fi

BASE_URL="${BASE_URL:-$DEFAULT_BASE_URL}"
RESULTS_DIR="$(cd "$(dirname "$0")" && pwd)/results"
mkdir -p "$RESULTS_DIR"
STAMP=$(date -u +"%Y%m%dT%H%M%SZ")
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUMMARY_MD="$RESULTS_DIR/${STAMP}_SUMMARY.md"

USE_DOCKER_K6=0
if ! command -v k6 >/dev/null 2>&1; then
  USE_DOCKER_K6=1
  echo "k6 not found locally — using grafana/k6 Docker image"
fi

run_k6() {
  if [[ "$USE_DOCKER_K6" == "1" ]]; then
    docker run --rm \
      -e BASE_URL="$BASE_URL" \
      -v "$SCRIPT_DIR:/scripts" \
      grafana/k6 "$@"
  else
    BASE_URL="$BASE_URL" k6 "$@"
  fi
}

script_path() {
  local name="$1"
  if [[ "$USE_DOCKER_K6" == "1" ]]; then
    echo "/scripts/$name"
  else
    echo "$SCRIPT_DIR/$name"
  fi
}

export_path() {
  local name="$1"
  if [[ "$USE_DOCKER_K6" == "1" ]]; then
    echo "/scripts/results/$name"
  else
    echo "$RESULTS_DIR/$name"
  fi
}

echo "# Flash Sale Load Test Results ($STAMP)" > "$SUMMARY_MD"
echo "" >> "$SUMMARY_MD"
echo "Base URL: \`$BASE_URL\`" >> "$SUMMARY_MD"
echo "" >> "$SUMMARY_MD"

run_scenario() {
  local name="$1"
  local vus="$2"
  local stock="$3"
  local duration="${4:-60s}"
  local max_checkouts="${5:-100}"
  local summary
  summary="$(export_path "${STAMP}_${name}_vus${vus}.json")"
  local log="$RESULTS_DIR/${STAMP}_${name}_vus${vus}.log"
  echo "=== Running $name with VUs=$vus stock=$stock duration=$duration max_checkouts=$max_checkouts ==="
  set +e
  run_k6 run \
    -e "BASE_URL=$BASE_URL" \
    -e "VUS=$vus" \
    -e "STOCK=$stock" \
    -e "DURATION=$duration" \
    -e "MAX_CHECKOUTS=$max_checkouts" \
    --summary-export "$summary" \
    "$(script_path flash_sale.js)" | tee "$log"
  local rc=${PIPESTATUS[0]}
  set -e
  echo "" >> "$SUMMARY_MD"
  echo "## $name (VUs=$vus, stock=$stock)" >> "$SUMMARY_MD"
  echo "" >> "$SUMMARY_MD"
  echo "- exit_code: $rc" >> "$SUMMARY_MD"
  echo "- log: \`$(basename "$log")\`" >> "$SUMMARY_MD"
  if [[ -f "$RESULTS_DIR/${STAMP}_${name}_vus${vus}.json" ]]; then
    python3 - <<PY >> "$SUMMARY_MD"
import json
p="$RESULTS_DIR/${STAMP}_${name}_vus${vus}.json"
d=json.load(open(p))
m=d.get("metrics", {})
def val(path, key="value"):
    cur=m
    for part in path.split("."):
        if cur is None: return None
        cur=cur.get(part)
    if isinstance(cur, dict):
        return cur.get(key) or cur.get("rate") or cur.get("count") or cur.get("p(95)") or cur.get("avg")
    return cur
print(f"- http_reqs: {m.get('http_reqs',{}).get('values',{}).get('count')}")
print(f"- http_reqs/s: {m.get('http_reqs',{}).get('values',{}).get('rate')}")
print(f"- http_req_duration p50: {m.get('http_req_duration',{}).get('values',{}).get('p(50)')}")
print(f"- http_req_duration p95: {m.get('http_req_duration',{}).get('values',{}).get('p(95)')}")
print(f"- http_req_duration p99: {m.get('http_req_duration',{}).get('values',{}).get('p(99)')}")
print(f"- http_req_failed rate: {m.get('http_req_failed',{}).get('values',{}).get('rate')}")
print(f"- checkouts_ok: {m.get('checkouts_ok',{}).get('values',{}).get('count')}")
print(f"- checkouts_fail: {m.get('checkouts_fail',{}).get('values',{}).get('count')}")
print(f"- rate_limited: {m.get('rate_limited',{}).get('values',{}).get('count')}")
print(f"- db_errors: {m.get('db_errors',{}).get('values',{}).get('count')}")
print(f"- queue_wait_ms avg: {m.get('queue_wait_ms',{}).get('values',{}).get('avg')}")
print(f"- queue_wait_ms p95: {m.get('queue_wait_ms',{}).get('values',{}).get('p(95)')}")
print(f"- oversell_suspect: {m.get('oversell_suspect',{}).get('values',{}).get('count')}")
PY
  fi
  # Extract FINAL_STOCK / METRICS from log
  grep -E 'FINAL_STOCK=|METRICS_SNAPSHOT=' "$log" | tail -5 >> "$SUMMARY_MD" || true
}

# Warm-up / smoke
run_scenario "smoke" 50 50 30s 25

# Portfolio scenarios — stock limited to create contention; more checkouts capacity for throughput
run_scenario "spike_1k" 1000 200 90s 50
run_scenario "spike_5k" 5000 500 120s 100

if [[ "${RUN_10K:-0}" == "1" ]]; then
  run_scenario "spike_10k" 10000 1000 180s 150
fi

echo "=== Final unit contention ==="
set +e
run_k6 run \
  -e "BASE_URL=$BASE_URL" \
  -e "VUS=100" \
  --summary-export "$(export_path "${STAMP}_final_unit.json")" \
  "$(script_path final_unit.js)" | tee "$RESULTS_DIR/${STAMP}_final_unit.log"
set -e
echo "" >> "$SUMMARY_MD"
echo "## final_unit (100 VUs, stock=1)" >> "$SUMMARY_MD"
grep -E 'FINAL_STOCK=|final_unit' "$RESULTS_DIR/${STAMP}_final_unit.log" | tail -10 >> "$SUMMARY_MD" || true

echo "Results written to $RESULTS_DIR"
echo "Summary: $SUMMARY_MD"
