#!/usr/bin/env bash
# mise description="Start ClickHouse server as daemon"

set -euo pipefail

TZ=UTC clickhouse server --daemon --pidfile=server/.clickhouse.pid
