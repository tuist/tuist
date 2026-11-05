# Pulse deployment

Standalone chart for [Pulse](../../../pulse/README.md). Public installation and
upgrade instructions live in [the deployment guide](../../../pulse/docs/deployment.md).
The chart is released independently of the Tuist server, alongside its matching
`ghcr.io/tuist/pulse` image at `oci://ghcr.io/tuist/charts/pulse`.

## Managed production instance

`values-managed-production.yaml` describes the initial private instance in the
Tuist production cluster, namespace/release `pulse`. It runs one combined pod on
the general worker pool. Recreate upgrades deliberately trade brief downtime for
avoiding overlapping maintenance fleets. No HPA, customer reconciler, public
ingress, or existing collector destination is enabled or changed.

The `pulse-release.yml` workflow uses shared `release:check pulse` versioning and
`pulse@<version>` tags, runs the reusable Pulse CI, and publishes matching image
and chart versions before calling `pulse-deployment.yml`. The latter also accepts
a released tag for explicit redeployment or rollback from main. It uses the
standard `server-k8s-production` environment and CI deployment credentials, waits
for ESO, rollout and internal readiness, and serializes Pulse deployments.
NIF artifacts are built and attached separately by `pulse-nif-release.yml`.

### Bootstrap prerequisites

These are desired configuration, **not a record of provisioned resources**:

- Create a dedicated `pulse-production` Tigris bucket with conditional-write
  support and bucket-scoped list/read/write/delete credentials. Never rename or
  silently replace a running installation's bucket.
- In the production `onepassword` ClusterSecretStore's vault, provision
  `pulse-secret-key-base/password` (at least 64 random characters),
  `pulse-tenant-tokens/password` (JSON tenant → `sha256$<digest>` map, never raw
  bearer tokens), and `pulse-object-storage` fields `username` (access key) and
  `credential` (secret key). The ExternalSecret produces `pulse-app`.
- Confirm the production ESO store is ready, the CI environment has its usual
  `OP_SERVICE_ACCOUNT_TOKEN`, and the general pool has the requested capacity.
- Land the workflows and publish a matching release before deploying. A manual
  production rollout requires explicit approval; configuring it is not running it.

The service is `pulse.pulse.svc.cluster.local:4000`. `/healthz` checks liveness;
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

## Local validation

From the repository root, run `bash infra/helm/pulse/test-managed.sh` with Helm,
yq v4 and jq installed. It renders standalone and managed modes, checks secret
ownership and private single-instance wiring, rejects incomplete ESO settings,
and checks that managed overlays are excluded from the published package.
