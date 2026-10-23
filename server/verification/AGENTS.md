# Standalone server verification

`cluster_e2e/` and `cluster_scale_out.exs` preserve the earlier integration harness. See [cluster_e2e/AGENTS.md](cluster_e2e/AGENTS.md) for its boundaries. Its historical assertions about immediate cached-subject revocation, distributed image exclusion, discovery-driven disconnects and supervised optional-task draining must be updated before treating it as a gate for the current server. Historical results do not validate this merged branch.

## Cluster formation verification

`cluster_formation.exs` runs in an isolated named VM with owned peers, no server/database startup and no production access. It exercises `RuntimeChildren.cluster/1`, DNS joining and failed-poll retention in a three-node mesh, a rejected wrong-cookie peer, and actual departure. Names are unique and peer listeners are ephemeral. This is not a release/Helm cookie-wiring or fixed-listener test: `test/tuist/application/release_environment_test.exs` separately exercises the actual release shell template, and Helm lint/render checks cover manifest wiring.

Neither check proves authorization, loaded mixed-version rolling replacement, enforced Kubernetes NetworkPolicy or real partition recovery. Run a real two-replica canary before promotion. Retaining peers after DNS failure does not disable OTP partition prevention or prevent disconnects after actual TCP/node loss. Private experiments must touch only owned resources and distinguish reported historical evidence from current inspected results.
