#!/usr/bin/env bash
#MISE description="Start ClickHouse server as daemon"

set -euo pipefail

CLICKHOUSE_RUNTIME_DIR="${TUIST_SERVER_CLICKHOUSE_RUNTIME_DIR:-${XDG_STATE_HOME:-${HOME}/.local/state}/tuist/clickhouse}"
CLICKHOUSE_HTTP_PORT="${TUIST_SERVER_CLICKHOUSE_HTTP_PORT:-8123}"
CLICKHOUSE_NATIVE_PORT="${TUIST_SERVER_CLICKHOUSE_NATIVE_PORT:-9000}"
CLICKHOUSE_INTERSERVER_HTTP_PORT="${TUIST_SERVER_CLICKHOUSE_INTERSERVER_HTTP_PORT:-9009}"
CLICKHOUSE_MYSQL_PORT="${TUIST_SERVER_CLICKHOUSE_MYSQL_PORT:-9004}"
CLICKHOUSE_POSTGRESQL_PORT="${TUIST_SERVER_CLICKHOUSE_POSTGRESQL_PORT:-9005}"
CLICKHOUSE_KEEPER_PORT="${TUIST_SERVER_CLICKHOUSE_KEEPER_PORT:-9181}"
CLICKHOUSE_KEEPER_RAFT_PORT="${TUIST_SERVER_CLICKHOUSE_KEEPER_RAFT_PORT:-9234}"
CLICKHOUSE_HTTP_URL="${TUIST_SERVER_CLICKHOUSE_HTTP_URL:-http://127.0.0.1:${CLICKHOUSE_HTTP_PORT}}"

CONFIG_DIR="${CLICKHOUSE_RUNTIME_DIR}/config.d"
DATA_DIR="${CLICKHOUSE_RUNTIME_DIR}/data"
COORDINATION_DIR="${DATA_DIR}/coordination"
COORDINATION_LOG_DIR="${COORDINATION_DIR}/log"
COORDINATION_SNAPSHOTS_DIR="${COORDINATION_DIR}/snapshots"
TMP_DIR="${CLICKHOUSE_RUNTIME_DIR}/tmp"
USER_FILES_DIR="${CLICKHOUSE_RUNTIME_DIR}/user_files"
FORMAT_SCHEMA_DIR="${CLICKHOUSE_RUNTIME_DIR}/format_schemas"
LOG_DIR="${CLICKHOUSE_RUNTIME_DIR}/log"
PID_FILE="${CLICKHOUSE_RUNTIME_DIR}/clickhouse.pid"
STARTUP_LOG="${LOG_DIR}/startup.log"
SERVER_LOG="${LOG_DIR}/server.log"
ERROR_LOG="${LOG_DIR}/error.log"

mkdir -p \
  "${CONFIG_DIR}" \
  "${DATA_DIR}" \
  "${COORDINATION_LOG_DIR}" \
  "${COORDINATION_SNAPSHOTS_DIR}" \
  "${TMP_DIR}" \
  "${USER_FILES_DIR}" \
  "${FORMAT_SCHEMA_DIR}" \
  "${LOG_DIR}"

# Create config.d with query_log enabled (ClickHouse merges this with embedded defaults)
cat > "${CONFIG_DIR}/query_log.xml" << 'EOF'
<clickhouse>
    <query_log>
        <database>system</database>
        <table>query_log</table>
    </query_log>
</clickhouse>
EOF

# Transactions need keeper enabled so the sandbox can begin and roll back
# ClickHouse sessions during tests.
cat > "${CONFIG_DIR}/transactions.xml" <<EOF
<clickhouse>
    <allow_experimental_transactions>1</allow_experimental_transactions>
    <keeper_server>
        <tcp_port>${CLICKHOUSE_KEEPER_PORT}</tcp_port>
        <server_id>1</server_id>
        <log_storage_path>${COORDINATION_LOG_DIR}</log_storage_path>
        <snapshot_storage_path>${COORDINATION_SNAPSHOTS_DIR}</snapshot_storage_path>
        <coordination_settings>
            <operation_timeout_ms>10000</operation_timeout_ms>
            <session_timeout_ms>30000</session_timeout_ms>
            <raft_logs_level>information</raft_logs_level>
        </coordination_settings>
        <raft_configuration>
            <server>
                <id>1</id>
                <hostname>127.0.0.1</hostname>
                <port>${CLICKHOUSE_KEEPER_RAFT_PORT}</port>
            </server>
        </raft_configuration>
    </keeper_server>
    <zookeeper>
        <node>
            <host>127.0.0.1</host>
            <port>${CLICKHOUSE_KEEPER_PORT}</port>
        </node>
    </zookeeper>
</clickhouse>
EOF

if curl -sf "${CLICKHOUSE_HTTP_URL}/ping" >/dev/null 2>&1; then
  echo "ClickHouse already running at ${CLICKHOUSE_HTTP_URL}"
  exit 0
fi

if [[ -f "${PID_FILE}" ]]; then
  pid="$(tr -d '[:space:]' < "${PID_FILE}")"
  if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
    for _ in $(seq 1 60); do
      if curl -sf "${CLICKHOUSE_HTTP_URL}/ping" >/dev/null 2>&1; then
        echo "ClickHouse already running at ${CLICKHOUSE_HTTP_URL}"
        exit 0
      fi
      sleep 1
    done

    echo "ClickHouse process ${pid} is running but did not become ready." >&2
    exit 1
  else
    rm -f "${PID_FILE}"
  fi
fi

# Start ClickHouse in background (--daemon flag doesn't pick up config.d correctly).
# Set keep_alive_timeout high enough to cover idle gaps in the Elixir connection
# pool; otherwise the server drops sockets mid-suite and TRUNCATE queries from
# ExUnit `on_exit` handlers fail with `Mint.TransportError: socket closed`.
(
  cd "${CLICKHOUSE_RUNTIME_DIR}"
  TZ=UTC nohup clickhouse server \
    -L "${SERVER_LOG}" \
    -E "${ERROR_LOG}" \
    -P "${PID_FILE}" \
    -- \
    --path="${DATA_DIR}/" \
    --tmp_path="${TMP_DIR}/" \
    --user_files_path="${USER_FILES_DIR}/" \
    --format_schema_path="${FORMAT_SCHEMA_DIR}/" \
    --listen_host=127.0.0.1 \
    --http_port="${CLICKHOUSE_HTTP_PORT}" \
    --tcp_port="${CLICKHOUSE_NATIVE_PORT}" \
    --interserver_http_port="${CLICKHOUSE_INTERSERVER_HTTP_PORT}" \
    --mysql_port="${CLICKHOUSE_MYSQL_PORT}" \
    --postgresql_port="${CLICKHOUSE_POSTGRESQL_PORT}" \
    --keep_alive_timeout=300 \
    >"${STARTUP_LOG}" 2>&1 &
)

for _ in $(seq 1 60); do
  if curl -sf "${CLICKHOUSE_HTTP_URL}/ping" >/dev/null 2>&1; then
    echo "ClickHouse ready at ${CLICKHOUSE_HTTP_URL}"
    exit 0
  fi
  sleep 1
done

echo "ClickHouse failed to start. Check ${STARTUP_LOG} and ${ERROR_LOG} for details." >&2
exit 1
