# Linux shard artifact storage

This independently released chart runs one Garage node on an EU-West Kura host.
It is disabled by default. It stores disposable Mix `_build` archives and Cargo
nextest archives; losing the volume requires rerunning the build job. It does
not store the authoritative shard plan or change Xcode artifact routing.

The `scw-local-nvme` provisioner enforces the 200 GiB PVC with an XFS project
quota. The pod requests the same amount of `ephemeral-storage` for scheduler
accounting and carries `tuist.dev/region` for Kura capacity admission. Install
in `kura`, where that admission reads region reservations. Admission uses the
current pressure threshold; it does not gain another 200 GiB when Garage is
installed. Check existing region and node headroom before installation. Do not
reduce the PVC or change its storage class to work around a full node.

Garage uses path-style S3 on a ClusterIP at port 3900. RPC binds to loopback;
the admin health listener is not exposed by the Service or NetworkPolicy.
The lifecycle CronJob applies 31-day expiration and one-day incomplete multipart
abortion. Server cleanup still applies the account's normal 7–30 day retention.
If an operator extends shard retention beyond 30 days, increase the backstop
first. Confirm the CronJob has completed successfully before enrollment.

## Configuration

Provision a 1Password item with `rpc-secret` (32 random bytes, hex encoded),
`access-key-id` and `secret-access-key`. Set `externalSecrets.item` to that item.
Garage 2.5's `--single-node --default-bucket` initializes the persisted layout,
key and bucket. The access key is a Garage key ID, e.g. `GK` followed by 24 hex
digits; use a random 32-byte hex secret. Retain those credentials across restarts.
For rotation use Garage's key-management commands; changing the default-key env
variables alone does not revoke an existing key.

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
credentials and Services available until their plans expire and cleanup finishes.
Disabling enrollment leaves reads, multipart operations and cleanup on the
persisted target. Missing configuration returns an error; it never redirects
those operations to Tigris.

## Rollout

Follow [infrastructure access rules](../../AGENTS.md) for every shared-cluster
operation. This chart is not a dependency of the main server release. A failed
storage node must not block server deployments.

1. Deploy the additive ClickHouse migration and server routing/capacity code
   before installing the store. All server replicas must understand the new
   column and target configuration before enabling the account flag.
2. Check Kura headroom, provision secrets, and install this chart separately as
   release `shard-storage` in namespace `kura`, with `enabled=true`. The default
   placement selects `kura-dedibox`; staging and canary require deliberate
   placement overrides. Preserve staging fixture archives. Canary cannot prove
   Gravelines locality.
3. Confirm readiness and the lifecycle policy, then perform a multipart
   upload/download/delete smoke test with disposable bytes from a server pod
   and an enrolled runner. Test a pod restart against the same PVC.
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
   expiration cleanup. Stop Garage temporarily: new plans should use the default
   store while existing plans fail without switching stores. Disable the flag
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
single node is lost permanently, disable enrollment, create a new target ID for
its replacement, and rerun affected build jobs.

## Local validation

Run `mise run helm:shard-storage`, `mise run helm:linux-vrack`, and
`mise run helm:rack-independence` from `infra/`. These render manifests only.
They do not establish live routing, quota enforcement or S3 interoperability.

Garage references: [single-node initialization](https://garagehq.deuxfleurs.fr/documentation/quick-start/),
[lifecycle support](https://garagehq.deuxfleurs.fr/documentation/reference-manual/s3-compatibility/),
and [health checks](https://garagehq.deuxfleurs.fr/documentation/reference-manual/admin-api/).
