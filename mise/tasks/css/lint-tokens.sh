#!/usr/bin/env bash
#MISE description="Check that CSS never references a custom property nothing defines"
#USAGE arg "[scope]" help="Limit the check to a single scope: noora or server"
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../../.."

case "${usage_scope:-}" in
  noora) globs=("noora/css/**/*.css") ;;
  server) globs=("server/assets/**/*.css") ;;
  "") globs=("noora/css/**/*.css" "server/assets/**/*.css") ;;
  *)
    echo "Unknown scope \"${usage_scope}\". Expected one of: noora, server" >&2
    exit 2
    ;;
esac

[ -d node_modules/stylelint ] || npm ci --no-audit --no-fund

npx --no-install stylelint "${globs[@]}"
echo "No CSS references an undefined custom property (${usage_scope:-noora, server})"
