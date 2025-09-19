#!/usr/bin/env bash
#MISE description="Edit the .env file"

set -eo pipefail

SOPS_AGE_KEY_FILE=~/.config/mise/tuist-age.txt sops edit .env.json
