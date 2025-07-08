#!/usr/bin/env bash
# mise description="Edit the .env file"
#USAGE arg "<env>" default="dev"

set -eo pipefail

SOPS_AGE_KEY_FILE=~/.config/mise/tuist-server-$usage_env-age.txt sops edit .env.$usage_env.json
