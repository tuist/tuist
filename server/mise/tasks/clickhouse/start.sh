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
ACCESS_CONTROL_DIR="${DATA_DIR}/access"
COORDINATION_DIR="${DATA_DIR}/coordination"
COORDINATION_LOG_DIR="${COORDINATION_DIR}/log"
COORDINATION_SNAPSHOTS_DIR="${COORDINATION_DIR}/snapshots"
TMP_DIR="${CLICKHOUSE_RUNTIME_DIR}/tmp"
USER_FILES_DIR="${CLICKHOUSE_RUNTIME_DIR}/user_files"
FORMAT_SCHEMA_DIR="${CLICKHOUSE_RUNTIME_DIR}/format_schemas"
LOG_DIR="${CLICKHOUSE_RUNTIME_DIR}/log"
PID_FILE="${CLICKHOUSE_RUNTIME_DIR}/clickhouse.pid"
LOCK_FILE="${CLICKHOUSE_RUNTIME_DIR}/start.lock"
STARTUP_LOG="${LOG_DIR}/startup.log"
SERVER_LOG="${LOG_DIR}/server.log"
ERROR_LOG="${LOG_DIR}/error.log"
STARTUP_LOG_MAX_BYTES=4194304

mkdir -p \
  "${CONFIG_DIR}" \
  "${DATA_DIR}" \
  "${ACCESS_CONTROL_DIR}" \
  "${COORDINATION_LOG_DIR}" \
  "${COORDINATION_SNAPSHOTS_DIR}" \
  "${TMP_DIR}" \
  "${USER_FILES_DIR}" \
  "${FORMAT_SCHEMA_DIR}" \
  "${LOG_DIR}"

# Bound the server's own log files. The embedded defaults log at `trace` with no
# rotation, which writes ~8MB/minute and grows server.log until the disk is full.
# Once a log write fails the Poco channel stays in a permanent error state: every
# subsequent log call throws, and each throw is reported on stderr, which turns
# the redirect below into a multi-GB-per-hour firehose that keeps the disk full.
cat > "${CONFIG_DIR}/logger.xml" << 'EOF'
<clickhouse>
    <logger>
        <level>information</level>
        <size>50M</size>
        <count>2</count>
        <console>0</console>
    </logger>
</clickhouse>
EOF

# Create config.d with query_log enabled (ClickHouse merges this with embedded defaults)
cat > "${CONFIG_DIR}/query_log.xml" << 'EOF'
<clickhouse>
    <query_log>
        <database>system</database>
        <table>query_log</table>
    </query_log>
</clickhouse>
EOF

# ClickHouse Keeper is the built-in coordination service (the ZooKeeper
# replacement). Transactions need it enabled so the sandbox can begin and roll
# back ClickHouse sessions during tests.
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

# `enter = { task = "clickhouse:start" }` fires on every shell that enters the
# directory, so several invocations can reach the checks below at once and each
# spawn a server against the same data directory. Serialise them: whoever loses
# the race waits and then takes the "already running" fast path.
# The lock is published by hard-linking a file that already holds the owner's
# pid, so it is never observable in a half-written state: a waiter that reads it
# always sees a pid it can test for liveness, and only reclaims the lock when
# that pid is gone.
LOCK_OWNER_FILE="${LOCK_FILE}.$$"
printf '%s\n' "$$" > "${LOCK_OWNER_FILE}"
# shellcheck disable=SC2064
trap "rm -f '${LOCK_OWNER_FILE}'" EXIT

lock_acquired=0
for _ in $(seq 1 90); do
  if ln "${LOCK_OWNER_FILE}" "${LOCK_FILE}" 2>/dev/null; then
    # shellcheck disable=SC2064
    trap "rm -f '${LOCK_FILE}' '${LOCK_OWNER_FILE}'" EXIT
    lock_acquired=1
    break
  fi

  lock_pid="$(tr -d '[:space:]' < "${LOCK_FILE}" 2>/dev/null || true)"
  if [[ -n "${lock_pid}" ]] && ! kill -0 "${lock_pid}" >/dev/null 2>&1; then
    rm -f "${LOCK_FILE}"
    continue
  fi

  sleep 1
done

if [[ "${lock_acquired}" -eq 0 ]]; then
  echo "Timed out waiting for another ClickHouse start to finish (${LOCK_FILE})." >&2
  exit 1
fi

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

# stdout/stderr only carries output from before the logger is up (config parse
# failures, port conflicts), so `head` keeps the first STARTUP_LOG_MAX_BYTES and
# `cat` drains the rest into /dev/null. Draining rather than closing the pipe is
# what keeps the cap safe: the server never blocks on a full pipe, and the log
# cannot grow past the cap no matter how much the server writes. The group's own
# stdout and stderr go to /dev/null so it holds no descriptor from the caller;
# otherwise it keeps the task's output pipe open for the server's whole lifetime
# and whoever reads that pipe never sees EOF.
#
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
    --access_control_path="${ACCESS_CONTROL_DIR}/" \
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
    2>&1 | (
      trap '' HUP
      head -c "${STARTUP_LOG_MAX_BYTES}" > "${STARTUP_LOG}"
      exec cat
    ) >/dev/null 2>&1 &
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
