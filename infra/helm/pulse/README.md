# Pulse deployment

Standalone chart for [Pulse](../../../pulse/README.md). Public installation and
upgrade instructions live in [the deployment guide](../../../pulse/docs/deployment.md).
The chart is released independently of the Tuist server, alongside its matching
`ghcr.io/tuist/pulse` image at `oci://ghcr.io/tuist/charts/pulse`.

## Managed telemetry instances

`values-managed-{staging,canary,production}.yaml` describe the independent Pulse
release in each cluster's `observability` namespace. Each runs one combined pod
on the general worker pool. Recreate upgrades deliberately trade brief downtime
for avoiding overlapping maintenance fleets. There is no HPA or customer
reconciler. Workload ingress exposes only authenticated, exact `/mcp`,
`/api/v1/write`, `/loki/api/v1/push` and `/v1/traces` paths over TLS. This permits
external NixOS cache ingestion without exposing query, admin or metrics APIs.
Grafana queries remain private over PDC. Do not replace these paths with a prefix.
The managed ingress explicitly permits 4 MiB request bodies, matching Pulse's
receiver limit instead of nginx's smaller default.

The `pulse-release.yml` workflow uses shared `release:check pulse` versioning and
`pulse@<version>` tags, runs the reusable Pulse CI, and publishes matching image
and chart versions before calling `pulse-deployment.yml`. The latter also accepts
a released tag for explicit redeployment or rollback from main. Deployments
cascade staging → canary → production using each `server-k8s-<environment>`
environment and its CI credentials. Each stage waits for ESO, rollout and
internal readiness, then reconciles the separately owned monitoring collectors
from the same release source. Promotion requires an authenticated query to find
real collector telemetry generated after reconciliation. Collectors send to
`pulse.observability.svc.cluster.local:4000`. The server deployment refuses a
collector cutover until standalone Pulse is ready and the legacy writer is stopped.
NIF artifacts are built and attached separately by `pulse-nif-release.yml`.

Automatic Pulse CI and release runs are limited to changes under `pulse/`.
Chart-only and deployment-workflow changes require manual Pulse CI validation
and a `pulse-release.yml` dispatch to publish a new immutable chart/overlay.

### Bootstrap prerequisites

These are desired configuration, **not a record of provisioned resources**:

- Preserve `tuist-pulso-{staging,canary,production}`, tenant prefixes and existing
  bucket-scoped credentials. These historical bucket names are intentional;
  renaming the application must not replace or rewrite acknowledged data.
- In each `onepassword` ClusterSecretStore's vault, provide
  `PULSE_SECRET_KEY_BASE/password`, `PULSE_TOKEN/password`, and
  `PULSE_S3_CREDENTIALS` fields `access_key_id` and `secret_access_key`.
  Preserve the existing values when renaming items. ESO derives the digest-only
  application token map and retains the plaintext token only for Alloy's existing
  Basic-auth contract. Pulse references individual Secret keys, not `envFrom`.
- Management has its own private `tuist-pulse-management` bucket and the same
  three items in **`tuist-k8s-mgmt`**, with bucket-scoped credentials independent
  of workload environments. The separate `infra/flux/mgmt/pulse-management.yaml`
  child installs the pinned standalone chart using explicit inline values matching
  `values-managed-management.yaml`. Missing bootstrap must not block other Flux
  children: the management monitoring workflow keeps Cloud-only collectors until
  the current Pulse Deployment is available and its ExternalSecret is ready.
  After bootstrap, reconcile monitoring and query fresh management samples in
  Pulse before changing any alert datasource. Local storage still cannot monitor
  its own total failure; retain external heartbeat/no-data/error evaluation.
- Pentest is retired in desired state. Verify live retirement instead of creating
  a new cluster or store. Only if the old cluster still needs monitoring, first
  bootstrap private `tuist-pulse-pentest` and the same vault fields in its existing
  store, deploy `values-managed-pentest.yaml`, then reconcile its collector overlay.
  No automatic pentest backend rollout is introduced.
- External NixOS cache hosts need opnix access to the **matching environment's**
  `PULSE_TOKEN/password`, stored Alloy-owned with mode `0400`. Apply the workload
  ingress/backend first, then deploy the host configuration. Never substitute a
  production token on staging/canary. Verify all three signal queues and actual
  stored samples/logs/trace IDs; a successful host rebuild is not delivery proof.
  An Alloy-only nixpkgs input pins version **1.15.1** for both NixOS and Colmena,
  leaving other host packages unchanged. The old 1.11.3 package cannot load the
  existing structured-metadata log stages. Run
  `python3 cache/platform/validate-alloy.py` with Nix and Docker to validate all
  ten host configurations and offline startup using the selected Alloy version.
- Confirm each ESO store is ready, the CI environment has its usual
  `OP_SERVICE_ACCOUNT_TOKEN`, and the general pool has the requested capacity.
- Land the workflows and publish a matching release before deploying. A manual
  production rollout requires explicit approval; configuring it is not running it.
- On the first rename, drain accepted ingestion and recording intents, stop all
  old writers, and resolve Helm resource ownership before starting Pulse. Never
  adopt another release's objects or overlap old/new maintenance fleets. Reconcile
  collectors, Atlas hostnames/audiences and TLS as one coordinated cutover; do not
  treat a successful `/readyz` probe as evidence of production ingestion.

The service is `pulse.observability.svc.cluster.local:4000`. `/healthz` checks liveness;
`/readyz` includes storage readiness. Queries and ingestion require tenant auth.
Pod scrape annotations use the cluster's existing Alloy autodiscovery for
`/metrics`; pod logs use existing cluster collection. No Prometheus Operator is
required. Chart alert rules are available in `files/alerts.json`; provisioning
them in Grafana is a separate reviewed operation. Retention remains observe-only
until a destructive retention policy is explicitly approved.

Secret refresh alone does not restart pods consuming environment variables. After
an intentional credential rotation, restart the workload through an approved
deployment. Rollbacks must respect storage compatibility and the migration
instructions in the deployment guide; a tag is not permission to roll back across
an incompatible storage format.

The deployment safety contract accepts the published `1.39.0` release's exact
MCP-only ingress. Later releases must include all four exact paths and the 4 MiB
body limit. Before rolling back to `1.39.0`, restore external hosts to Cloud-only
export and verify delivery there: its immutable overlay removes public Pulse
ingestion. Once hosts depend on those routes, `1.39.0` is not an end-to-end
rollback target until those senders have been reverted. The workflow does not
verify external host state; this is an operator prerequisite, not an automatic
fallback or a waiver of storage-format compatibility requirements.

Managed staging, canary and production use a 2-second ingest coalescing window
to reduce small segment and manifest writes. This can add up to 2 seconds before
publication starts; acknowledgments still wait for durable publication, so total
latency also includes encoding and object-store requests. The staging setting
does not reduce retention, sample data or change its concurrency/byte bounds.

## Local validation

From the repository root, run `bash infra/helm/pulse/test-managed.sh` with Helm,
yq v4 and jq installed. It renders standalone and managed modes, checks secret
ownership and private single-instance wiring, rejects incomplete ESO settings,
validates the exact MCP/ingest-only ingress, management/pentest private backends,
Flux/overlay equality and checks that managed overlays are excluded
from the published package. The same render safety contract used by deployment
also checks the historical MCP-only exception and rejects later MCP-only
releases, missing body limits and prefix routes.
