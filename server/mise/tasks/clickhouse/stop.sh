#!/usr/bin/env bash
#MISE description="Stop ClickHouse server"

set -euo pipefail

CLICKHOUSE_RUNTIME_DIR="${TUIST_SERVER_CLICKHOUSE_RUNTIME_DIR:-${XDG_STATE_HOME:-${HOME}/.local/state}/tuist/clickhouse}"
CLICKHOUSE_NATIVE_PORT="${TUIST_SERVER_CLICKHOUSE_NATIVE_PORT:-9000}"
PID_FILE="${CLICKHOUSE_RUNTIME_DIR}/clickhouse.pid"

if [[ ! -f "${PID_FILE}" ]]; then
  echo "ClickHouse is managed externally"
  exit 0
fi

pid="$(tr -d '[:space:]' < "${PID_FILE}")"
if [[ -z "${pid}" ]] || ! kill -0 "${pid}" >/dev/null 2>&1; then
  rm -f "${PID_FILE}"
  echo "ClickHouse is managed externally"
  exit 0
fi

if clickhouse client --host 127.0.0.1 --port "${CLICKHOUSE_NATIVE_PORT}" --query "SYSTEM SHUTDOWN" >/dev/null 2>&1; then
  if [[ -f "${PID_FILE}" ]]; then
    for _ in $(seq 1 30); do
      if [[ -z "${pid}" ]] || ! kill -0 "${pid}" >/dev/null 2>&1; then
        rm -f "${PID_FILE}"
        echo "ClickHouse stopped"
        exit 0
      fi
      sleep 1
    done
  fi

  echo "ClickHouse stopped"
else
  if [[ -n "${pid}" ]] && ! kill -0 "${pid}" >/dev/null 2>&1; then
    rm -f "${PID_FILE}"
  fi

  echo "ClickHouse is not running"
fi
