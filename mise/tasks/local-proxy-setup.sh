#!/usr/bin/env bash
#MISE description="Register this clone with a local reverse proxy for hostname routing"

set -euo pipefail

if [[ -z "${TUIST_SERVER_HOSTNAME:-}" || -z "${TUIST_SERVER_PORT:-}" ]]; then
  echo "Error: TUIST_SERVER_HOSTNAME or TUIST_SERVER_PORT not set." >&2
  exit 1
fi

CADDY_SITES_DIR="${HOME}/.config/caddy/sites"
CADDY_MAIN="${HOME}/.config/caddy/Caddyfile"
CADDY_SITE_FILE="${CADDY_SITES_DIR}/${TUIST_SERVER_HOSTNAME%.localhost}.caddy"

mkdir -p "${CADDY_SITES_DIR}"

# Ensure main Caddyfile exists with global log config and import directive
CADDY_LOG_FILE="${HOME}/.config/caddy/caddy.log"
CADDY_MAIN_EXPECTED="$(cat <<EOF
{
	log {
		output file ${CADDY_LOG_FILE}
		level ERROR
	}
}

import ${CADDY_SITES_DIR}/*
EOF
)"
if [[ ! -f "${CADDY_MAIN}" ]] || ! grep -qF "output file" "${CADDY_MAIN}"; then
  printf '%s\n' "${CADDY_MAIN_EXPECTED}" > "${CADDY_MAIN}"
fi

# Write per-project site config (idempotent)
CADDY_EXPECTED="$(printf 'http://%s {\n\treverse_proxy localhost:%s\n}\n' "${TUIST_SERVER_HOSTNAME}" "${TUIST_SERVER_PORT}")"
if [[ ! -f "${CADDY_SITE_FILE}" ]] || [[ "$(cat "${CADDY_SITE_FILE}")" != "${CADDY_EXPECTED}" ]]; then
  printf '%s\n' "${CADDY_EXPECTED}" > "${CADDY_SITE_FILE}"
  echo "Wrote Caddy config: ${CADDY_SITE_FILE}"
else
  echo "Caddy config already up to date."
fi

# Add to /etc/hosts if missing
if ! grep -qE "127\.0\.0\.1[[:space:]].*${TUIST_SERVER_HOSTNAME}" /etc/hosts 2>/dev/null; then
  echo "Adding ${TUIST_SERVER_HOSTNAME} to /etc/hosts (may require your password)..."
  sudo -p "Password to update /etc/hosts: " sh -c "printf '127.0.0.1 %s\n' '${TUIST_SERVER_HOSTNAME}' >> /etc/hosts" || {
    echo "Failed. Run manually: sudo sh -c \"echo '127.0.0.1 ${TUIST_SERVER_HOSTNAME}' >> /etc/hosts\"" >&2
    exit 1
  }
else
  echo "/etc/hosts already contains ${TUIST_SERVER_HOSTNAME}."
fi

# Start or reload Caddy
if caddy status --config "${CADDY_MAIN}" 2>/dev/null | grep -q "Running"; then
  caddy reload --config "${CADDY_MAIN}"
  echo "Caddy reloaded."
else
  caddy start --config "${CADDY_MAIN}"
  echo "Caddy started."
fi

echo ""
echo "http://${TUIST_SERVER_HOSTNAME} -> localhost:${TUIST_SERVER_PORT}"
