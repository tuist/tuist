#!/usr/bin/env bash
#MISE description="Run the rack node install stick tests (bats)"
#
# Against fake op and curl on PATH, so the suite needs no credentials.

set -euo pipefail

root="$(git rev-parse --show-toplevel)"
exec bats "$root/infra/rack-nodes/tests"
