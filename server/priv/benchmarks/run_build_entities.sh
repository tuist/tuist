#!/usr/bin/env bash
# Starts only its own loopback ClickHouse; never resets another server's cache or database.
set -euo pipefail
cd "$(dirname "$0")/../.."
port="${BUILD_ENTITY_BENCH_PORT:-18233}"
if curl --silent --fail --max-time 2 "http://127.0.0.1:$port/ping" >/dev/null; then
  echo "Port $port is already in use. Choose a free BUILD_ENTITY_BENCH_PORT." >&2
  exit 1
fi
root="$(mktemp -d "${TMPDIR:-/tmp}/tuist-build-entities.XXXXXX")"
mkdir -p "$root/data" "$root/tmp"
# Configuration is entirely local and synthetic. Keep the dataset/results for inspection.
cat > "$root/config.xml" <<EOF
<clickhouse>
  <logger><level>warning</level><log>$root/server.log</log><errorlog>$root/error.log</errorlog></logger>
  <path>$root/data/</path><tmp_path>$root/tmp/</tmp_path>
  <listen_host>127.0.0.1</listen_host><http_port>$port</http_port>
  <tcp_port>0</tcp_port><interserver_http_port>0</interserver_http_port>
  <keep_alive_timeout>300</keep_alive_timeout>
  <profiles><default><log_queries>1</log_queries></default></profiles>
  <users><default><password></password><networks><ip>127.0.0.1</ip></networks><profile>default</profile><quota>default</quota></default></users>
  <quotas><default></default></quotas>
  <query_log><database>system</database><table>query_log</table><flush_interval_milliseconds>1000</flush_interval_milliseconds></query_log>
  <max_server_memory_usage>8589934592</max_server_memory_usage>
</clickhouse>
EOF
binary="$(mise which clickhouse)"
CLICKHOUSE_WATCHDOG_ENABLE=0 "$binary" server --config-file="$root/config.xml" > "$root/startup.log" 2>&1 &
pid=$!
cleanup() {
  # PID reuse must not signal another worktree's process.
  if ps -p "$pid" -o args= | grep -F -- "--config-file=$root/config.xml" >/dev/null; then
    kill -TERM "$pid"
    wait "$pid" || true
  fi
  echo "Benchmark files retained in $root"
}
trap cleanup EXIT INT TERM
for _ in {1..60}; do
  if curl --silent --fail "http://127.0.0.1:$port/ping" >/dev/null; then break; fi
  kill -0 "$pid" || { echo "ClickHouse failed: $root/startup.log" >&2; exit 1; }
  sleep 1
done
curl --silent --fail "http://127.0.0.1:$port/ping" >/dev/null
export BUILD_ENTITY_BENCH_OUTPUT="${BUILD_ENTITY_BENCH_OUTPUT:-$root/results.json}"
export BUILD_ENTITY_BENCH_DATABASE="${BUILD_ENTITY_BENCH_DATABASE:-build_entities_bench_$(date +%s)}"
export TUIST_SERVER_CLICKHOUSE_HTTP_PORT="$port"
export BUILD_ENTITY_BENCH_EXPECTED_PORT="$port"
export TUIST_DEV_DISABLE_CODE_RELOADER=1
export ERL_FLAGS="${ERL_FLAGS:-+S 4:4}"
# No application start: only explicitly isolated repositories are launched.
case "${BUILD_ENTITY_BENCH_MODE:-entities}" in
  entities)
    mise exec -- env MIX_ENV=dev TUIST_SERVER_CLICKHOUSE_HTTP_PORT="$port" mix do deps.loadpaths --no-deps-check + run --no-start priv/benchmarks/build_entities.exs
    ;;
  parents)
    export BUILD_ENTITY_BENCH_NATIVE_OUTPUT="${BUILD_ENTITY_BENCH_NATIVE_OUTPUT:-$BUILD_ENTITY_BENCH_OUTPUT}"
    mise exec -- env MIX_ENV=dev TUIST_SERVER_CLICKHOUSE_HTTP_PORT="$port" mix do deps.loadpaths --no-deps-check + run --no-start -e \
      'Code.require_file("priv/benchmarks/build_entity_native_parents.exs"); BuildEntityNativeParentsBenchmark.standalone()'
    ;;
  once)
    export TUIST_SERVER_TEST_POSTGRES_DB="$BUILD_ENTITY_BENCH_DATABASE"
    export TUIST_SERVER_TEST_CLICKHOUSE_DB="$BUILD_ENTITY_BENCH_DATABASE"
    export BUILD_ENTITY_ONCE_OUTPUT="${BUILD_ENTITY_ONCE_OUTPUT:-$BUILD_ENTITY_BENCH_OUTPUT}"
    mise exec -- env MIX_ENV=test TUIST_SERVER_CLICKHOUSE_HTTP_PORT="$port" TUIST_SERVER_TEST_POSTGRES_DB="$BUILD_ENTITY_BENCH_DATABASE" \
      TUIST_SERVER_TEST_CLICKHOUSE_DB="$BUILD_ENTITY_BENCH_DATABASE" \
      mix do deps.loadpaths --no-deps-check + run --no-start priv/benchmarks/build_entities_once.exs
    ;;
  *) echo "Use BUILD_ENTITY_BENCH_MODE=entities, parents or once" >&2; exit 1 ;;
esac
