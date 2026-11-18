# Kura wrapping-key custody, rotation and privileged access

## Status and boundaries

Each tenant share is wrapped by the `tuist_root` provider with an AES-256-GCM
root key. Root keys live in each environment's 1Password vault as item
`KURA_VOLUME_ROOT_KEYS`, field `value`, and reach the web server through
ExternalSecrets when `server.config.kuraVolumeRootKeys.enabled` is set. The value
is a comma-separated list of `<id>:<base64 32-byte key>` entries; the first wraps
new shares and every entry decrypts. Staging, canary and production enable root
sync. Missing or malformed roots fail closed.

The October 27, 2026 access review used only metadata. No root key, volume
passphrase, Secret value or backup object was retrieved. No production mutation
was performed. The staging identity could not create ValidatingAdmissionPolicies
or update ClusterRoles. Those objects required the normal deployment workflow.

## Staging admission rollout

The [chart-only deployment](https://github.com/tuist/tuist/actions/runs/40479579902)
completed successfully on October 27. Integration commit
`1457e5a1ef5365a8b26ca9af15be79b392dc9193` starts from staging's deployed
`130e8af72995f9e70dcf50fa3e52690eed5c1fdf`, preserving the newer KVM work.
Server/runtime/controller/CSI and other component images stayed pinned to their
previous values. The live CSI ClusterRole now has only read verbs on PVCs; the
new `kura` Role grants their updates/events.

A disposable **1 GiB diagnostic, unencrypted LVM** claim on Paris exercised the
real provisioner's node selection, PV creation, mount, write/sync/read, unstage
and deletion under the policies. The marker read back correctly and the PV was
reclaimed through normal CSI deletion. Pod/PVC/PV fixtures were removed. All
**12 existing Kura pods** retained their UID and readiness; CSI stayed **3/3
Ready**. No CSI authorization/capacity errors appeared in the checked ten-minute
log window. This confirms the normal provisioner lifecycle, not an
encrypted-data migration. Adversarial rejection cases and policy compilation
were verified on the disposable local API server; the human staging identity
cannot read admission-policy status directly. No privileged test role was
installed on staging.

## Rewrap, retirement and recovery

Root rotation does not change a tenant share, key version, share order, LUKS
passphrase or data encryption key. It requires no volume rewrite/restart. This
is different from rotating a compromised tenant share or LUKS keyslot; that
workflow is not delivered here.

1. Take a recoverable database backup and record its recovery point and the
   root identifiers it depends on. Verify the old root remains recoverable.
   Store only identifiers in the change record, never key material.
2. Prepend the new root to `KURA_VOLUME_ROOT_KEYS`, keeping every old root, and
   deploy. Wait until every web replica runs with the new configuration.
3. On the release, inspect `Tuist.Kura.VolumeKeys.Rotation.inventory/0`.
   It reports provider, wrapping identifier, active/retired state and counts.
4. Run a single batch pinned to the expected destination, initially with limit 1:

   ```elixir
   Tuist.Kura.VolumeKeys.Rotation.batch({"tuist_root", "<new-root-id>"}, limit: 1)
   ```

   Each operation unwraps, rewraps and verifies the same plaintext before
   committing. An atomic compare-and-swap refuses concurrent changes. The
   cryptographic work does not hold a database row lock.
5. Increase the bounded batch size (default 25, maximum 100), passing the
   returned `after_id` into the next call. Persist that non-secret cursor.
   A failure includes the last successful cursor; fix the cause and resume.
   A crash after commit can cause a repeated rewrap, which preserves the key.
   Include retired versions: old volumes still depend on them.
6. Verify inventory has zero references to the old root. Run inventory again
   after every replica has the new configuration, since UUID pagination alone
   does not catch concurrent inserts behind a cursor. Probe new volume creation
   and re-stage an existing disposable replica, preserving a healthy sibling.
   Check stored-object checksums, unchanged LUKS UUID and issuance version.
7. Remove the old root from the item, deploy, and restart **all** consumers of
   the shared server-config Secret (web, migration/processor workloads as
   applicable). Removing a Secret entry does not erase a running process's
   environment. Verify references/rollout completion without printing
   environments or keys.
8. Keep old roots in restricted offline recovery custody until every backup,
   snapshot, replica, rollback image and exported recovery bundle depending on
   them has expired or been replaced and a restore drill has passed. The observed
   database retention was 30 days, not evidence that all possible copies expire
   at 30 days. Never delete root history automatically from a zero live-row count.

For recovery, restore a selected backup into an isolated environment, restore
its matching roots, and verify a known volume's derived passphrase through an
actual re-stage/checksum probe. Never connect a restored database to production
controllers. A pre-rewrap backup still requires the old root. Losing a root and
its recoverable copies makes the volumes whose shares it wraps unrecoverable.
Already-open mappings continue through a key-service outage; new/re-staged
volumes fail closed. Removing a root does not revoke mounted plaintext.

## Future: external key custody

A root key is exportable: anyone who can read the 1Password item or the
server-config Secret holds it, and volume-key issuance is recorded only in the
server's own logs.
An external key service such as OpenBao Transit would add a non-exportable
root that never leaves the service, revocation by withdrawing the server's
decrypt permission, and an audit record for every unwrap.

Adopting one would require a highly available deployment spanning providers,
automatic unseal, durable audit delivery, encrypted off-cluster backups with a
tested restore, and an owner for its operation. Its storage must not live on
encrypted Kura volumes, which would create a circular boot dependency. It would
likely also cover `SECRET_KEYS/encryption` (`Tuist.Vault`). Stored shares
record their provider, so it would be a new `ShareProvider` and an entry in the
provider table, followed by the rewrap above with the new target. Revisit when a
customer or compliance requirement asks for audited, non-exportable key custody.

## CSI boundary and access review

**Claim/node binding (2026-11-01):** a compromised node plugin could previously
select an unassigned claim for its own node and pre-bind it. The plugin may now
only release a selection of its own node (Kura classes bind
`WaitForFirstConsumer`, so only the scheduler selects), and
`kura-csi-pv-claim-node` evaluates every claim labelled
`app.kubernetes.io/managed-by: kura-controller` in `kura` as a param: a PV may name
one only when its UID matches and the scheduler selected the caller's node. The
API server reads params through an informer, so a selection that just moved can
be observed a few seconds late; a claim without that label is not covered
(the controller's claim templates always carry it). Local kind 1.34 harness
only; not yet installed on a hosted cluster.

**Key-service transport (implemented, not yet deployed):** the key service no
longer trusts the TLS terminators on the public edge. Each fetch mints a
pod-bound token whose only audience is the SHA-256 of that request's X25519 key,
so a terminator replaying the token with its own key fails TokenReview, and a
replay with the original key yields only a response sealed to the plugin. The
response is additionally keyed by a static server X25519 key that the plugin
pins, and the AAD binds volume id and key version, so a terminator cannot forge
or relabel a passphrase. A terminator still sees request metadata (volume ids,
timing) and can deny service. A compromised node plugin can still fetch keys for
volumes pinned to its own node; that boundary is unchanged.

Enabling it per environment requires an operator, in order: generate an X25519
keypair offline; store the base64 private key in the environment vault as item
`KURA_VOLUME_TRANSPORT_KEYS`, field `value`; set
`server.config.kuraVolumeTransportKeys.enabled` and deploy the server; then set
`kuraVolumesCSI.keyServicePublicKey` and explicitly upgrade the CSI digest.
Server and plugin speak only the v2 protocol, so stages fail between the
server deploy and the CSI upgrade; mounted volumes are unaffected. To rotate,
prepend the new private key, deploy, re-pin the plugin, then remove the old key.

RBAC still lets the distributed provisioner manage cluster-scoped PVs, which
cannot be namespace-scoped. Five fail-closed ValidatingAdmissionPolicies (the claim/node policy above and four below) add
field/node restrictions for its exact ServiceAccount:

- PV create/update/delete must reference a Kura claim and the caller's bound
  node. The PV name must match its claim UID, driver and volume handle. Existing
  PV specifications cannot change; finalizer updates remain possible.
- PVC updates are restricted to namespace `kura`, immutable specification and
  ownership fields, and selecting/releasing only the caller's own node.
- Node-status updates can modify only `tuist.dev/kura-disk` capacity on the
  caller's node. CPU/memory, readiness and other status/metadata remain unchanged.
- TokenRequests must be bound to the caller's own pod (name and UID from its
  token), carry exactly one `kura-volume-keys.tuist.dev/v2/<sha256>` audience
  and expire within ten minutes. A namespaced Role grants `create` on only the
  plugin's own `serviceaccounts/token`.

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
  among others. Root custody is therefore broader than vault membership alone;
  see [Future: external key custody](#future-external-key-custody). Do not
  revoke unrelated controller permissions without testing those controllers'
  dependencies. Kubernetes data-at-rest encryption was not
  established by this RBAC review.
- Barman ObjectStores use HTTPS Tigris endpoints, separate staging/production
  backup buckets and 30-day retention. Both reported a successful October 27
  backup. Their configuration specifies gzip, not client-side backup encryption.
  Bucket encryption, IAM, object-lock/version retention and actual restore
  success were not verified through these Kubernetes objects. Wrapped tenant
  shares remain encrypted in database backups; backup compromise plus a
  root compromises their confidentiality.

## Reproducible local validation

The focused server tests cover root rewrap/retirement, old-record recovery,
context/identity binding, target pinning, concurrent-update refusal, retired
versions and bounded resumption.

```sh
cd server
mix test test/tuist/kura/volume_keys_test.exs \
  test/tuist_web/controllers/internal/kura_volume_keys_controller_test.exs \
  test/tuist/environment_test.exs
```

From the repository root, `ruby infra/kura-volumes-csi/security/helm_test.rb`
checks root and transport key sync, policy rendering, key-bound token minting
and namespaced CSI writes. For real admission evaluation:

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
or production.
