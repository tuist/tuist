#!/usr/bin/env bash
#MISE description="Test the Noora web package"
set -euo pipefail
cd noora
aube run test
