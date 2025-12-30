#!/usr/bin/env bash
#MISE description="Encrypts the .env file"

set -eo pipefail

sops encrypt -i --age "age1rjkec7xhu4tcesxsgvhm9px95zd0hj7l0zrl5m9saxeugfkm7v7s9aw65j" .env.json
