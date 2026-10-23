# Cluster formation verification

Standalone scripts in this directory are included in the server's normal formatter and Credo checks. Keep them compliant with the same style rules as application code; declarations such as aliases belong at module scope. Static checks do not execute these probes or qualify their runtime behavior.

`cluster_formation.exs` runs in an isolated named VM with owned peers, no server/database startup and no production access. It exercises `RuntimeChildren.cluster/1`, DNS joining and failed-poll retention in a three-node mesh, a rejected wrong-cookie peer, and actual departure. Names are unique and peer listeners are ephemeral. This is not a release/Helm cookie-wiring or fixed-listener test: `test/tuist/application/release_environment_test.exs` separately exercises the actual release shell template, and Helm lint/render checks cover manifest wiring.

Neither check proves authorization, loaded mixed-version rolling replacement, enforced Kubernetes NetworkPolicy or real partition recovery. Run a real two-replica canary before promotion. Retaining peers after DNS failure does not disable OTP partition prevention or prevent disconnects after actual TCP/node loss. Private experiments must touch only owned resources and distinguish reported historical evidence from current inspected results.
