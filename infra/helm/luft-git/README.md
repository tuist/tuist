# Luft Git

Standalone, private Git storage in namespace `luft` on `tuist-k8s-production`.
This is infrastructure for a future organization-repository adapter, not that
adapter: installing it neither migrates existing behavior releases nor makes
Git pushes approve or activate them. Luft's PostgreSQL database remains the
source of truth for existing releases, review decisions, permissions and live
business records.

The service, release and credential names describe the capability (`luft-git`),
not its implementation. Enroute remains explicit in operational details below.
The dedicated Tigris bucket is named `luft-git-production`.

Upstream: [Enroute](https://enroute.sh/),
[hosting](https://enroute.sh/docs/operate/hosting),
[security](https://enroute.sh/docs/operate/security),
[limitations](https://enroute.sh/docs/reference/limitations).
The chart pins the v0.4.1 image by its multi-architecture digest, not `latest`.
Enroute is pre-1.0, unaudited, and its API and storage format can change.

## Deployment boundary

- One `both` node with a retained 20 GiB ledger PVC and a dedicated S3
  bucket/prefix. This is the upstream **single-node profile**, not HA. Restarts
  cause downtime; permanent ledger-disk loss can lose acknowledged writes
  that have not yet flushed to S3. S3 alone is not a backup of the ledger.
- Ledger/cache memory settings, disk cache, temporary space, CPU and container
  memory are bounded. Cache limits are not a repository quota: monitor PVC
  usage; logs and repository data still grow. No Kubernetes API token is mounted.
- `luft-git.luft.svc:50051` is an unauthenticated, plaintext gRPC API.
  Anyone reaching it can read, write or delete **all** repositories. The
  mandatory NetworkPolicies allow only the selected Luft server pods in this
  namespace, with the matching narrow egress addition for those callers.
  ClusterIP alone is not a security boundary. Other additive policies, node
  access and the trusted Luft server remain part of the boundary.
- Git binds only to loopback, is not in any Service, and cannot create
  repositories on push. There is no Ingress, public DNS, or external Git
  access. Do not expose it before Luft implements signed authorization hooks.
- Egress allows DNS and public HTTPS for S3. No private object-store endpoints
  or private remote fetches are supported by this policy. Status on port 7400
  is for kubelet probes only; it is not exposed by a Service. Process/listener
  probes do not establish object-store health; exercise an API round trip from
  an authorized caller after rollout and monitor object-store/log errors.
- The release does not roll the Luft server, use its OAuth credentials, or
  access the Tuist product database or secrets. Do not run the Luft server
  deployment workflow to install Enroute.

## Provision before installation

1. Provision a dedicated S3 bucket/prefix for this deployment. Supply its
   nonsecret URI as `bucket.uri`: for AWS,
   `s3://BUCKET/luft-production?region=eu-central-1`; for a compatible provider,
   add its HTTPS `endpoint` query parameter. Never put credentials in the URI.
   Production values point to the dedicated private Tigris bucket
   `luft-git-production` in the `tuist` organization, using
   `https://t3.storage.dev` and signing region `auto`. Saved placement is
   single-region Frankfurt (`fra`), with Standard storage. The bucket and its
   bucket-scoped read/write key have been created, with default organization
   permissions disabled. Actual provider conditional-write semantics still
   need operator verification.
2. Verify **both** conditional create (`If-None-Match: *`) and conditional
   replace (`If-Match`) against the actual provider: mismatches must fail.
   Never disable conditional writes. Enable encryption at rest and abort
   incomplete multipart uploads after one day. Do not apply object expiration
   to Enroute's live prefix. Scope credentials to that bucket/prefix with
   list/read/write/delete and multipart permissions; do not reuse Tuist's keys.
3. A human must save the dedicated key in item **`LUFT_GIT_S3`**, vault
   **`tuist-k8s-production`**, with text fields **`access_key_id`** and
   **`secret_access_key`** (mark the latter as concealed). Do not save the
   credentials in Git, Helm values, or this thread. Production enables the
   chart's `ExternalSecret`: the existing `onepassword` ClusterSecretStore
   extracts that item into Secret `luft-git-s3` in namespace `luft`, mapping
   the fields to `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. Its refresh
   interval is one hour. A deployment/operator identity must install this
   resource: agent elevation does not grant creation of ExternalSecrets.
   Missing Secret/keys fail startup. Agents must not read/create Secrets,
   access 1Password, or print credential values, even with elevation.
   For other installations, leave `externalSecret.enabled=false` and provision
   `bucket.existingSecret` separately. On rotation, sync the ExternalSecret,
   restart StatefulSet `luft-git`, verify an API round trip, then revoke the
   old key. Environment variables do not update when ESO refreshes the Secret.
4. Establish ledger volume backups and a tested restore procedure before
   customer repositories depend on it. A retained PVC survives uninstall; it
   is not a backup or protection from disk failure. Preserve the bucket,
   node identity and ledger together. See upstream
   [maintenance](https://enroute.sh/docs/operate/maintenance).
5. Use the manual **Luft Git Deployment** workflow
   (`.github/workflows/luft-git-deployment.yml`) for the full installation.
   It uses the existing `server-k8s-production` deployment environment and
   its protections, requires execution from main and a full source SHA that
   main contains, and installs only this release. It does not redeploy Luft.
   The workflow must be on main before dispatch; pushing it does not deploy.
   Neither a human's normal Pomerium identity nor thread elevation can create
   the ExternalSecret. Do not retrieve deployment credentials into an orb to
   work around that restriction. Direct production workload changes still
   require human-approved thread elevation per
   [infrastructure guidance](../../AGENTS.md#cluster-access-for-agents).

Once those prerequisites are met, render the production manifests and review
them before an authorized installation:

```sh
helm template luft-git infra/helm/luft-git --namespace luft \
  -f infra/helm/luft-git/values-production.yaml
```

An authorized deployment identity can use `helm upgrade --install` with the
same chart, release, namespace and values and `--wait --timeout 10m`.
The deployment workflow uses `HELM_DRIVER=configmap` for nonsecret release
metadata; subsequent operators must use that same driver. An elevated orb
must not use Helm's default Secret release driver. Never switch drivers on an
existing release. This chart renders no Secret resources; production renders
an ExternalSecret whose controller creates the Secret. An elevated orb cannot
install that resource, so the full production release needs an approved
deployment/operator identity. Signing into the cloud consoles is not cluster
elevation and does not grant agents access to 1Password.

After installation, check StatefulSet readiness, PVC binding, `/status`, and
an API create → commit → read round trip in a uniquely named disposable test
repository. Delete only that test repository, then verify a non-client pod
cannot reach the API and no non-loopback caller can reach Git. Do not use
customer repositories as smoke fixtures. Local rendering cannot establish
CNI enforcement, CSI persistence or real-provider durability.

## Lifecycle and application integration

Single-node replacement must stop the old process before opening the same
ledger. Do not scale this StatefulSet to multiple replicas: a replicated
profile needs distinct ledger identities, peer discovery, network rules and
durable disks, not a replica-count override. The current general pool is in
one availability zone; host spreading would not establish zone resilience.

Before changing the image, read the exact upstream release's storage-format
notes, back up ledger and objects, and rehearse recovery. Upstream supports
neither mixed-version rolling upgrades nor downgrades. An incompatible release
needs a new isolated deployment and repository migration. Do not use Helm
`--atomic`/automatic rollback to restore an old binary over upgraded storage.

Luft must still implement the authorized repository adapter, stable opaque
organization/repository mapping, commit pinning in review records, and explicit
promotion before these repositories can hold active authored definitions.
Never hand Enroute API access or S3 credentials to agents or native clients.
Enroute provides no tenant boundary, quota, or per-caller rate limit inside a
deployment: Luft must enforce these. A repository per organization is a
logical mapping, not storage-level isolation; use separate deployments where
that stronger isolation is required.

Repositories and their historical commits can contain personal attribution and
authored content. Before enabling collection, update the export/deletion
contract in `server/data-export.md` with the actual mapping, retention and
backup handling. Deleting a business record or changing an active release
must not be described as erasing Git history.

## Offline checks

```sh
helm lint infra/helm/luft-git -f infra/helm/luft-git/values-ci.yaml
helm lint infra/helm/luft-git \
  -f infra/helm/luft-git/values-production.yaml \
  -f infra/helm/luft-git/values-ci.yaml
helm template luft-git infra/helm/luft-git --namespace luft \
  -f infra/helm/luft-git/values-production.yaml \
  -f infra/helm/luft-git/values-ci.yaml
python3 infra/helm/luft-git/test-chart.py
```

CI values are deliberately fictitious and must never be used for installation.
