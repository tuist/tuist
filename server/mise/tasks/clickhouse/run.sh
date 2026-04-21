#!/usr/bin/env bash
#MISE description="Run ClickHouse in the foreground for Pitchfork"

set -euo pipefail

clickhouse_dir="${TUIST_SERVER_CLICKHOUSE_DIR:-.clickhouse}"
http_port="${TUIST_SERVER_CLICKHOUSE_PORT:-8123}"
tcp_port="${TUIST_SERVER_CLICKHOUSE_TCP_PORT:-9000}"
interserver_http_port="${TUIST_SERVER_CLICKHOUSE_INTERSERVER_HTTP_PORT:-10000}"
mysql_port="${TUIST_SERVER_CLICKHOUSE_MYSQL_PORT:-9004}"
postgresql_port="${TUIST_SERVER_CLICKHOUSE_POSTGRESQL_PORT:-9005}"
prometheus_port="${TUIST_SERVER_CLICKHOUSE_PROMETHEUS_PORT:-9363}"

mkdir -p \
  "${clickhouse_dir}/config.d" \
  "${clickhouse_dir}/data" \
  "${clickhouse_dir}/tmp" \
  "${clickhouse_dir}/user_files" \
  "${clickhouse_dir}/format_schemas" \
  "${clickhouse_dir}/logs"

cat > "${clickhouse_dir}/config.d/tuist-dev.xml" <<EOF
<clickhouse>
    <listen_host>127.0.0.1</listen_host>
    <http_port>${http_port}</http_port>
    <tcp_port>${tcp_port}</tcp_port>
    <interserver_http_port>${interserver_http_port}</interserver_http_port>
    <mysql_port>${mysql_port}</mysql_port>
    <postgresql_port>${postgresql_port}</postgresql_port>
    <prometheus>
        <port>${prometheus_port}</port>
    </prometheus>
    <https_port remove="true" />
    <tcp_port_secure remove="true" />
    <grpc_port remove="true" />
    <query_log>
        <database>system</database>
        <table>query_log</table>
    </query_log>
</clickhouse>
EOF

# Keep everything scoped to this checkout so worktrees do not fight over state or ports.
cd "${clickhouse_dir}"

exec env TZ=UTC CLICKHOUSE_WATCHDOG_ENABLE=0 clickhouse server -- \
  --path="${clickhouse_dir}/data/" \
  --tmp_path="${clickhouse_dir}/tmp/" \
  --user_files_path="${clickhouse_dir}/user_files/" \
  --format_schema_path="${clickhouse_dir}/format_schemas/" \
  --logger.log="${clickhouse_dir}/logs/clickhouse.log" \
  --logger.errorlog="${clickhouse_dir}/logs/clickhouse.err.log" \
  --keep_alive_timeout=300
