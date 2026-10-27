# Kura wrapping-key custody, rotation and privileged access

## Status and boundaries

The PR adds an AWS KMS share provider, a resumable root-rewrap API, dedicated
projected workload identity and CSI admission policies. **These changes are not
an assertion that the hosted deployment already uses KMS.** Managed overlays
continue to use their existing roots until the migration gates below pass.

The October 27, 2026 access review used only metadata. No root key, volume
passphrase, Secret value or backup object was retrieved. No production mutation
was performed. AWS provisioning was blocked by an expired `tuist-dns` session;
there was no default AWS identity. The current staging identity cannot create
ValidatingAdmissionPolicies or update ClusterRoles. Those objects require the
normal reviewed deployment workflow. OIDC discovery through that identity was
also forbidden, so public federation readiness remains unverified.

## Custody

`server.config.kuraVolumeKMS` enables a dedicated AWS KMS key ARN and workload
role ARN on the web server. Its projected token has audience `sts.amazonaws.com`
and expires after one hour. Each key operation exchanges that token for a
short-lived STS session. It does not inherit S3 credentials or require a static
AWS access key. The server receives plaintext tenant shares during authorized
unwraps but never receives the KMS wrapping key. It performs no KMS operations
on artifact GET/PUT: the CSI stage/re-stage path fetches volume passphrases.

Only full symmetric-key ARNs in the configured region are accepted. The active
ARN wraps new shares; the explicit decrypt allowlist retains old ARNs during
migration. Partial/invalid KMS configuration and provider outages fail closed,
without falling back to a legacy wrapper for new shares. Legacy ciphertext
continues to use the root named in its record until it is rewrapped.

The KMS encryption context contains `purpose=kura-volume-share` and the existing
stable tenant/version/share-position AAD. It contains no artifact content. KMS
responses must name the expected key and contain exactly 32 plaintext bytes.
The transport uses verified HTTPS with bounded connect/request timeouts and no
redirects. It deliberately bypasses shared ExAws/Finch request-body telemetry;
errors contain only fixed reason atoms. ExAws is used for signing, not transport.
There is no plaintext-share cache in this provider. Server memory remains in the
trusted boundary; BEAM garbage collection is not guaranteed secure erasure.

Generate reviewable IAM policies with `kms-policies.rb`, setting the six named
`KURA_*` inputs listed in that script. Use a separate key and workload role per
environment. Create a symmetric `AWS_KMS` origin key; enable 90-day automatic
material rotation. Keep the key on infrastructure-stack deletion. The workload
gets only Encrypt/Decrypt with the required context, while a separate operator
role administers the key. Review existing account policies and grants too:
these generated policies alone cannot prove there are no additional grants.

Before enabling the chart:

1. Verify the cluster token's issuer has public HTTPS discovery and JWKS which
   AWS can fetch. Never expose the Kubernetes API or private signing keys to
   achieve discovery. Verify issuer/signing-key rotation and retain overlapping
   public keys until old tokens expire. Changing a cluster's issuer needs its
   own reviewed platform rollout; do not silently change it with this PR.
2. Register that issuer in IAM and restrict trust to the exact environment's
   `system:serviceaccount:<namespace>:tuist-server` and STS audience. Use the
   rendered ServiceAccount name if an installation overrides chart naming.
3. Create the dedicated role before installing a key policy that names it.
   Verify the runtime role cannot change policy, create grants, disable/delete
   the key, or access another environment's key. Keep key-admin access separate.
4. Verify durable CloudTrail management-event delivery includes KMS (it can be
   excluded). Retention/access protections must be checked on the actual trail.
   Produce one authorized wrap/unwrap and one denied wrong-context operation;
   verify principal, key ARN and AAD in the events without recording plaintext.
5. Exercise token refresh, KMS denial/outage and re-stage recovery on a disposable
   staging volume. Record latency and availability; local mocks do not validate
   IAM, public discovery, network reachability or CloudTrail delivery.

AWS references: [encryption context](https://docs.aws.amazon.com/kms/latest/developerguide/encrypt_context.html),
[CloudTrail](https://docs.aws.amazon.com/kms/latest/developerguide/logging-using-cloudtrail.html),
[OIDC prerequisites](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html).

## Rewrap, retirement and recovery

Root-envelope rotation does not change a tenant share, key version, share order,
LUKS passphrase or data encryption key. It requires no volume rewrite/restart.
This is different from rotating a compromised tenant share or LUKS keyslot; that
workflow is not delivered here. Automatic KMS material rotation keeps the ARN
and old material for decryption; moving to a different ARN requires rewrap.
See [AWS rotation semantics](https://docs.aws.amazon.com/kms/latest/developerguide/rotate-keys.html).

1. Take a recoverable database backup and record its recovery point and required
   wrapping-key identifiers. Verify the old key remains recoverable. Store only
   identifiers in the change record, never key material.
2. Deploy provider-capable code everywhere before any KMS shares are written.
   Enable the destination wrapper while retaining all source decrypt keys.
   For legacy-to-KMS migration retain `kuraVolumeRootKeys.enabled: true` initially.
3. On the release, inspect `Tuist.Kura.VolumeKeys.Rotation.inventory/0`.
   It reports provider, wrapping identifier, active/retired state and counts.
4. Run a single batch pinned to the expected destination, initially with limit 1:

   ```elixir
   target = {"aws_kms", "<the exact new key ARN>"}
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
   at 30 days. Never delete KMS keys or root history automatically from a zero
   live-row count.

For recovery, restore a selected backup into an isolated environment, restore
its matching legacy roots or KMS decrypt permissions, and verify a known
volume's derived passphrase through an actual re-stage/checksum probe. Never
connect a restored database to production controllers. A pre-rewrap backup still
requires the old wrapper. Re-enabling a disabled KMS key/repairing IAM can restore
unwraps; deleting a KMS key cannot be undone after its deletion window.

Rollback after any KMS share exists must retain KMS-capable code and its decrypt
configuration. To move back to legacy custody, rewrap every row while both
providers work, verify inventory and recovery, and only then disable KMS.
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
  Removing the root from the shared Secret after KMS migration is the immediate
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

The focused ExUnit run passed 106 tests against the unchanged lockfile. The
real Kubernetes 1.34 admission run passed 16 allowed/denied cases with no policy
type-check warnings. The isolated Helm render checks, CSI Go tests/vet, and managed rack-release isolation checks passed. Strict Credo found no issues in the 11 key modules/tests. The suites cover legacy-root rewrap/retirement, restoring an old key
record with its old root, KMS migration/outage recovery with a cryptographic
stand-in, concurrent-update refusal, target pinning, retired versions, bounded
resumption, ARN/context/identity validation and existing issuance authorization.
These tests do not constitute a live KMS or full database restore drill.

```sh
cd server
mix test test/tuist/kura/volume_keys_test.exs \
  test/tuist/kura/aws_kms_share_provider_test.exs \
  test/tuist/kura/kms_http_test.exs \
  test/tuist_web/controllers/internal/kura_volume_keys_controller_test.exs \
  test/tuist/environment_test.exs
```

From the repository root, `ruby infra/kura-volumes-csi/security/helm_test.rb`
checks projected identity, root-secret removal, required KMS settings, policy
rendering and namespaced CSI writes. For real admission evaluation:

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
or production. Hosted activation and the AWS recovery/audit drill remain gates.
