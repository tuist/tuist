# Guarded management replacements

Extracted from #14511, adapted to current main. These are access/controller
replacements, not warm runner-image waves. Source image pins are candidates,
not evidence that their embedded verifier implements all twelve policy keys.

`guard.sh` reads only workload metadata and images through kubectl and jq.
Malformed responses and access errors fail closed even with `--acknowledged`.
Acknowledgement records a human's completed qualification; it grants no cluster
access and does not perform that qualification. Unchanged image sets need no
acknowledgement. Missing workloads still need qualification: absence can mean
the legacy management Deployment has not migrated yet, not a fresh install.

## Management Tailscale

The target is **DaemonSet/tailscale in mgmt-tailscale**, not the obsolete
mgmt-system Deployment. Preserve per-node state/hostname, KubePrism API access,
host networking and RollingUpdate maxUnavailable=1/maxSurge=0. Do not restore
the old singleton/Recreate topology.

Before a human dispatches `mgmt-cluster-apply.yml` on main with
`management_access_qualified=true`, qualify an independent management access
path and patched rollback, per-node identity retention, OAuth join, KubePrism
state access and recovery while one node's Tailscale is unavailable. Verify the
candidate image's trust behavior separately. A Ready DaemonSet is not TLS proof.
The separate Kubernetes operator and its generated proxy images are **not**
upgraded here: supported operator/proxy version skew and actual ingress/egress
behavior require their own explicit gate before those components are changed.

Merging changes invokes the existing management apply workflow. A differing or
absent DaemonSet blocks its apply job before mutation until a qualified manual
dispatch. The workflow's earlier Hetzner/Talos reconciliation jobs are unchanged.
Once the serving image set matches, ordinary main pushes proceed again. No
workflow or cluster operation was run to qualify the candidate in this PR.

Offline checks: `GOWORK=off go test -run TestReplacementGuard -count=1 ./...`
from this directory, plus management shell/workflow tests. They use fake kubectl
responses and never read credentials, install trust or change a cluster.
