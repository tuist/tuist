# Offline scheduling simulation

This is a discrete-event experiment, not a production scheduler. It has no
network, database, credential, Kubernetes or deployment access. The CLI is
`cmd/simulate-scheduling`; the readout is `../../scheduling-simulation.md`.

- `engine.go` models the existing per-runner dispatch rule and directly calls
  `assignment.Propose` for the alternative policy. Preserve the distinction between
  a port of current dispatch and execution of the retained pure experimental Go
  function in `assignment/` (see its
  [boundary](assignment/AGENTS.md)). There is no production collector or endpoint.
- Compare policies on identical jobs, capacity, quotas, cache initialization,
  and paired poll phases. Never expose future runtimes to the policy adapters.
- Keep transport comparisons separate from fairness/global placement changes.
  The former production observer's 30-second sampling interval is not a proposed
  execution cadence; central decision/delivery delay is an explicit assumption.
- Fixed slots, recycle delays, cache costs and synthetic arrivals are model
  inputs. Do not claim this simulates Kubernetes packing, autoscaling, provider
  job remapping, claim races, eviction, or production performance.
- When dispatch semantics change, update the modeled baseline and its boundary
  tests against `server/lib/tuist/runners.ex` and
  `server/lib/tuist/runners/volume_affinities.ex`. In particular, live macOS
  affinity understands repository masters as well as account masters.
- Require conservation of jobs, slot capacity, both budget dimensions, and
  queue-time attribution. Failing or unfinished scenarios must report errors.

Run `go test ./internal/simulation` and
`go run ./cmd/simulate-scheduling -seeds 30`. Use `-export-scenarios` and `-json`
to retain inputs and per-job results, or `-scenarios` to load a bounded trace.
