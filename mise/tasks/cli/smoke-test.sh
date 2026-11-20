#!/bin/bash
#MISE description="Runs a bundled Tuist CLI on this repository and fails if it does not generate it"
#USAGE arg "<directory>" help="Directory holding the tuist executable next to its ProjectDescription.framework, as bundle.sh lays it out or a release archive extracts"

# A release can link, sign and notarize and still crash at runtime:
# 4.219.0-canary.31 to .34 dropped Swift protocol conformances from the
# statically linked executable and segfaulted generating this repository, while
# small fixtures generated fine. So this generates the repository itself, with
# its external packages, the way a developer here does.

set -uo pipefail

source "$MISE_PROJECT_ROOT/mise/utilities/setup.sh"

DIRECTORY=${1:?"Pass the directory that holds the tuist executable"}
TUIST="$DIRECTORY/tuist"

echo "$(format_subsection "Running $TUIST on $MISE_PROJECT_ROOT")"
"$TUIST" version || exit 1

"$TUIST" generate --no-open --cache-profile none --path "$MISE_PROJECT_ROOT"
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
    if [ "$STATUS" -gt 128 ]; then
        echo "$(format_error "tuist generate crashed with signal $((STATUS - 128)). Do not publish this build.")" >&2
    else
        echo "$(format_error "tuist generate failed with exit status $STATUS. Do not publish this build.")" >&2
    fi
    exit 1
fi
echo "$(format_success "tuist generate succeeded")"
