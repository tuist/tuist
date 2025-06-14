#!/bin/bash
# mise description="Install all necessary dependencies"

set -euo pipefail

pnpm install -C docs/
tuist install
