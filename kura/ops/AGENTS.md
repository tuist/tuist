# Operations

This node covers operational assets under `kura/ops/`.

## Key Boundaries
- `helm/kura/` - Kubernetes packaging and rollout adapter for the Kura StatefulSet
- `rollout/` - Transport-agnostic rollout gate helpers that operate on Kura HTTP endpoints and metrics
- `prometheus/`, `loki/`, `promtail/`, `tempo/` - Local observability stack configuration

## Maintenance Notes
- `peerTopology` in the standalone chart is opt-in and requires peer TLS. A
  private pod address is not proof of a private underlay; follow the provider
  qualification gates in `infra/kura-controller/private-replication.md` first.
- Keep rollout policy generic at the `ops/rollout/` layer. Platform-specific orchestration belongs in leaf adapters such as `ops/helm/kura/`.
- When runtime readiness, drain, or metrics semantics change, update both the generic rollout helpers and any platform adapters that consume them.
- Keep Helm lifecycle defaults aligned with runtime shutdown configuration, but do not introduce Kubernetes-specific assumptions into the core Rust service.
