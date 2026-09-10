# Regional gateway benchmark

Bounded operational experiment for staging, independent of the Kura runtime.
See `README.md` for the placement controls, cleanup procedure, and limits.

- Keep all payload traffic in cluster; never benchmark through kubectl port-forward.
- Compare identical TLS/proxy settings on the local and remote paths.
- Keep HTTP/1 and h2c upstream connection pools separate.
- Preserve unique labels, internal-only Services, restrictive NetworkPolicy,
  ephemeral storage, explicit resource caps, and automatic cleanup.
- Use the adjacent gRPC throughput client's pinned Go module for `client.go`.
- The client can also verify a deployed staging ingress with `-ca ''` (system
  trust) and `-token-file` containing a scoped temporary cache credential. Keep
  tokens out of command-line arguments, output and committed artifacts.
- Do not interpret cloud-worker overlay measurements as dedicated private-network
  capacity or extrapolate small-concurrency proxy memory to fleet-wide load.
- Keep failed preliminary runs distinct from completed measurement sets.
- For sustained comparisons, balance path order, reverse backend placement,
  retain per-case TCP/CPU counters, and report paired differences. Preserve the
  temporary backend reset and bounded upload fixtures. Document keepalive
  overrides separately from production connection-recycling behavior.
