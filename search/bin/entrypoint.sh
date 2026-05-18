#!/bin/bash
# Entrypoint for the search container.
# Starts TypeSense and installs a cron job that runs all indexers daily at 04:00 UTC.
set -euo pipefail

# Install cron job for periodic indexing if the API key is available
if [ -n "${TYPESENSE_API_KEY:-}" ]; then
  cat > /etc/cron.d/docsearch-indexer << CRON
TYPESENSE_API_KEY=${TYPESENSE_API_KEY}
TYPESENSE_HOST=http://localhost:8108
GITHUB_TOKEN=${GITHUB_TOKEN:-}
0 4 * * * root /opt/docsearch/run-indexers.sh >> /var/log/docsearch-indexer.log 2>&1
CRON
  chmod 644 /etc/cron.d/docsearch-indexer

  # Start cron daemon in the background
  cron
fi

# Ensure data directory exists
mkdir -p "${TYPESENSE_DATA_DIR:-/data}"

# Start TypeSense (exec replaces shell so signals propagate correctly)
exec /opt/typesense-server "$@"
