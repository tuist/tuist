#!/bin/bash
#MISE description="Install all necessary dependencies"

set -eo pipefail

pnpm install --ignore-workspace
