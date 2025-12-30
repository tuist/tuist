#!/usr/bin/env bash
#MISE description="Start ClickHouse server as daemon"

set -euo pipefail

kill $(cat .clickhouse.pid) || echo "ClickHouse is not running"
