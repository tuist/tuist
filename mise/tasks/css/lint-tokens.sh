#!/usr/bin/env bash
#MISE description="Check that CSS never references a custom property nothing defines"
#USAGE arg "[scope]" help="Limit the check to a single scope: noora or server"
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
node mise/utilities/css_tokens_lint.mjs . ${usage_scope:-}
