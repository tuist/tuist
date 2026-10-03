#!/usr/bin/env bash
#MISE description="Run the rack switch fleet tests (bats)"
#
# Everything here runs against a committed transcript taken off a live switch
# and against a fake switch on PATH, so the suite needs no hardware.

set -euo pipefail

root="$(git rev-parse --show-toplevel)"
exec bats "$root/infra/rack-switch-fleet/tests"
