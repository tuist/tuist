# Shadow assignment policy

This package is an experiment in central assignment of queued demand to
already-warm runner VMs. It has no actuator. `controllers/shadow_scheduler.go`
collects observations through `client.Reader`; the server supplies bounded
PostgreSQL demand, active claims and account budgets through a controller-only
endpoint. Never call dispatch, mint credentials, or mutate cluster resources
from this path.

- `policy.go` is deterministic and side-effect free. It consumes explicit time
  and input structs so policies can be replayed without a cluster. Budgets are
  shared across pools within each account/platform. Busy claims override stale
  queue or Pod observations, including GitHub's executed-job remapping.
- Policy version 1 prefers lower dominant usage relative to account limits,
  then queue age, with an oldest-first override after two minutes. This is an
  experimental weighted sharing policy, not a guarantee of fair service or
  bounded waiting under overload. Exact pool, platform and shape must match.
- Cache residency chooses among compatible warm runners only. It is potential
  locality, not a cache-hit prediction or permission to read the cache; fork
  trust and credential checks remain in real dispatch.
- `observer.go` compares the first outstanding proposal for a Pod UID with a
  later claim's account. It does not compare executed job IDs: GitHub chooses
  the matching job. Missed/expired observations and Pod replacement are unknown.
- Bump `Version` when changing policy semantics or the input protocol. Keep
  bounds aligned with `Tuist.Runners.Shadow.Snapshot` and document changes in
  `../../shadow-scheduler.md`.

Run `go test ./...` from `infra/runners-controller`; the bounded-input benchmark
is `go test ./internal/shadow -run '^$' -bench BenchmarkProposeBoundedSnapshot`.
