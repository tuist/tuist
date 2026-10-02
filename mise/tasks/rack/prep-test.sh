#!/usr/bin/env bash
#MISE description="Run the rack switch console bring-up tests (bats)"
#
# Everything reachable without a switch on the end of a cable. Console bring-up
# is the first thing that runs at a new site and the step that cannot be retried
# cheaply from another continent, so the parts that can be checked here are.

set -euo pipefail

root="$(git rev-parse --show-toplevel)"
exec bats "$root/infra/rack-switch-prep/tests"
