# Helm Charts

This node covers Helm assets under `infra/helm/`.

## Scope
- Umbrella and component charts for deploying Tuist services on Kubernetes
- Values for embedded vs external infrastructure dependencies
- Kubernetes manifests and helper templates for app services, data services, and observability
- Standalone app charts with their own release boundary, such as Noora Storybook and Slack

## Conventions
- Prefer one umbrella chart that models deployable capabilities, not implementation brands.
- When a workload needs an independent workflow and release cadence, give it its own chart
  rather than adding it to `helm/tuist/`.
- Model infrastructure dependencies with capability names such as `objectStorage`, not provider names such as `minio`.
- Support both `embedded` and `external` dependency modes when practical.
- Keep local validation simple: `helm template` first, then a small-cluster install path such as `kind`.
- Managed PgBouncer client limits and idle cleanup live in `tuist/values-managed-common.yaml`. Keep the connection lifecycle and rollout validation in [`../cnpg/README.md`](../cnpg/README.md#client-connections-through-tailscale) aligned when changing them.
- Grafana-managed alert queries and their operational rationale live in
  `k8s-monitoring/alerts.md`. Keep that runbook aligned with live rule changes;
  browser LCP p99 also requires distinct affected sessions, not just total samples.
- When filtering metrics, preserve every side of absence-based alerts. The
  macOS PN VLAN check needs both `node_load1` and VLAN transmit series in
  non-production; keeping only liveness falsely reports a missing interface.
- Kura metrics use `instance=<namespace>/<pod>` at the metrics destination so
  pod IP changes do not multiply series. Preserve the cluster label and the
  unready scrape's `ready="false"` label when changing either scrape path.
- Managed Kura analytics are enabled by `kuraController.analytics.enabled`.
  `tuist/templates/kura-analytics-external-secret.yaml` sends the server's
  internal address and existing webhook signing key to the shared runtime
  Secret. Keep its key source and trimming aligned with the server config.
  Receiving Bazel build events alone does not enable analytics delivery.

## Related Context
- Parent infra context: `infra/AGENTS.md`
- Noora Storybook chart: `infra/helm/noora-storybook/AGENTS.md`
- Slack chart: `infra/helm/slack/AGENTS.md`
- Server runtime dependencies: `server/AGENTS.md`
- Cache runtime dependencies: `cache/AGENTS.md`
- Processor runtime dependencies: `processor/AGENTS.md`
