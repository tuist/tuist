#!/usr/bin/env bash
#MISE description="Stop ClickHouse server"

set -euo pipefail

if clickhouse client --query "SYSTEM SHUTDOWN" >/dev/null 2>&1; then
  echo "ClickHouse stopped"
else
  echo "ClickHouse is not running"
fi
