#!/usr/bin/env bash
#MISE description "Deploy processor with Kamal"
#MISE raw=true
#USAGE arg "<environment>" help="Target environment" {
#USAGE   choices "staging" "canary" "production"
#USAGE }
set -euo pipefail

kamal app stop -d "${usage_environment?}" 2>/dev/null || true
kamal deploy -d "${usage_environment?}"
