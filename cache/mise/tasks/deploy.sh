#!/usr/bin/env bash
#MISE description "Deploy cache with Kamal"
#MISE raw=true
#USAGE arg "<environment>" help="Target environment" {
#USAGE   choices "canary" "staging" "production"
#USAGE }
set -euo pipefail

op run -- kamal deploy -d "${usage_environment?}"
