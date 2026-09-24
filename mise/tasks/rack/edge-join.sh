#!/usr/bin/env bash
#MISE description="Join the rack's edge node to the cluster the rack belongs to, for the rack's edge workloads"
#
# kubeadm's join with a one-hour bootstrap token, the node tainted and labelled
# so only the rack's edge workloads run there, and refused until the cluster's
# Cilium agent stays off it.
#
#   mise run rack:edge-join --context <kube context> --dry-run
#   mise run rack:edge-join --context <kube context>
#   mise run rack:edge-join --context <kube context> --leave
#
# See infra/rack-switch-fleet/AGENTS.md.

set -euo pipefail

root="$(git rev-parse --show-toplevel)"
exec "$root/infra/rack-switch-fleet/edge-join.sh" "$@"
