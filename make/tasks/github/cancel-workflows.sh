#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../../utilities/root_dir.sh)

OWNER=tuist
REPO=tuist

if [[ -n "$GITHUB_TOKEN" ]]; then
    TOKEN="$GITHUB_TOKEN"
else
    TOKEN=$(echo "url=https://github.com" | git credential fill | grep password | cut -d '=' -f 2)
fi

echo $TOKEN

workflow_ids=$(curl -s -H "Authorization: token $TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    https://api.github.com/repos/$OWNER/$REPO/actions/runs \
    | jq '.workflow_runs[] | select(.status == "queued") | .id')

for id in $workflow_ids; do
    echo "Canceling workflow run with ID $id"
    curl -s -X POST -H "Authorization: token $TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        https://api.github.com/repos/$OWNER/$REPO/actions/runs/$id/cancel
done