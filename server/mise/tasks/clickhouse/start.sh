#!/usr/bin/env bash
#MISE description="Start ClickHouse server"

set -euo pipefail

# Create config.d with query_log enabled and reduced logging (ClickHouse merges this with embedded defaults)
mkdir -p config.d
cat > config.d/server.xml << 'EOF'
<clickhouse>
    <query_log>
        <database>system</database>
        <table>query_log</table>
    </query_log>
    <logger>
        <level>warning</level>
        <console>true</console>
    </logger>
</clickhouse>
EOF

# Start ClickHouse in foreground (pitchfork manages the daemon lifecycle)
# Set keep_alive_timeout to 30 seconds to prevent connection issues
export TZ=UTC
exec clickhouse server -- --keep_alive_timeout=30
