# Serving-authority qualification fixtures

These fixtures exercise real Kura runtimes. `client.mjs` operates only on an
explicitly selected isolated Kubernetes instance and uses the real controller.
Its fencing tests keep the original HTTP/2 and gRPC sessions: do not reconnect
those channels to turn a stale-channel failure into a pass.

`corpus.mjs` verifies action-cache output digests and every referenced CAS body.
Only idempotent verification reads may reconnect after graceful connection aging
or a bounded transport reset. A gRPC failure remains a failure. Large corpora
should be read by a bounded client pod through the actual cluster Service rather
than through a slow local port-forward.

`fixture.mjs` and `fixture-api.mjs` create disposable local Docker peers and a
TLS ConfigMap simulator for resource, disk-pressure, and complete-process-pause
tests. Their grants are test inputs, not a controller implementation. Never point
this simulator at Kubernetes, edit a real serving ConfigMap to emulate it, or
claim that Docker pause proves physical host power-off. The tmpfs pressure volume
is bounded; never fill the host disk to manufacture ENOSPC.

Run resource comparisons sequentially with the same architecture, host, limits,
load, warmup, and cooldown. Keep workload counts, metric samples, both peers' CPU,
disk, client/peer egress, memory peaks and settled levels. Preserve failures and
measurement noise in the PR evidence. Do not run another local build or load test
during a measured comparison.

`serving_authority_resource_spec.sh` opts into the pause and pressure cases with
`KURA_E2E_AUTHORITY_RESOURCES=1`, `KURA_E2E_AUTHORITY_IMAGE`, and an absolute
`KURA_E2E_AUTHORITY_OUTPUT` directory. `mesh-resource.mjs IMAGE legacy|active DIR`
compares sustained replication and verifies the retained corpus after handover.
Run-specific manifests, keys, logs and results belong in a temporary output
directory, never in the repository. Remove only resources created by the fixture.
