# Helm Charts

This node covers Helm assets under `infra/helm/`.

## Scope
- Umbrella and component charts for deploying Tuist services on Kubernetes
- Values for embedded vs external infrastructure dependencies
- Kubernetes manifests and helper templates for app services, data services, and observability
- Atlas standalone and managed deployment: see `atlas/AGENTS.md`.
- Standalone app charts with their own release boundary, such as Noora Storybook and Slack

## Conventions

- `capi.vultrPrivateNetwork` declares regional networks; the CAPI controller owns
  provider IDs and creation intent in a retained `-state` ConfigMap. Keep that
  state out of Helm-owned data. Production enables Chicago and Santiago; Santiago
  has one host, so physical host-pair validation is still required when a second
  host arrives. Reciprocal `canonicalPeers` region names
  approve canonical mTLS between exact VPC IDs resolved by the controller. Stage
  this policy on existing runtimes before qualifying another region; same-VPC
  traffic remains private-only. Self-hosted defaults stay off.

- `capi.ovhPrivateNetwork` declares the environment's provisioned vRack and
  reserved CIDR. `kuraController.privateReplication` consumes Node route
  attestations; both default off for self-hosting. Address reservations are
  controller-owned and must not be placed in Helm-owned data or garbage-collected
  with a Machine. See `../kura-controller/private-network-provisioning.md`.
  Managed staging, canary and production enable both settings for their own
  provisioned OVH vRack. Runtime publication still waits for matching host route
  attestations; this does not enable topology for other providers.

- Production public EU-West runs on three `ovhFleets.eu-west` nodes. Managed
  Dedibox support is removed after all Machine release finalizers completed
  on September 28, 2026: no fleet values, templates, provider implementation,
  CRD sources, credentials wiring, or provider permissions remain. Helm does
  not prune installed CRDs or the legacy IAM ExternalSecret hook; both require
  explicit post-deployment cleanup. Follow [the cleanup runbook](../kura-controller/eu-west-ovh-migration.md#post-retirement-cleanup).
  Production EU-West ingress discovers OVH gateway Node addresses automatically.
  Preserve the `kura-dedibox` selector and `scw-local-nvme` StorageClass because
  OVH uses both. Public staging/canary validation uses OVH `ca-east`; retain the
  separate Scaleway Elastic Metal Mac runner cache (`kuraFleet`) and Mac fleets.
- Stable cache DNS infrastructure is enabled in managed staging, canary, and production. Canary advertises and hands out stable endpoints once ready; staging and production require the `kura_stable_hostname` account/global feature flag, absent by default, with no server environment rollout toggles or account allowlist. Keep environment owner IDs and vault credentials separate. Certificate readiness is an operator bootstrap check, not a routine deployment gate; see `../cache-dns/README.md`.
- `pomerium/templates/access-tiers.yaml` extends the shared `view` tier with `get`/`list`/`watch` on `dnsendpoints.externaldns.k8s.io` in all namespaces. Keep DNS inspection in this read tier, scoped to that resource; DNS mutation and Secret access are not part of this grant. The Pomerium deployment workflow applies this chart to staging, canary, and production on merge.
- OVH Machine repairs use `patch ovhdedicatedmachines` in the directly bound
  `tuist-fleet-unwedge` role. Do not aggregate it into `edit` or extend it to
  templates, status, create, update or delete. RBAC does not restrict fields;
  scope each repair to the diagnosed drift (for example, backfilling a live
  Machine's `egressBudgetMbps` from its reviewed OnDelete fleet template).
  Staging has standing write access; canary/production require human elevation.
- Kura archival defaults to hourly sweeps with a 24-hour never-used Air window. Canary inherits the hourly default; staging keeps its five-minute sweep override for lifecycle drills.
- Prefer one umbrella chart that models deployable capabilities, not implementation brands.
- When a workload needs an independent workflow and release cadence, give it its own chart
  rather than adding it to `helm/tuist/`.
- Model infrastructure dependencies with capability names such as `objectStorage`, not provider names such as `minio`.
- Support both `embedded` and `external` dependency modes when practical.
- Embedded object storage uses the same digest-pinned `ghcr.io/coollabsio/minio` community image for the server and bundled `mc` initializer because the upstream Quay images no longer allow anonymous pulls. Keep both image pins aligned and validate changes with `helm:k3s-smoke`; managed environments use external storage.
- Keep local validation simple: `helm template` first, then a small-cluster install path such as `kind`.
- The K3s smoke task builds its MinIO/mc image from checksum-pinned upstream
  release binaries and imports it into the disposable cluster. Existing-context
  runs must preload that image; the smoke values never pull it from a registry.
- Managed PgBouncer client limits and idle cleanup live in `tuist/values-managed-common.yaml`. Keep the connection lifecycle and rollout validation in [`../cnpg/README.md`](../cnpg/README.md#client-connections-through-tailscale) aligned when changing them.
- Grafana-managed alert queries and their operational rationale live in
  `k8s-monitoring/alerts.md`. Keep that runbook aligned with live rule changes;
  browser LCP p99 also requires distinct affected sessions, not just total samples.
- `k8s-monitoring/kura-availability-alert-rules.json` reflects the enabled rule,
  provisioned separately from Helm. Its zero-ready-replica expression and routing
  are exercised by `test-kura-availability-alert.sh` using Bash, jq, promtool and amtool.
  Keep unavailable service separate from the 30-minute redundancy warning.
- Browser RUM gateway rollout has two phases: deploy gateway-capable server pods first, then enable `server.faro.gateway.enabled` to switch the dedicated collector Ingress backend and remove its rewrite. New rules in `k8s-monitoring/browser-rum-alert-rules.json` stay paused until coverage and per-surface baselines are validated; see `k8s-monitoring/browser-rum.md`.
- The managed production overlay enables the browser RUM gateway; the chart default remains disabled. Roll back by disabling that production override, restoring the direct Alloy backend and `/collect` rewrite.
- When filtering metrics, preserve every side of absence-based alerts. The
  macOS PN VLAN check needs both `node_load1` and VLAN transmit series in
  non-production; keeping only liveness falsely reports a missing interface.
- Keep `tuist_repo_*` counters and duration sums in non-production so the same
  database pool and mean-query-timing checks work for server and processors.
  Histogram buckets remain production-only.
- Kura metrics use `instance=<namespace>/<pod>` at the metrics destination so
  pod IP changes do not multiply series. Preserve the cluster label and the
  unready scrape's `ready="false"` label when changing either scrape path.
- Managed Kura analytics are enabled by `kuraController.analytics.enabled`.
  `tuist/templates/kura-analytics-external-secret.yaml` sends the server's
  internal address and existing webhook signing key to the shared runtime
  Secret. Keep its key source and trimming aligned with the server config.
  Receiving Bazel build events alone does not enable analytics delivery.

## Related Context
- Experimental Kura serving-authority flag defaults off. The additive CRD,
  per-instance ConfigMap-read role, sticky runtime/controller rollback floor and
  quarantined-volume reaper exclusion belong together; see
  [`../kura-controller/serving-authority.md`](../kura-controller/serving-authority.md).
- Parent infra context: `infra/AGENTS.md`
- Noora Storybook chart: `infra/helm/noora-storybook/AGENTS.md`
- Slack chart: `infra/helm/slack/AGENTS.md`
- Server runtime dependencies: `server/AGENTS.md`
- Cache runtime dependencies: `cache/AGENTS.md`
- Processor runtime dependencies: `processor/AGENTS.md`

- Runner Kura uses `platform`'s `kura-runners` ingress-nginx DaemonSet with the shared streaming config. Keep direct-source enforcement (forwarded headers, real IP and PROXY protocol disabled), HTTP/gRPC source allowlists, and disabled ingress status publication together. Private DNS comes from the controller DNSEndpoint. Managed Tuist values enable the namespace-scoped gateway readiness read role. `kuraFleet.replicas` counts hosts; the catalog configures two process replicas per account. See `infra/kura-controller/private-runner-rollouts.md`.

- The Once events listener (`once.events.v1`, gRPC on the server's port 4001) is served by `platform`'s `grpc-ingress-nginx` controller (`nginx-grpc` class), and its hosts are DNS-only with a cert-manager certificate. Do not move it to the main `nginx` class or turn Cloudflare proxying back on. The main controller keeps upstream keepalive off for the Bandit backends, which makes ingress-nginx send `Connection: close` upstream. HTTP/2 forbids that header, and Cowboy resets the stream with PROTOCOL_ERROR (nginx logs `upstream rejected request with error 1`). Cloudflare answers gRPC to a proxied host with a 403. To check a change, send a gRPC-shaped request (`content-type: application/grpc`) to the host: a healthy listener answers HTTP 200 with a `grpc-status` header.

- Private gateway-backed Kura pods carry `tuist.dev/host-network-gateway=true`. `tuist/templates/kura-gateway-network-policy.yaml` allows TCP 4000 from Cilium host/remote-node identities, including cross-host proxying; Kubernetes namespace/ipBlock selectors do not cover this hop. Keep it gated by `kuraController.privateGateway.enabled` with the gateway read permission so self-hosted installs do not require Cilium.

- Stable cache DNS is disabled by default: platform `cacheDNS` owns the CRD-only AWS external-dns and Route53 ACME solver; `kuraController.stableDNS` supplies read/health-check credentials separately. Cloudflare excludes `cache.tuist.dev`. Preserve independent owners and Secrets, and see `../cache-dns/README.md` before enabling.
  Staging enables the provider plumbing and shared cache wildcard for spec 95
  validation. Select `kura-spec95-e2e` and the temporary `kura-spec95-health`
  fixture through FunWithFlags actor gates before deploying the removal of the
  old staging environment allowlist if those fixtures must remain active.

- Linux cache volumes require a bounded reflink filesystem. The
  node agent uses local loop-mounted images and the existing macOS object-storage
  infrastructure; no Ceph Secret or pool values remain. Managed production opts
  into idempotent host provisioning through a privileged init container; other
  installs can supply a pre-provisioned filesystem. The init container enters the
  host mount namespace and installs the persistent systemd mount before agent
  readiness. It never reformats existing images or replaces another mount.
  See `../runners-controller/cache-volumes.md`.
- Staging custom-volume smoke validation uses the preallocated XFS mount at
  `/var/lib/kubelet/tuist-runner-cache` on its Linux runner's data partition;
  the root partition is too small for the default 200 GB backing file. Keep
  its agent image aligned with the controller release and retain the mount while any
  private branches are live. Production enables provisioning and resolves the
  agent image from the matching controller release through normal deployment.
  Keep `tuist/values-ci.yaml` supplied with a controller image tag so static
  production rendering exercises the cache-volume agent's shared-tag fallback.

- macOS custom volumes retain automatic built-in Tuist/CAS caches. They reuse the
  shared runner-cache lifecycle with an APFS backend; rollout and compatibility
  are documented in `infra/tart-kubelet/custom-cache-volumes.md` at repository root.
  Canary and production enable them fleet-wide after the platform-index
  enablement migration. Self-hosting and staging stay off by default; staging's
  40 GiB cache quota cannot fit the built-in reservation and custom admission floor.
- Cache-volume agents expose phase/source/result telemetry on a separate port
  9091. Allow scraping only from `observability`, retain the series in staging,
  and keep runner acquisition on 8090 under its existing pod selector.

- Multiple server replicas require `server.cluster.enabled`. Web pods share a release-scoped Erlang cookie Secret, use a fixed distribution port, and discover pod addresses through the headless service. Preserve the cookie on upgrades or supply `cookieExistingSecret`; restrict distribution traffic to server pods. See `tuist/README.md` for checks and rotation.

- `tuist/values-cluster-ci.yaml` validates two self-hosted web nodes with private distribution traffic and custom port/cookie keys. The Helm workflow lints and schema-validates this profile alongside production.
