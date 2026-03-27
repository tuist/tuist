#!/usr/bin/env bash
#MISE description="Test the Noora web package"
set -euo pipefail
pnpm -C noora run test
