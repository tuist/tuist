#!/usr/bin/env bash
#MISE description="Start ClickHouse server as daemon"

set -euo pipefail

TZ=UTC clickhouse server --daemon --pidfile=.clickhouse.pid
