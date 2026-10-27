# Linux shard artifact storage

This independently released chart runs Garage on OVH hosts in Gravelines,
reached over the private vRack by OVH Linux runners. Start with one node per
environment: this is a transfer optimization with rebuildable artifacts, not
an authoritative storage service. Three-node replication remains an optional
future topology, not a prerequisite for the initial rollout.
It is disabled by default. It stores disposable Mix `_build` archives and Cargo
nextest archives; losing the volume requires rerunning the build job. It does
not store the authoritative shard plan or change Xcode artifact routing.

The `scw-local-nvme` provisioner enforces the configured PVC with an XFS project
quota (200 GiB by default, 3 TiB in the production overlay). The pod requests
the same amount of `ephemeral-storage` for scheduler
accounting and carries `tuist.dev/region` for Kura capacity admission. Install
in `kura`, where that admission reads region reservations. Admission uses the
current pressure threshold; installing Garage consumes existing capacity.
Check existing region and node headroom before installation. Do not
reduce the PVC or change its storage class to work around a full node.

Garage uses path-style S3 on a ClusterIP at port 3900. Singleton RPC binds to
loopback. Replicated stores allow RPC on 3901 only between their own pods and
DNS to CoreDNS; a separate headless Service publishes peer addresses even before
readiness. The admin health listener is not exposed by a Service or NetworkPolicy.
Fresh environment overlays apply **three-day archive expiration** and one-day
incomplete multipart abortion through S3 lifecycle. This applies only to this
store's disposable Mix/Cargo archives: shard plans, test results, Xcode artifacts,
and default/Tigris storage keep their existing retention. Server cleanup still
runs under the account's normal policy and safely deletes already-expired
prefixes. The shorter local archive lifetime takes precedence over that policy.

The three-day window is measured from object creation, not the end of a test run.
It allows ordinary queue delays and retries, but does not lease artifacts to
active jobs: a consumer delayed beyond the window must rerun the build. Old plan
metadata can still be queried and can yield a signed URL whose object has expired;
there is no new API-level expiry response or automatic rebuild. Lifecycle expiry
and physical space reclamation are asynchronous, so three days is not a hard
capacity bound. Monitor actual disk use and reclamation before broad enrollment.

Keep the default 31-day policy for the existing staging store. Use the environment
overlay on a **new release/target** to introduce shorter retention, or stop old
store enrollment and let its existing retention drain before shortening it.
Never silently apply a shorter lifecycle to retained artifacts. Confirm the
policy Job has completed and read back the policy before enrollment.

## Configuration

Provision a 1Password item with `rpc-secret` (32 random bytes, hex encoded),
`access-key-id` and `secret-access-key`. Set `externalSecrets.item` to that item.
In singleton mode, Garage 2.5's `--single-node --default-bucket` initializes the
persisted layout, key and bucket in every initial environment. Optional replicated
stores use the manual bootstrap below; those flags cannot be used with replication.
The access key is a Garage key ID, e.g. `GK` followed by 24 hex
digits; use a random 32-byte hex secret. Retain those credentials across restarts.
For rotation use Garage's key-management commands; changing the default-key env
variables alone does not revoke an existing key.

An installation with separately managed credentials may set
`externalSecrets.enabled=false` and provision a Secret named after the release
with those same three fields. Retain the Secret with the volume; never place
credentials in Helm values or rendered release metadata.

Provision another 1Password item whose password is the JSON map below. Reference
it through `server.externalSecrets.shardStorage.item` in the main Tuist chart.
This supplies `TUIST_SHARD_STORAGE_TARGETS` to the server. Use the same S3 key as
the Garage item. Never commit populated secrets in values files.

```json
{
  "gra-v1": {
    "site": "gra",
    "enabled": false,
    "private_network_ready": false,
    "endpoint": "http://shard-storage.kura.svc.cluster.local:3900",
    "bucket": "shards",
    "region": "garage",
    "access_key_id": "<Garage key ID>",
    "secret_access_key": "<secret>"
  }
}
```

`gra-v1` is an immutable storage identity. Never repoint an existing ID at a
different store or bucket. Add a new ID when replacing a store. Keep old IDs,
credentials and Services available until retained artifacts expire and application
cleanup finishes, even if lifecycle has already removed the bytes.
Disabling enrollment leaves reads, multipart operations and cleanup on the
persisted target. Missing configuration returns an error; it never redirects
those operations to Tigris.

## Initial single-node deployment

Use `values-staging.yaml`, `values-canary.yaml`, or `values-production.yaml` on a
fresh store. All select one replica and three-day archive expiration. Staging
and canary default to 200 GiB for functional validation; production reserves
3 TiB on one suitably sized OVH host. A mirrored pair of 3.84 TB NVMe disks is
one candidate, subject to actual allocatable disk after OS/reserves. Keep usage
below about 3 TB decimal to leave room within the quota. There is no three-way
replication multiplier: the usable dataset is stored once. This is a starting
capacity, not a measured demand estimate; compare retained bytes and daily
upload volume with the window before widening enrollment.

Do not place the production store on `cwmt8` or infer capacity from a host count.
Its previously measured 341 GiB unreserved cannot satisfy 3 TiB. Provision and
verify one appropriate host, then set its exact pool/placement and vRack before
installation. The default legacy `kura-dedibox` selector is an OVH cache-pool
label, not evidence of available storage. Canary also needs a Gravelines host;
its Canadian OVH cache node is not a local substitute. Staging's existing
singleton can continue under its current policy without buying another host.
A fresh parallel staging store needs its own capacity while old artifacts drain.

### Singleton maintenance and recovery

The StatefulSet uses `OnDelete` in both topologies. A chart/image update does not
automatically restart the sole serving pod. For maintenance, disable new-plan
enrollment, check queued/running consumers, and schedule a restart after they
finish, or accept that affected jobs may need retrying. Rehearse the exact Garage
version pair first. Preserve the PVC, node identity and credentials; verify an
old artifact checksum and a fresh multipart upload/read after restart, then
reenable enrollment. Disabling enrollment alone does not stop existing consumers.

There is no zero-downtime upgrade or host-failure guarantee. While Garage is down,
new plans can fall back to the account/default store, while existing local plans
remain pinned and fail until it returns. An ordinary restart preserves the disk;
permanent disk/host loss requires rerunning affected build jobs on a new immutable
store target. Local RAID reduces individual-disk risk but is not a second host.
For incompatible upgrades, retain the old store until its artifacts drain, or
use temporary separate capacity and a new target. Never repoint an existing ID.

## Optional future replication and initial bootstrap

Install a **new release** using the environment overlay followed by
`values-replicated.yaml`, and an independent
immutable target ID (for example `gra-replicated-v1`). Never change the existing
staging release from one to three replicas. Garage does not support changing
the replication factor in place; Helm rejects a replica-count change when it
can look up the existing StatefulSet. Offline rendering cannot enforce that
guard. Keep any old release, target and credentials until its retained artifacts
expire and application cleanup finishes.

The optional replicated topology uses factor 3 with consistent reads/writes (quorum 2).
Two replicas require both for writes, so they would not meet the maintenance
availability requirement. Required hostname anti-affinity places each replica
on a different OVH host in the selected pool. All three remain in Gravelines:
this protects against one host outage, not a site outage. Each reserves a
3 TiB local PVC and 3 TiB of scheduler capacity with the production overlay:
9 TiB reserved, at most 3 TiB logical before metadata/headroom. The example
layout below advertises 3000 GB per node to leave headroom. Adjust this to the
actual PVC size when qualifying with smaller test volumes. Both metadata and
data fsync are enabled.

Discovery and layout initialization are a deliberate **manual bootstrap gap**.
Public node IDs only exist after the initial start. We use stable peer DNS seeds
instead of granting Garage Kubernetes API access and installing a discovery CRD.
The pods need no service-account token. This should eventually become an
idempotent bootstrap controller/job; it must not silently replace a persisted
layout or credentials on upgrades.

After human-authorized installation (no `--wait` for initial readiness: quorum
cannot exist until the layout is assigned), wait for all three containers to be
Running, then execute in Bash with the explicitly selected context and release:

```bash
shard_context=tuist-k8s-production
shard_release=shard-storage-replicated
k() { kubectl --context "$shard_context" -n kura "$@"; }
g() { k exec -i "$shard_release-0" -- /garage "$@"; }

# STOP if this is not a fresh, unassigned layout at version 0.
g layout show
# Verify three distinct OVH hosts, free capacity and private routes first.
k get pods -l "app.kubernetes.io/instance=$shard_release" -o wide

printf 'cluster:\n  bootstrapPeers:\n' > shard-peers.yaml
for i in 0 1 2; do
  shard_id=$(k exec "$shard_release-$i" -- /garage node id | cut -d@ -f1)
  shard_peer="$shard_id@$shard_release-$i.$shard_release-peers.kura.svc.cluster.local:3901"
  printf '    - "%s"\n' "$shard_peer" >> shard-peers.yaml
  g node connect "$shard_peer"
  shard_host=$(k get pod "$shard_release-$i" -o jsonpath='{.spec.nodeName}')
  g layout assign -z "$shard_host" -c 3000GB "$shard_id"
done
g layout show
g layout apply --version 1
g json-api GetClusterHealth
```

Keep `shard-peers.yaml` (public IDs, no secrets) with the environment's deployment
values and include it in every subsequent Helm upgrade alongside the environment
and replicated overlays and secret item reference. Roll all three pods once using the procedure
below **before enrollment**, so every process loads the stable DNS seeds. Peers
retain their identities on their PVCs; DNS permits reconnecting after pod IPs
change. Never bootstrap a replacement volume with an old node's identity.

Import the pre-provisioned S3 key through `garage json-api ImportKey -`, supplying
JSON on stdin with `accessKeyId`, `secretAccessKey`, and `name`. An authorized
operator obtains these from the environment's credential manager; do not read
Kubernetes Secrets or put credentials in shell arguments, Helm values, logs or
this file. Suppress the ImportKey response, which contains credentials. Then
create `shards` with `garage bucket create shards` and grant that key
`garage bucket allow --read --write --owner shards --key <key-id>`. Verify the
lifecycle CronJob and authenticated multipart S3 access before activation.

## Optional replicated-store maintenance

The S3 Service and target identity remain stable during a compatible Garage
upgrade. With one replica stopped, the remaining two can read uploaded artifacts
and accept uploads. A PodDisruptionBudget requires two ready pods for voluntary
evictions. The StatefulSet uses `OnDelete`: changing the image does not start
an automatic rolling update. A PDB alone would not constrain a StatefulSet
rollout or direct pod deletion, nor does it prevent simultaneous physical faults.

For each compatible version upgrade or host maintenance:

1. Read Garage's release-specific upgrade instructions and rehearse the exact
   version pair on a replicated staging/test cluster. Check free disk on every
   host, all three node identities, and `garage json-api GetClusterHealth`:
   `healthy`, three storage nodes OK, all partitions OK. Check from every node.
2. Run `garage repair --all-nodes --yes tables`; wait for table sync/Merkle
   workers to be idle with empty queues on every node. If running block repair,
   also wait for its repair workers to be `Done`. Inspect `garage stats --all-nodes`
   and workers for outstanding table synchronization, block resyncs or errors.
   Garage 2.5 also schedules verification checks after twice its RPC timeout
   (ten minutes with defaults), so a nonempty queue is not necessarily a failed
   transfer; allow it to settle. Do not proceed while replicas are catching up.
   Capture metadata snapshots
   and the layout using the release-specific backup procedure before upgrades.
3. Apply the reviewed image/configuration with Helm, preserving the environment
   and replicated overlays and peer values. Evict **one** pod through the Kubernetes eviction
   API (or drain that host respecting PDBs). Do not scale down, delete the PVC,
   force a drain or use a simultaneous `rollout restart`. Wait for that same
   ordinal/PVC to return and repeat the full health, repair and backlog checks
   before evicting the next. Abort on a second degraded replica.
4. Verify a pre-existing artifact's checksum and a fresh multipart upload/read
   through the S3 Service from an enrolled runner throughout the procedure.
   Check the final image on all three pods and full cluster health.

These checks are currently operator-run, not an automated maintenance gate.
HTTP `/health` only proves quorum; it is insufficient as a catch-up gate. The
120-second termination grace period allows Garage to stop gracefully, but a
connection to the departing pod can still fail. Storage quorum is not a promise
of uninterrupted individual transfers; runner/client retry behavior and Service
endpoint convergence must be validated under real load before production use.

Protocol-changing major upgrades may require coordinated downtime. To avoid
disrupting in-flight plans, create a parallel cluster with a **new target ID**,
enroll new plans there, and retain the old store/version for reads and cleanup
until its final plan expires. Never repoint an existing target to the empty new
cluster. This requires temporary capacity for both stores. If that capacity is
unavailable, disable enrollment and wait for retained plans to drain before a
scheduled migration; do not promise an online major upgrade.

An ordinary reboot retains the same PVC and identity. A permanently lost disk
requires Garage's node replacement/layout/rebalance procedure while the two
healthy replicas stay online; retain the remaining PVCs, restore redundancy and
verify data before any further maintenance. Local PV node affinity prevents a
pod from simply moving its disk to another host. The provisioner's `Delete`
reclaim policy makes PVC deletion destructive. Replication does not replace
backups or protect against accidental bucket deletion or a site-wide failure.

## Rollout

Follow [infrastructure access rules](../../AGENTS.md) for every shared-cluster
operation. This chart is not a dependency of the main server release. A failed
storage node must not block server deployments.

1. Deploy the additive ClickHouse migration and server routing/capacity code
   before installing the store. All server replicas must understand the new
   column and target configuration before enabling the account flag.
2. Check Kura headroom, provision secrets, and install this chart separately as
   a new production release in namespace `kura`, with `enabled=true` and
   the environment overlay. Use singleton initialization for the initial rollout;
   use the manual bootstrap only for the optional three-node topology. The default
   placement selects `kura-dedibox`, the historical pool label now used by the
   OVH EU-West fleet in Gravelines. The former Dedibox hosts have been retired;
   the label remains because existing KuraInstances, local PVs and gateways
   depend on it. Verify the selected host's OVH provider identity, Gravelines
   location, allocatable disk and private route before enrollment. Staging and
   canary require deliberate placement overrides. Preserve staging fixture archives.
3. Confirm full cluster health and the lifecycle policy, then perform a multipart
   upload/download/delete smoke test with disposable bytes from a server pod
   and an enrolled runner. Test each replica's restart against the same PVC and
   preserved data after recovery. During a singleton outage, existing local
   plans must remain pinned and fail; new plans should fall back. Existing
   timings describe one staging setup, not the new hardware or workload.
4. Complete the drained [Linux private-network enrollment](../../kura-controller/linux-runner-private-cache.md)
   for every runner eligible for the workflow. Verify the private route to the
   storage host; a configured vRack template alone is insufficient. Only then
   label those actual Nodes `node.cluster.x-k8s.io/shard-storage-site=gra`.
   `ovhFleets.<fleet>.shardStorageSite: gra` carries that label on future Machines;
   it does not attest to the networking of existing hosts. Do not label hosts
   before private connectivity is verified.
5. Deploy the updated Linux runner image and Mix/Cargo clients. GitHub and
   Buildkite jobs receive the signed grant; fork jobs do not. Dispatch reads
   the claiming node's storage-site label, never guest input. Both the build
   and every consuming shard must run on enrolled nodes at that site.
6. Set the target's `enabled` and `private_network_ready` to true and roll the
   server pods to reload their environment. Enable the default-off
   `runner_shard_storage` flag for the Tuist account only. New Mix/Cargo plans
   select Garage only with a valid account/site/Linux grant and a successful
   bounded authenticated bucket probe. Custom account S3 storage is preserved.
7. Verify creation, reference and plan-ID upload routes, download, rerun, and
   expiration cleanup, including the shorter local lifetime. In an isolated
   test, stop the store: new plans should use the default store
   while existing plans fail without switching stores. Disable the flag
   and verify existing Garage plans still work. Use the existing CI timing data
   to assess the rollout; a separate measurement PR is not a prerequisite.

Consumers must present a same-site grant before receiving local URLs. Unenrolled,
external or older workers cannot consume a local plan; rerun the build with
enrollment disabled for a workflow that needs those workers. Grants are API
headers only and are never forwarded to object storage or logged in HAR/debug
headers. Storage credentials stay server-side.

Rollback means disable the account flag or the target's `enabled` field, while
retaining the store/configuration for existing plans. Do not roll the server
back to code that ignores `storage_target`, drop the column, or uninstall the
store before its retained plans have expired and cleanup has succeeded. If the
whole store is lost permanently, disable enrollment, create a new target ID for
its replacement, and rerun affected build jobs.

## Local validation

Run `mise run helm:shard-storage`, `mise run helm:linux-vrack`, and
`mise run helm:rack-independence` from `infra/`. These render manifests only.
They do not establish live routing, quota enforcement or S3 interoperability.
For the initial singleton, verify same-PVC restart persistence, new-plan
fallback, pinned existing-plan failure, recovery, multipart cleanup and policy
readback. Validate shortened expiration on disposable data; setting a lifecycle
policy alone does not prove elapsed-time deletion or timely space reclamation.
Before adopting optional replication, qualify it in an isolated test release: distinct random multipart objects before and during each
one-node outage, checksum reads through the stable Service, rejection of a second
eviction, and completed recovery on the same PVC before the next outage. Repeat
using the exact image version pair and the production private route. Do not use
the existing staging singleton or preserved fixture volumes for destructive tests.

Garage references: [single-node initialization](https://garagehq.deuxfleurs.fr/documentation/quick-start/),
[lifecycle support](https://garagehq.deuxfleurs.fr/documentation/reference-manual/s3-compatibility/),
and [health checks](https://garagehq.deuxfleurs.fr/documentation/reference-manual/admin-api/).
See also [configuration/quorum](https://garagehq.deuxfleurs.fr/documentation/reference-manual/configuration/),
[cluster bootstrap](https://garagehq.deuxfleurs.fr/documentation/cookbook/real-world/),
and [upgrade compatibility](https://garagehq.deuxfleurs.fr/documentation/operations/upgrading/).
