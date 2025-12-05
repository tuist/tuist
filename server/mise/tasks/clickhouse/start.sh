#!/usr/bin/env bash
#MISE description="Start ClickHouse server as daemon"

set -euo pipefail

# Set keep_alive_timeout to 30 seconds to prevent connection issues
# Default is 3 seconds which can cause "socket closed" errors
TZ=UTC clickhouse server --daemon --pidfile=.clickhouse.pid -- --keep_alive_timeout=30
