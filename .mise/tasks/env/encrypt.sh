#!/usr/bin/env bash
#MISE description="Encrypts the .env file"
#USAGE arg "<env>" default="dev"

set -eo pipefail

# Check if the environment is "dev"
if [ "$usage_env" = "dev" ]; then
    # Use the existing dev public key
    sops encrypt -i --age "age1ejsmlc8yz6vtf0x765d7kt486dukwlvfx2pkaxrk07f6qtge6cmsclam80" .env.$usage_env
else
    # Fail the script for non-dev environments
    echo "Error: Encryption is only supported for 'dev' environment."
    echo "Current environment: $usage_env"
    exit 1
fi