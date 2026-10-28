#!/usr/bin/env bash
set -euo pipefail

[[ $# = 2 ]] || { echo 'Usage: prepare.sh <Once Atlas.app> <new Atlas.app>' >&2; exit 2; }
bash "$(dirname "$0")/prepare-app.sh" "$1" "$2"
bash "$(dirname "$0")/validate.sh" "$2"
