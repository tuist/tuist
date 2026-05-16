#!/usr/bin/env bash
#MISE description="Bootstrap a freshly-ordered bare-metal vm-image-builder Mac mini"

# Wraps infra/vm-image-builder-bootstrap. See infra/vm-image-builder.md
# for the operator runbook (Scaleway order, IAM SSH key registration,
# the M2-L SKU, etc.). Forward all flags through to the Go binary.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}/infra/vm-image-builder-bootstrap"

exec go run . "$@"
