#!/usr/bin/env bash
#MISE description="Deploys the documentation website."

set -euo pipefail

pnpm run deploy
