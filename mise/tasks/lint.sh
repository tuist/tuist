#!/usr/bin/env bash
set -euo pipefail

# Lint all components of the project
mise run cli:lint "$@"