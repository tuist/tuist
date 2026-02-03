#!/usr/bin/env bash
#MISE description="Start ClickHouse server as daemon"

set -euo pipefail

# Create config.d with query_log enabled (ClickHouse merges this with embedded defaults)
mkdir -p config.d
cat > config.d/query_log.xml << 'EOF'
<clickhouse>
    <query_log>
        <database>system</database>
        <table>query_log</table>
    </query_log>
</clickhouse>
EOF

# Start ClickHouse in background (--daemon flag doesn't pick up config.d correctly)
# Set keep_alive_timeout to 30 seconds to prevent connection issues
TZ=UTC nohup clickhouse server -- --keep_alive_timeout=30 > /dev/null 2>&1 &
