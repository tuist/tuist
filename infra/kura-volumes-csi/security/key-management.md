# Kura wrapping-key custody, rotation and privileged access

## Status and boundaries

The PR adds an OpenBao Transit share provider, a resumable root-rewrap API,
dedicated Kubernetes workload identity and CSI admission policies. The earlier
AWS implementation was never activated and has been removed. **Hosted storage
does not yet use OpenBao.** Managed overlays continue using their existing roots
until a dedicated OpenBao service and the migration gates below are validated.

The October 27, 2026 access review used only metadata. No root key, volume
passphrase, Secret value or backup object was retrieved. No production mutation
was performed. The staging identity could not create ValidatingAdmissionPolicies
or update ClusterRoles. Those objects required the normal deployment workflow.
No durable OpenBao service is configured in this repository. The disposable
staging validation below passed; permanent deployment, operator custody and
matching database recovery validation remain prerequisites.

## Staging admission rollout

The [chart-only deployment](https://github.com/tuist/tuist/actions/runs/40479579902)
completed successfully on October 27. Integration commit
`1457e5a1ef5365a8b26ca9af15be79b392dc9193` starts from staging's deployed
`130e8af72995f9e70dcf50fa3e52690eed5c1fdf`, preserving the newer KVM work.
Server/runtime/controller/CSI and other component images stayed pinned to their
previous values; KMS stayed disabled. The live CSI ClusterRole now has only
read verbs on PVCs; the new `kura` Role grants their updates/events.

A disposable **1 GiB diagnostic, unencrypted LVM** claim on Paris exercised the
real provisioner's node selection, PV creation, mount, write/sync/read, unstage
and deletion under the policies. The marker read back correctly and the PV was
reclaimed through normal CSI deletion. Pod/PVC/PV fixtures were removed. All
**12 existing Kura pods** retained their UID and readiness; CSI stayed **3/3
Ready**. No CSI authorization/capacity errors appeared in the checked ten-minute
log window. This confirms the normal provisioner lifecycle, not live KMS or
another encrypted-data migration. Adversarial rejection cases and policy
compilation were verified on the disposable local API server; the human staging
identity cannot read admission-policy status directly. No privileged test role
was installed on staging.

The source-code rewrap fixes and KMS provider were tested locally; this
chart-only rollout intentionally kept the server on `sha-ef07ca13e38d` and did
not activate those modules. That rollout is historical admission evidence, not
validation of the subsequent OpenBao provider. Its separate staging proof is
recorded below. Persisted account-key migration, durable audit delivery and a
matching database/volume restore remain pending.

## OpenBao staging validation (October 27)

A disposable OpenBao 2.7.1 service was exercised on the actual staging cluster.
The [identity deployment](https://github.com/tuist/tuist/actions/runs/40495934313)
added only a temporary ServiceAccount and narrowly scoped TokenReview
ClusterRole/Binding through the normal deployment identity. It preserved the
deployed chart's KVM/LVM configuration and existing component image pins.
The initial two attempts stopped before applying resources: checkout rejected
an abbreviated SHA, then the staging guard rejected the workflow's
namespace-less Helm preflight. Full-SHA dispatch and a staging-values guard
fixed those fixture issues; production/canary rendering remains refused.

The client used the current staging server runtime (`sha-ef07ca13e38d`) in a
separate Pod with an empty release configuration. It loaded the PR's exact
provider/transport/passphrase source and the production OpenBao configuration
function from commit `fd66359899f6d2723354266106b6e696b1f40352` in a fresh process.
It did not start the web application, connect to the database, mount application
Secrets or change existing tenant keys. This tests the production cryptographic
code in staging, not deployment of a newly built full server image.

The real checks passed:

- Verified TLS over the in-cluster Service, Kubernetes TokenReview login from
  the `tuist-server` identity, and Transit wrap/unwrap. Tenant, version and share
  position substitutions were rejected. Wrong audience and ServiceAccount
  tokens were rejected. The workload could not rotate/reconfigure/export/back
  up keys or encrypt with an unapproved key.
- Transit key rotation selected version 2 for new envelopes while retaining
  decryption of version 1. Sealing OpenBao prevented key derivation; unsealing
  recovered it. Audit records HMAC-protected JWTs and plaintext shares.
- An encrypted Raft snapshot survived deletion of the original OpenBao Pod and
  its entire ephemeral data directory. Restoration into a freshly initialized
  replacement recovered the original key, with the pre-rotation version
  explicitly verified, and decrypted the saved shares.
- The real CSI provisioner allocated a disposable 1 GiB plain LVM claim on
  Paris. Inside it, a 512 MiB LUKS2/XFS file used a passphrase derived by
  `VolumeKeys.volume_passphrase/3` from OpenBao-wrapped fixture shares. A 1 MiB
  random object retained its SHA-256 checksum and the LUKS UUID across manual
  close/reopen, wrapping-key rotation and OpenBao pod-loss recovery.
- Kubelet replaced the actual projected ten-minute token. A fresh in-cluster
  login, saved-share decrypt and LUKS reopen passed after that replacement.
  This sampled refresh check is not a continuous availability measurement.

All fixture Pods, the Service, TLS Secret, source/config ConfigMaps, extra
ServiceAccount and diagnostic PVC were removed. CSI reclaimed the PV. All
**12 existing Kura pods** kept their UIDs and readiness; CSI remained **3/3
Ready**. The [cleanup deployment](https://github.com/tuist/tuist/actions/runs/40497935403)
removed the temporary reviewer ServiceAccount and TokenReview ClusterRole/Binding.
Their absence was verified against the live API. The chart returned to its
pre-fixture tree with the existing image pins preserved.

This was a single-member, disposable service with test-only one-share unseal
custody and a local audit file. It does not establish hosted HA, durable audit
delivery, production operator/unseal custody, or a matching database restore.
The LUKS file was mounted manually on a CSI-provisioned diagnostic LV; the test
did not switch the live CSI key URL or exercise the full encrypted CSI
`NodeStageVolume`/issuance endpoint with OpenBao. Persisted account-key migration
and that full release/CSI cutover remain explicit gates. No production mutation
was performed, and normal staging storage retains its existing roots.

## Custody and dedicated deployment

`server.config.kuraVolumeOpenBao` configures an HTTPS origin, Transit/auth mount,
key name and Kubernetes role on the web server. The dedicated projected token
has audience `openbao.kura.tuist.dev` and expires after one hour. Each operation
reads the current projected token, logs in to OpenBao and uses the returned
short-lived batch token for one encrypt/decrypt request. There are no static
workload tokens, AWS credentials, STS calls or public OIDC discovery dependency.
OpenBao's Kubernetes auth method verifies identity through TokenReview.

Use a stable HTTPS origin and explicit single-segment names. Stored `key_id`
values include origin, Transit mount and key name; changing the configured
origin/mount cannot silently redirect old ciphertext. `decryptKeyNames` allows
older keys in the same backend during migration. Cross-service relocation needs
an explicit migration design; it is not achieved by changing `address`.
The optional `caConfigMap` projects `ca.crt` for private TLS. Peer and hostname
verification remain enabled; HTTP, embedded credentials, URL paths, redirects,
queries and fragments are rejected. This transport bypasses shared HTTP body
telemetry and emits sanitized reason atoms, never tokens or provider bodies.

Configure a derived `aes256-gcm96` Transit key. Every operation supplies both
base64 derivation `context` and `associated_data` with the existing stable
`kura-tenant-key/v1|tenant|version|position` identity. Returned plaintext must be
exactly 32 bytes. Partial configuration, denial, sealed OpenBao or an outage
fails closed; no legacy fallback wraps new shares. Existing legacy records
still decrypt with their named roots until rewrapped. There is no share/token
cache and no key-service call on artifact GET/PUT, only stage/re-stage and key
management. Plaintext shares still exist in the server's memory; BEAM GC is not
secure erasure. OpenBao software keys do not provide an HSM boundary.

Generate a configuration plan without making API calls:

```sh
KURA_OPENBAO_SERVER_NAMESPACE=tuist-staging \
KURA_OPENBAO_ROLE=kura-staging \
KURA_OPENBAO_KEY_NAME=kura-volume-root \
ruby infra/kura-volumes-csi/security/openbao-config.rb
```

Optional `KURA_OPENBAO_TRANSIT_MOUNT`, `KURA_OPENBAO_AUTH_MOUNT` and
`KURA_OPENBAO_DECRYPT_KEY_NAMES` select dedicated mounts and old keys. The plan
sets derived, non-exportable keys with plaintext backup disabled and 90-day
rotation, exact Transit encrypt/decrypt policy paths, an exact namespace and
`tuist-server` service account, the dedicated audience, and five-minute batch
tokens without the default policy. Do not grant the workload key creation,
rotation, export, backup, mount/policy administration or root access. Configure
mounts, keys and roles using a separately authorized operator. Give OpenBao's
own service account TokenReview permission; configure its Kubernetes auth with
its locally rotated reviewer token and cluster CA, not a permanent reviewer JWT.

Before hosted activation:

1. Prepare a dedicated OpenBao deployment separate from the application release.
   Use at least three Raft members across independent nodes, durable storage,
   TLS, controlled network access and a stable endpoint. Do not place its Raft
   storage on encrypted Kura volumes: that creates a circular boot dependency.
   Keep environment keys/auth roles isolated and administrative access separate.
2. Choose and exercise root-of-trust custody. Without an external HSM/KMS,
   Shamir unseal needs operator-held shares after node restart. Distribute a
   threshold across independent custodians; never put every share in one vault
   or a Kubernetes Secret readable by the application cluster. No automated
   unseal script or embedded root token is supplied. A future HSM/auto-unseal
   choice needs its own tested recovery path. Do not claim unattended recovery
   while manual unseal remains required.
3. Declare durable audit devices in the OpenBao server configuration with raw
   logging disabled (the fixture uses `audit "file" "local"`); do not enable
   unsafe API audit-device creation to work around configuration. Protect their
   delivery/storage. Verify authorized login, wrap/unwrap and denied access
   appear, with sensitive values HMAC-protected. Check audit-destination failure
   behavior. A local file audit fixture is not durable hosted delivery.
4. Back up encrypted Raft snapshots outside the application cluster. Keep the
   required unseal custody separate from snapshots. Restore a snapshot onto an
   isolated service, unseal it and decrypt a saved share; then verify the same
   volume passphrase with a matching database recovery point. Test total-cluster
   loss, member replacement, token refresh and operator availability.
5. Enable the provider in staging only after the service is ready and exercise
   a disposable volume. Test expired/wrong-audience/wrong-service-account tokens, removed
   role permissions, sealing/outage and recovery, and real CSI re-stage/checksum
   preservation. Keep legacy root sync during the staged rewrap below. Regional
   LVM enrollment and OpenBao cutover are independent changes.

References: [Transit API](https://openbao.org/docs/api/secret/transit/),
[Kubernetes authentication](https://openbao.org/docs/auth/kubernetes/),
[seal and recovery](https://openbao.org/docs/concepts/seal/).

## Rewrap, retirement and recovery

Root-envelope rotation does not change a tenant share, key version, share order,
LUKS passphrase or data encryption key. It requires no volume rewrite/restart.
This is different from rotating a compromised tenant share or LUKS keyslot; that
workflow is not delivered here. Transit rotation keeps the key name and old
versions available for decryption; the ciphertext's `vault:vN:` prefix records
the version. Rewrap batches encrypt with the latest version even when `key_id`
stays the same. Inventory counts key names, not Transit versions: do not raise
`min_decryption_version`, trim versions or delete a key based on those counts.
Old database backups may still contain envelopes from earlier versions.

1. Take a recoverable database backup and record its recovery point and required
   wrapping-key identifiers. Verify the old key remains recoverable. Store only
   identifiers in the change record, never key material.
2. Deploy provider-capable code everywhere before any OpenBao shares are written.
   Enable the destination wrapper while retaining all source decrypt keys.
   For legacy-to-OpenBao migration retain `kuraVolumeRootKeys.enabled: true` initially.
3. On the release, inspect `Tuist.Kura.VolumeKeys.Rotation.inventory/0`.
   It reports provider, wrapping identifier, active/retired state and counts.
4. Run a single batch pinned to the expected destination, initially with limit 1:

   ```elixir
   target = {"openbao", "https://<stable-openbao-origin>/v1/transit/keys/kura-volume-root"}
   Tuist.Kura.VolumeKeys.Rotation.batch(target, limit: 1)
   ```

   For legacy-root rotation use `{"tuist_root", "<new-root-id>"}` after adding
   that root first. Each operation unwraps, rewraps and verifies the same
   plaintext before committing. An atomic compare-and-swap refuses concurrent
   changes. Remote cryptographic work does not hold a database row lock.
5. Increase the bounded batch size (default 25, maximum 100), passing the
   returned `after_id` into the next call. Persist that non-secret cursor.
   A failure includes the last successful cursor; fix the cause and resume.
   A crash after commit can cause a repeated rewrap, which preserves the key.
   Include retired versions: old volumes still depend on them.
6. Verify inventory has zero references to the old wrapper. Run inventory again
   after every replica has the new configuration, since UUID pagination alone
   does not catch concurrent inserts behind a cursor. Probe new volume creation
   and re-stage an existing disposable replica, preserving a healthy sibling.
   Check stored-object checksums, unchanged LUKS UUID and issuance version.
7. Disable legacy root sync, deploy, and restart **all** consumers of the shared
   server-config Secret (web, migration/processor workloads as applicable).
   Removing a Secret entry does not erase a running process's environment.
   Verify references/rollout completion without printing environments or keys.
8. Keep old roots in restricted offline recovery custody until every backup,
   snapshot, replica, rollback image and exported recovery bundle depending on
   them has expired or been replaced and a restore drill has passed. The observed
   database retention was 30 days, not evidence that all possible copies expire
   at 30 days. Never delete Transit keys or root history automatically from a zero
   live-row count.

For recovery, restore a selected backup into an isolated environment, restore
its matching legacy roots or OpenBao decrypt permissions, and verify a known
volume's derived passphrase through an actual re-stage/checksum probe. Never
connect a restored database to production controllers. A pre-rewrap backup still
requires the old wrapper. Restoring role access, unsealing the service or restoring
a matching Raft snapshot can recover unwraps. Losing Transit key material and
its recoverable backups makes the corresponding volumes unrecoverable.

Rollback after any OpenBao share exists must retain OpenBao-capable code and its decrypt
configuration. To move back to legacy custody, rewrap every row while both
providers work, verify inventory and recovery, and only then disable OpenBao.
Already-open mappings can continue through a key-service outage; new/re-staged
volumes fail closed. Revoking a wrapper does not revoke mounted plaintext.

## CSI boundary and access review

RBAC still lets the distributed provisioner manage cluster-scoped PVs, which
cannot be namespace-scoped. Three fail-closed ValidatingAdmissionPolicies add
field/node restrictions for its exact ServiceAccount:

- PV create/update/delete must reference a Kura claim and the caller's bound
  node. The PV name must match its claim UID, driver and volume handle. Existing
  PV specifications cannot change; finalizer updates remain possible.
- PVC updates are restricted to namespace `kura`, immutable specification and
  ownership fields, and selecting/releasing only the caller's own node.
- Node-status updates can modify only `tuist.dev/kura-disk` capacity on the
  caller's node. CPU/memory, readiness and other status/metadata remain unchanged.

PVC write/event permissions now live in a `kura` Role; snapshot permissions are
removed. The driver retains cluster-wide informer reads needed by the upstream
provisioner. Policies and bindings are retained across rollbacks like the CSI
resources. Install and verify them before claiming the stronger boundary.
Kubernetes 1.34 is the exercised API version. Re-run tests after upgrading the
provisioner or Kubernetes NodeStatus schema.

A privileged node can still read mounted plaintext and identities on that node.
An administrator able to change admission, impersonate identities or deploy as
the web server remains trusted. This is not protection against cluster-admin.

Read-only live findings (staging and production, October 27):

- Both environment vaults list Marek and Pedro with item read/export/history and
  management access. Owners and Administrators groups can manage vault access.
  Both groups have the same two active people; Administrators also lists one
  suspended member. Service-account/Connect access and historical exports were
  not established by this CLI review and need an administrative inventory.
- The current web server references `tuist-tuist-server-config-external-secrets`.
  Human default `view` bindings do not grant Secret read. Staging's standing
  write group and production's elevated write group bind `edit`, which does.
- Many platform identities have namespace-wide or cluster-wide Secret reads:
  ingress, cert-manager, monitoring, external-secrets, CAPI and node identities,
  among others. Root custody is therefore broader than vault membership alone.
  Removing the root from the shared Secret after OpenBao migration is the immediate
  mitigation. Do not revoke unrelated controller permissions without testing
  those controllers' dependencies. Kubernetes data-at-rest encryption was not
  established by this RBAC review.
- Barman ObjectStores use HTTPS Tigris endpoints, separate staging/production
  backup buckets and 30-day retention. Both reported a successful October 27
  backup. Their configuration specifies gzip, not client-side backup encryption.
  Bucket encryption, IAM, object-lock/version retention and actual restore
  success were not verified through these Kubernetes objects. Wrapped tenant
  shares remain encrypted in database backups; backup compromise plus a legacy
  root compromises their confidentiality.

## Reproducible local validation

The 112 focused server tests pass and cover legacy-root rewrap/retirement, old-record recovery,
context/identity binding, target pinning, outage recovery, concurrent-update
refusal, retired versions and bounded resumption. `openbao_integration.rb`
creates a disposable kind cluster and real TLS-enabled OpenBao with Raft,
Kubernetes TokenReview authentication and the generated least-privilege policy.
It exercises the production Elixir provider, rotation, identity/permission
rejections, sealing/recovery, encrypted Raft snapshot restore and HMAC protection
of JWTs and plaintext shares in audit records. Its one-share
unseal and single-member ephemeral storage are test fixtures only. It deletes
its cluster and temporary credentials; it never uses a hosted kubeconfig.
The snapshot is restored into the same disposable service; this is not a
total-cluster-loss, hosted availability or full database/volume restore drill.
The real OpenBao 2.7.1/Kubernetes 1.34 run passes, as do strict Credo on the 11
key modules/tests, the OpenBao Helm checks and managed rack-release isolation.

The prior real Kubernetes 1.34 CSI admission run passed 16 allowed/denied cases
with no policy type-check warnings. Those policies are unchanged by the provider
replacement. Historical CSI tests/vet and managed rack-release checks also passed.

```sh
cd server
mix test test/tuist/kura/volume_keys_test.exs \
  test/tuist/kura/openbao_share_provider_test.exs \
  test/tuist/kura/key_service_http_test.exs \
  test/tuist_web/controllers/internal/kura_volume_keys_controller_test.exs \
  test/tuist/environment_test.exs
```

From the repository root, `ruby infra/kura-volumes-csi/security/helm_test.rb`
checks projected identity, root-secret removal, required OpenBao settings, policy
rendering and namespaced CSI writes. Run the isolated real-provider integration
with `ruby infra/kura-volumes-csi/security/openbao_integration.rb` (Docker, kind,
kubectl, OpenSSL and the installed server toolchain are required). For real
admission evaluation:

```sh
kind create cluster --name kura-key-security --image kindest/node:v1.34.0 \
  --kubeconfig /tmp/kura-key-security.kubeconfig
KURA_SECURITY_KUBECONFIG=/tmp/kura-key-security.kubeconfig \
  ruby infra/kura-volumes-csi/security/admission_test.rb
kind delete cluster --name kura-key-security
```

The admission test deliberately grants its local fixture identity cluster-admin
so admission must independently reject attacks. It refuses other context names
and removes its temporary token file. Never install that test role on staging
or production. Hosted OpenBao activation and recovery/audit drills remain gates; the CSI chart rollout is recorded above.
