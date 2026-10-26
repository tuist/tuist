# Helm Charts

This node covers Helm assets under `infra/helm/`.

## Scope
- Umbrella and component charts for deploying Tuist services on Kubernetes
- Values for embedded vs external infrastructure dependencies
- Kubernetes manifests and helper templates for app services, data services, and observability
- Atlas standalone and managed deployment: see `atlas/AGENTS.md`.
- Standalone app charts with their own release boundary, such as Noora Storybook and Slack

Monitoring cost controls must preserve metric identity and operator audit records.
See `k8s-monitoring/README.md` for the staged Kura and API-server migrations.
Helm CI starts the production Alloy log pipeline to compile LogQL selectors and
runs the mixed-version latency expression through promtool.

## Conventions

- `kuraVolumesCSI` deploys the `kura-volumes.tuist.dev` CSI driver
  (`templates/kura-volumes-csi.yaml`, see `../kura-volumes-csi/AGENTS.md`) and
  the `kura-encrypted-nvme` StorageClass. Its node plugin runs on the pools
  `tuist.kuraCachePools` lists, the same list the quota exporter uses, and
  never on rack nodes. The `kura-volumes` namespace and the
  `kura-volumes-csi-node` ServiceAccount are fixed: the server's key endpoint
  authorizes by that TokenReview username. `kuraVolumesCSI.image.tag` pins a
  `sha-` build (set by the deploy workflows) and is required. An account's
  instances move onto the class only under the `:kura_encrypted_volumes`
  feature flag. Volume keys are wrapped by the
  root keys `server.config.kuraVolumeRootKeys.enabled` syncs from the env's
  `KURA_VOLUME_ROOT_KEYS` 1Password item (`value`); canary and production
  issue no keys without it.

- Xcode 27.1 RC retirement requires the additive stable chart already deployed
  and a published versioned runner image containing stable. Keep 26.6 as the
  default. Follow the prerequisites, rollback floor and required
  post-rollout reconciliation in
  [the retirement runbook](../runner-image/xcode-27.1-retirement.md).

- Production sizes warm floors by demand: only a warm runner claims a job in
  under 10 s, and a pool without one starts every job cold (scale-up plus VM
  boot, 10 to 75 s), while a floor on an image without jobs holds a slot
  other images' bursts wait for. Images with a job in most weekday working
  hours keep one: on the BER1 rack 27.0 keeps two and 26.6, 26.3 and 26.0.1
  one (`rackFleet.runners.xcodeOverrides`, default 0); on the rented fleet
  27.0 keeps two and the default image 26.6 one (`runnersFleet.xcodeOverrides`).
  Re-measure from `tuist.runner_jobs` before changing them.
  The 12 vCPU shape pools stay at 0, because an idle one holds a whole host.
  Staging and canary run one lent rack host with two slots: staging warms
  26.6 and 27.1, and canary keeps its slots free for the runners acceptance
  probe. How warm runners give way to queued jobs is in
  `../runners-controller/AGENTS.md` ("Fleet-capacity awareness").

- RunnerPool names (`<release>-runner-pool-macos-[<site>-]<xcode-dashes>[-<shape>]`)
  are identifiers: they are `fleet_name` in Postgres and ClickHouse, the
  dispatch key, and what alerts and dashboards select on. Customers see the
  GitHub runner name instead, which the server mints per job as
  `tuist-macos-<guest macOS>-xcode-<xcode>-<shape>-<hex>` from the pool's
  `tuist.dev/xcode-version` label and the version the guest reports. Change
  that name in `server/lib/tuist/runners.ex`, not by renaming pools, and keep
  the label on every catalog pool. Pools without it (the explicit `pools`
  entries) keep their Pod name as the runner name.

- `server.config.originAppKey.enabled` adds the registered Origin App ID and Ed25519 private PEM to the managed server-config ExternalSecret. Trim only the App ID, never the private PEM or log key material. It defaults off and is enabled in production, canary, and staging after each environment's own `ORIGIN_APP/app_id` and `ORIGIN_APP/private_key` fields exist in its `tuist-k8s-<env>` vault. The App ID field is configurable with `appIdField`. Each environment uses an independent app and signing key.

- Production enables the Kura authority controller independently of instance
  activation. Keep it enabled once any instance has a serving rollback floor;
  disabling it expires live grants. See
  [serving authority](../kura-controller/serving-authority.md).

- `capi.vultrPrivateNetwork` declares regional networks; the CAPI controller owns
  provider IDs and creation intent in a retained `-state` ConfigMap. Keep that
  state out of Helm-owned data. Production enables Chicago and Santiago; Santiago
  has two enrolled hosts with bidirectional physical private-path and isolated
  replication validation. See the qualification limits in
  `../kura-controller/vultr-private-networking.md`. Reciprocal `canonicalPeers`
  region names
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
- Production's `node.cluster.x-k8s.io/pool: processor` nodes are untainted and have no memory beyond what the processor's rollout surge needs. Pin other production workloads, in any chart, to `node.cluster.x-k8s.io/pool: general` with a `nodeSelector`. A workload left unpinned can land there and deadlock the processor rollout, and helm then rolls back the whole release. The general pool's limit is CPU requests, not memory: keep one node with room for the server's 1-CPU surge pod, and resize `md-0` in `k8s/clusters/workloads/production/cluster.yaml` rather than squeezing that out.
- Deploys wait on the tuist, k8s-monitoring and platform releases (Helm 4's
  kstatus wait: a DaemonSet is ready only when every pod it wants is). Nothing
  in them may run a pod on a rack node, which can be dark for days: rack-node
  workloads go in `rack-nodes` or `rack-cache-gateways`, installed with
  `--wait=hookOnly` from the tuist and platform charts' values. Run
  `mise -C infra run helm:rack-independence` after adding a DaemonSet or
  tolerations; the Helm workflow runs it too. See "Deploys and the rack's
  health" in `../rack-nodes/AGENTS.md`.
- The xcresult processor is not in the waited tuist release either. Managed
  values set `xcresultProcessor.ownRelease`, and `xcresult-processor/` renders
  the tuist chart's processor templates (symlinked, with `tuistRelease` naming
  the tuist release) as the `tuist-xcresult-processor` release, installed with
  `--wait=hookOnly` and reported by a non-gating `kubectl rollout status`.
  A new template the processor needs has to be symlinked into that chart too.
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
  ClickHouse read-failure and latency rules aggregate Cloud and shadow physical
  repos; expanding telemetry coverage can surface previously invisible failures
  without any threshold change.
- `k8s-monitoring/kura-availability-alert-rules.json` reflects the enabled rule,
  provisioned separately from Helm. Its zero-ready-replica expression and routing
  are exercised by `test-kura-availability-alert.sh` using Bash, jq, promtool and amtool.
  Keep unavailable service separate from the 30-minute redundancy warning, and keep
  the ten-minute StatefulSet age gate: single-replica instances start at zero Ready.
- `k8s-monitoring/runner-cache-volume-alert-rules.json` records the live
  **Runner cache volumes** group (four Loki rules and one Postgres rule,
  five-minute evaluation), provisioned separately from Helm; `alerts.md` holds
  the backtests. The warm-rate rule reads the production database as
  `tuist_grafana_ro`, so its columns are in `Tuist.Release`'s Grafana grant
  allowlist. The Loki rules read host logs because `tuist_runner_cache_volume_operations_total` undercounts:
  its `sum:counter` Adaptive Metrics rule (2026-10-22) makes it rate-able, but
  both agents create series on first increment, so isolated failures vanish. Keep the macOS
  queries line-filtered and the windows short: that stream carries the runner
  logs and each evaluation scans the whole window.
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
- Preserve the dotted REAPI binary metadata header through Kura ingress: the shared regional/runner config and dedicated gRPC activation controller require `ignore-invalid-headers: "false"`. Leave the main web ingress unchanged. `infra/kura-controller/controllers/reapi_metadata_ingress_test.go` checks environment overlays and, with `TUIST_TEST_NGINX`, real HTTP/2 `grpc_pass` forwarding. Successful artifact transfers without attribution do not establish analytics delivery; verify fresh signed events by project/invocation after the normal platform rollout. Previously skipped events cannot be reconstructed from client observations.
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

- macOS custom volumes reuse the shared runner-cache lifecycle with an APFS
  backend; rollout and compatibility are documented in `infra/tart-kubelet/custom-cache-volumes.md` at repository root.
  Canary and production enable them fleet-wide after the platform-index
  enablement migration. Self-hosting and staging stay off by default; staging's
  40 GiB cache quota cannot fit the built-in reservation and custom admission floor.
  Production M4 replacement hosts have a 512 GiB shared cache quota; M2 stays
  at 80 GiB. Existing APFS quotas are immutable under bootstrap and the fleet
  uses OnDelete: deploy the host free-space guard before replacing drained M4s.
- Cache-volume agents expose phase/source/result telemetry on a separate port
  9091. Allow scraping only from `observability`, retain the series in staging,
  and keep runner acquisition on 8090 under its existing pod selector.

- `tuist.kuraActivation` is a disabled-by-default, stateless wildcard fallback. Enable exactly one global owner; the matching platform `cacheDNS.activationIngressClass` opt-in reads `nginx-grpc` ingress status for Route53 wildcard DNS. Both activation protocols must use the same dedicated ingress/load balancer; main nginx sends an HTTP/2-forbidden Connection header. The production overlay enables the gateway on the general worker pool; other environments keep it off. Production alone enables wildcard DNS sourcing after pinned production transport validation; other environments remain off. Regional latency records and their withdrawal barriers stay controller-owned. See `../kura-controller/activation.md` before rollout.

## Replica-safety rollout

Keep the chart-facing [server scaling guide](tuist/README.md#scaling-the-server) aligned with the cookie, private networking and membership-verification contracts below.

Cluster formation requires a stable shared cookie Secret, a fixed distribution listener, allowed EPMD/distribution ingress, and a headless service. More than one server replica requires clustering. Managed canary runs two replicas so actual membership is exercised before production promotion. Do not promote until the proof-cache and authoritative authentication rollouts are stable and OAuth entity operations no longer depend on replicated invalidations. Boruta's cache and membership supervision still starts; the entity callbacks, not that lifecycle, are disabled. The stable private cookie connects different image versions during rolling upgrades; the first migration from image-baked cookies still creates old/new islands. Qualify PubSub, Oban PG notifications and peer replacement across the actual versions. Offline/GitOps renderers without live Secret lookup must use a separately managed `cookieExistingSecret`; a missing key in an existing generated Secret fails rather than silently rotating it. Managed staging/canary/production configure `server.cluster.externalSecret` with `cookieExistingSecret: tuist-server-cluster-cookie`: the dedicated ESO resource reads `SERVER_CLUSTER_COOKIE/password` from each environment's own 1Password vault, never the shared server-config Secret. It renders only when clustering is enabled, uses `refreshPolicy: OnChange` so source edits alone do not propagate on a timer, and requires an explicit sync during coordinated rotation; self-host defaults require no ESO. Missing/empty source data must not trigger cookie generation. `test-cluster-cookie.py` checks ownership, all three environment overlays, web-only references and invalid configurations in Helm CI. Bootstrap, rebuild and coordinated rotation are documented in [onboarding](../k8s/onboarding.md#5e-durable-server-distribution-cookies). Cookie rotation requires coordinated process replacement. The chart guard rejects previously accepted unclustered multi-web configurations because live PubSub/PG notifications must cross replicas; it is not a runtime replica-count detector. See the [self-host clustering upgrade guidance](../../server/priv/docs/en/guides/server/self-host/server.md#multi-replica-clustering).
