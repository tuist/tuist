# RustFS staging qualification

This standalone chart is disabled by default and is not connected to deployment
workflows. It creates a disposable store, not an upgrade of `shard-storage`
(Garage). No dedicated hardware orders or changes to existing volumes are needed.

## Topology and limits

The chart requires namespace `rustfs-staging`, four general workers, and two
10 GiB `hcloud-volumes` claims per worker. Eight independent virtual volumes
give roughly 40 GiB logical capacity before metadata/headroom with EC:4. Reserve
2.2 CPUs and about 4.2 GiB memory across the cluster; the four RustFS pods can
consume up to 8 GiB combined. Check **allocatable minus pod requests**, memory
pressure and volume attachment limits before enabling; current usage alone does
not establish headroom. Do not relax required hostname anti-affinity to fit.

This tests S3 integration and logical member failure, **not OVH vRack routing,
physical disk independence, site resilience or production NVMe throughput**.
The initial pool starts all four members together. Never scale it to three and
later add the fourth, change its endpoint list, or reuse an existing Garage PVC.
Every release must be installed in the namespace its overlay names
(`namespace`, `rustfs-staging` by default).

## Production pilot on the Gravelines shard host

`values-production-gra.yaml` runs one member with one drive in
`rustfs-production` on the `shard-storage` host, beside Garage, as
`s3.tuist.dev`: a general store whose first bucket is `shards`. RustFS keeps one
copy (`parity: ""`) on the host's RAID10 `/data`; the RAID handles disk failures,
and a host outage fails plans already stored here while the server sends new
plans to Tigris. The single 1000G PVC gets one XFS project quota of that size.

It needs Garage's quota on the same filesystem lowered from 3Ti to 2Ti first.
The `scw-local-nvme` provisioner sets a volume's quota only when it creates it,
and the class does not allow expansion, so this is a host step: lower the hard
limit of Garage's project with `xfs_quota` (from the host mount namespace, under
a production elevation), confirm `prjquota` enforcement on `/data`, then deploy
`shard-storage` with `storage.reservation: 2Ti` and recreate its pod (OnDelete).

To take over Garage's in-cluster workload, the drive then grew in place: lower
Garage's project hard limit to 1200Gi (above its usage), raise RustFS's project
to 1850Gi, then deploy both reservations (`storage.reservation: 1200Gi`,
`resources.requests.ephemeral-storage: 1850Gi`) and recreate `shard-storage-0`
before `rustfs-0`, so the node's 3.08 TiB allocatable fits both while each pod
schedules. The PVC still reads 1000G; the project limit and the reservation are
what count. Grow it again the same way, lowering Garage only above its usage.
Until then the RustFS pod stays Pending: Garage's 3Ti request leaves the node
less ephemeral storage than RustFS requests.

Garage was retired on 2026-11-19. A Job on the shard host mirrored its
`shards`, `sandbox-archives` and `actions-cache` buckets into these buckets
under the same keys, and `target.aliases: [gra-production-v1]` publishes
Garage's ID as a private alias of this store (in-cluster endpoint, never
`private_network_ready`). Shard plans, Actions cache entries and sandbox archive
rows recorded under that ID resolve here unchanged, so no database row moved.
Production's server reads only this release's `rustfs-targets`. Garage's
release was uninstalled and its PVC deleted (the provisioner's teardown clears
its project quota), and RustFS's project hard limit was raised to 3050Gi, the
two stores' former total, with the reservation following.

The server deployment installs this release in production.
Nobody handles credentials: with `generateCredentials`, External Secrets
generates the root Secret (`existingSecret`) and `<release>-service` once
(`CreatedOnce`, orphaned from the release), and the hourly `<release>-setup`
CronJob idempotently creates the `shards` bucket, its `setup.expirationDays`
expiry (a 31-day backstop: server cleanup applies the plan's 7/14/30 days), the `shards-policy.json` policy and the service user. Run
`kubectl -n rustfs-production create job --from=cronjob/rustfs-setup` to apply
it without waiting. `target.id` publishes the bucket as a public target in
Secret `<release>-targets` (key `targets.json`) in `serverNamespace`, copied
through a SecretStore that may only `get` the service Secret, never root. The
main chart reads it with `server.externalSecrets.shardStorage.publicSecret` into
`TUIST_PUBLIC_SHARD_STORAGE_TARGETS`, merged with the runner-local targets; a
public ID never replaces a runner-local one. Accounts still need the public
shard storage flag, and the server skips the target while it does not answer.

`dockerMirror.bucket` adds a bucket for the main chart's Docker Hub
pull-through cache (`registryCache`), capped by a `maxGB` quota and reachable
only in-cluster. The setup CronJob creates it with its own user, which can
reach only that bucket, and `target.yaml` copies that user's keys into Secret
`<release>-docker-mirror` in `serverNamespace`. Point `registryCache` at it only
once that Secret exists and the hourly setup has created the user: the main
release waits on the cache pod and rolls back if its Secret is missing.

Public requests enter through the host-network `kura-eu-west` controller on
the EU-West Kura nodes and cross the vRack to the gateway, so
`ingress.hostNetworkController` adds a Cilium rule admitting node identities
on the gateway port.

Gateway pods expose only the path-style buckets in `gateway.buckets` (`shards`
by default; every other path is 404). Public TLS terminates
at an explicitly configured Ingress; backend services remain ClusterIP-only.
The gateway preserves the signed Host/path/query and streams both directions.
It does not replay requests after partial uploads. Root credentials are only in
the RustFS pods. Normal server credentials must have `shards-policy.json`, not
root/admin rights. NetworkPolicy permits peer traffic only inside this release
and gateway ingress only from the configured ingress-controller namespace.

The gateway writes one JSON access line per request to stdout, which Alloy
ships to Pulse: time, client (the last `X-Forwarded-For` entry, which the
ingress appends), peer, method, path (`$uri`), status, bytes, duration, user
agent, how the request was signed (`presigned`, `header` or `none`) and the
signing access key ID. It never logs the query string or `Authorization`, which
carry signatures; the gateway's error log and the Ingress access log stay off
because nginx writes the whole request line there. `mise run
helm:shard-storage-rustfs` fails if the log format names any other variable.
In-cluster callers reach `<release>-s3:9000` directly, so their requests are
not in this log.

RustFS's audit records cover every S3 request, in-cluster ones included
(`audit.enabled`, on by default). RustFS posts them to an `audit` sidecar on
`127.0.0.1:9900`, which prints one JSON line per request with
`"log":"rustfs_audit"` to stdout, the same path to Pulse as the gateway log:
time, client (source IP), API, bucket, object, path, status, request bytes,
duration, how it was signed, signing access key ID, request ID and user agent,
plus the deleted keys (up to 4096 characters) and their count for a bulk
delete.
RustFS puts the request headers in the record, so the receiver
(`files/audit_receiver.py`) builds each line from an allowlist and never logs
them; any path still shaped like a signature is dropped.
`test-audit-receiver.py` runs it against unredacted presigned and
header-signed records. Limits: RustFS sends no record for a request that fails
signature verification (the gateway log still has public ones) and reports no
response size, so only request bytes are logged. Delivery never blocks S3:
RustFS queues up to `audit.queueLimit` records on a 2Gi emptyDir while the
receiver is down and drops beyond that with an `audit_dispatch_failed` error
log. A sidecar that is not running still makes the pod NotReady and removes
the store from its Service, so the sidecar has no probes and its shell restarts
the receiver in place; what remains is an image pull from Docker Hub failing
when the pod is recreated. The StatefulSet is `OnDelete`, so the sidecar
starts only when the store pod is recreated.

The shard Ingress uses a 1 MiB client-body buffer while keeping request
buffering **off**. NGINX uses this buffer to size unbuffered HTTP/2 stream
receive windows; the default 8 KiB body buffer leaves roughly a 64 KiB window
and throttles uploads over higher-latency links. This is not full-body buffering
or an HTTP/2 disable switch. Budget roughly 1 MiB per active upload stream
(about 10 MiB for the CLI's ten concurrent parts), plus proxy/TLS overhead,
on the ingress controllers. It is not a global concurrency or memory cap.
Keep the override scoped to this Ingress, not the shared controller ConfigMap.
See [NGINX's directive](https://nginx.org/en/docs/http/ngx_http_core_module.html#client_body_buffer_size)
and [HTTP/2 upload flow control](https://blog.cloudflare.com/delivering-http-2-upload-speed-improvements/).

### Rack Macs' store on larch-store-a

`values-production-larch.yaml` runs one member with one drive in `rustfs-larch`
on larch-store-a, as private target `rustfs-larch-production-v1` (site
`larch`). Macs reach no cluster network: a rack VM may reach only its site's
storage node on TCP 443 (`rackFleet.vmCacheGatewayCIDRs`). So each entry in
`runnerEntrances` is an Ingress on that site's host-network gateway
(`kura-<site>-runners`), admitting only the site's machines segment, with a
DNS record at the storage node's segment address and a DNS-01 certificate.
The server reaches the store in-cluster, signs a Mac's URLs for its own
site's entrance (`runner_endpoints`), and places plans here from Macs at
`larch` and at each site in `target.placementSites` (ber1) with
`runner_shard_storage`; a placement site needs its own entrance. Shard jobs run at whichever site claims
them, so ber1's entrance must serve before any plan lands here: the server
gets `runner_endpoints` only once `target.runnerEntrancesReady` is set, for
every entrance at once. ber1's traffic crosses both sites' internet ports
until the inter-site link carries the machines segments.

The main chart reads the published Secret as
`server.externalSecrets.shardStorage.secret` (`rustfs-larch-targets`). Before
the first install, check larch-store-a's memory (the store requests 512Mi, the
gateway 64Mi) and that `kuraDataLVSize` keeps room for `volumeSize` beside the
VM image cache: the lvm-v1 reinstall empties `/data`.

To mark it ready, from a Mac at each site:
`curl -sS -o /dev/null -w '%{http_code}' https://<entrance host>/shards/` answers
403 (RustFS, unsigned). Then set `target.runnerEntrancesReady: true`, deploy,
and restart the server so it reads the new map.

In Pulse, `tuist_shards_plans_total{platform="macos"}` counts macOS plans by
`store` (`default` is the account or Tigris), and
`tuist_shards_upload_plan_age_milliseconds` times each artifact upload from its
plan's creation, by store, platform and site. The store's own view is RustFS's
OTLP export under `job="rustfs-larch"`, for example
`histogram_quantile(0.5, sum by (le) (rate(rustfs_s3_put_object_duration_ms_bucket{job="rustfs-larch"}[1h])))`
and `rate(rustfs_http_server_response_body_bytes_total{job="rustfs-larch"}[5m])`.

### Single-member OVH performance variant

`values-staging-ovh.yaml` installs a second release, `rustfs-ovh`, as one
member with eight drives on the staging Gravelines Kura box. Public TLS ends
on that box's `kura-eu-west` ingress (`shards-ovh-staging.tuist.dev`), so
uploads never cross to Hetzner. It measures OVH NVMe and the public path, not
replication between hosts or failure behaviour. All drives share the box's
NVMe RAID1 root through local-path, which requires `unsafeSharedDisks`; the
chart refuses that setting for more than one member. Kura's encrypted CSI
classes cannot be used: an admission policy lets that driver provision only
for Kura, and refused claims leave thin volumes behind until `DeleteVolume`
is called on the node.

```bash
helm -n rustfs-staging upgrade --install rustfs-ovh infra/helm/shard-storage-rustfs \
  -f infra/helm/shard-storage-rustfs/values-staging-ovh.yaml
RUSTFS_RELEASE=rustfs-ovh RUSTFS_HOST=shards-ovh-staging.tuist.dev \
  RUSTFS_TARGET=rustfs-staging-ovh-v1 bash bootstrap-staging.sh
```

The server reads `TUIST_SHARD_STORAGE_TARGETS` at startup, so restart it after
publishing a target. Enabled public targets are chosen in ID order, so
`rustfs-staging-ovh-v1` takes precedence over `rustfs-staging-v1` for
enrolled test accounts; disable it in the target map to switch back.

## Approval boundary and bootstrap

Everything below that creates resources, buckets, users, flags, plans or objects
needs staging approval. These commands are **not** part of the local checks.

1. Check four eligible workers and CSI capacity. Provision the namespace and
   `rustfs-root` Secret (`root-user`, `root-password`) through the environment's
   credential manager. A human owns Secret provisioning; do not read shared
   Secrets into an agent session. Keep credentials across restarts.
2. Choose a staging-only, DNS-only hostname and provision its valid TLS Secret,
   or set `ingress.clusterIssuer` to the staging cert-manager issuer.
   Do not put Cloudflare's proxy or response cache in the object data path.
   Confirm `ingress.className` and `ingress.controllerNamespace` against the
   actual controller. Access logs are disabled on this Ingress, but the shared
   controller's **error logs can still contain signed queries**: audit/redact
   that logging or use a dedicated controller before customer enrollment.
3. After approval, install the independent release, supplying the reviewed
   hostname and existing TLS Secret (no credentials in Helm values):

   ```bash
   HELM_DRIVER=configmap helm upgrade --install rustfs infra/helm/shard-storage-rustfs \
     --kube-context tuist-k8s-staging --namespace rustfs-staging \
     --set enabled=true --set ingress.enabled=true \
     --set ingress.host="$SHARD_STORAGE_HOST" --set ingress.tlsSecret="$TLS_SECRET" \
     --wait --timeout 10m
   kubectl --context tuist-k8s-staging -n rustfs-staging \
     wait --for=condition=Ready pod -l app=rustfs --timeout=5m
   kubectl --context tuist-k8s-staging -n rustfs-staging \
     wait --for=condition=Ready certificate/"$TLS_SECRET" --timeout=5m
   ```

   The certificate wait applies when cert-manager owns the Secret. This release
   uses ConfigMap-backed Helm metadata (only credential references, never values),
   so upgrades/history must also set `HELM_DRIVER=configmap`. Do not assume Helm's
   completion means every pod or certificate is Ready. The staging instance uses
   `shards-staging.tuist.dev`, `rustfs-public-tls`, and `letsencrypt-cloudflare`.

   Once the pods and certificate are Ready, a **human on their own machine** can
   run `bash bootstrap-staging.sh` to perform steps 4–5 together. It fetches the
   staging kubeconfig locally, reuses the root credential, creates/reuses a
   separate `RUSTFS_STAGING_SHARDS` 1Password item, and tests a small authenticated
   public transfer before publishing an enabled target. The routing-capable server
   must keep `public_shard_storage` off except for the disposable test account;
   the script does not change flags. The current private-only server cannot select
   this target because `private_network_ready` remains false. It preserves existing
   target entries and refuses a concurrent Secret update. It does not restart the
   server or enroll accounts. Requires `op`, `kubectl`, `jq`, `curl`, and `shasum`.
   If MinIO `mc` is absent, it downloads a checksum-verified, pinned GitHub release
   into its temporary directory and deletes it on exit; the old `dl.min.io`
   binary URL returns HTTP 410. Never run the bootstrap in an orb or send its
   kubeconfig/credentials to an agent. The manual equivalent follows.

4. Verify four Ready members on distinct nodes, eight Bound claims, both
   gateways, TLS, and all-peer readiness. Root/admin operations use a human's
   loopback-only port-forward to a store pod, **never** the public gateway.
   Configure an `mc` alias `rustfs-stage-admin` using interactive credential
   prompts in a protected local config directory. Bootstrap only this empty
   store (commands run from this chart's directory):

   ```bash
   mc mb rustfs-stage-admin/shards
   mc ilm import rustfs-stage-admin/shards < lifecycle.json
   mc ilm export rustfs-stage-admin/shards
   mc admin policy create rustfs-stage-admin shard-artifacts shards-policy.json
   # Prompts for access/secret keys; never put them in command arguments.
   mc admin user add rustfs-stage-admin
   mc admin policy attach rustfs-stage-admin shard-artifacts --user "$SHARD_SERVICE_USER"
   ```

   Read the lifecycle back and validate the separate service user's multipart,
   GET, HEAD, LIST, DELETE and abort permissions; deny anonymous reads, other
   buckets, bucket-policy changes and admin operations. Keep root and service
   credentials separate. `mc` admin compatibility with the pinned RustFS build
   is a deployment gate, not assumed from its S3 compatibility. Never enable
   the server with root credentials to work around a failed bootstrap.
5. Merge a **new** immutable ID into the staging server's existing
   `TUIST_SHARD_STORAGE_TARGETS` secret map; preserve all Garage entries:

   ```json
   {
     "rustfs-staging-v1": {
       "access": "public",
       "site": "gra",
       "enabled": false,
       "private_network_ready": false,
       "endpoint": "https://<reviewed-staging-host>",
       "region": "us-east-1",
       "bucket": "shards",
       "access_key_id": "<limited service user>",
       "secret_access_key": "<limited service secret>"
     }
   }
   ```

   Roll out the routing-capable server first, refresh its secret configuration,
   then enable the target and the default-off account flag `public_shard_storage`
   **only on a disposable test account**. Use separate Xcode/Cargo projects
   named `rustfs-e2e-*`. Customer-owned S3 always wins. Existing eligible private
   Mix/Cargo storage also wins; turn off `runner_shard_storage` for the test
   account to exercise the new public fallback without changing Garage.

## Runnable qualification

Python 3 (standard library only) runs the transport harness. Supply `TUIST_URL`,
`TUIST_PROJECT` and `TUIST_TOKEN` securely; the harness accepts only
`https://staging.tuist.dev` or loopback and dedicated `rustfs-e2e-*` projects.
Do not use shell tracing. No signed URLs or tokens go into its output/manifests.

```bash
# Xcode project: 512 MiB shared artifact plus an asymmetric module artifact.
python3 e2e/shard-storage.py --storage-host "$SHARD_STORAGE_HOST" \
  --manifest /tmp/rustfs-plan.json
# Cargo/Mix project: single legacy bundle, same multipart transport.
python3 e2e/shard-storage.py --storage-host "$SHARD_STORAGE_HOST" --layout bundle
# Recheck the SAME plan after withdrawal, restart, or recovery.
python3 e2e/shard-storage.py --storage-host "$SHARD_STORAGE_HOST" \
  --read-manifest /tmp/rustfs-plan.json
```

It creates a real plan through Tuist, starts by reference, signs/completes by
plan ID, checks the destination host, streams multipart parts, and verifies full
SHA-256, exact size, HTTP 206 and unaligned Range bytes. Failures are nonzero;
timeouts are bounded (120-second socket inactivity, 30-minute overall deadline).
It deliberately does not retry away an outage. Output includes per-object bytes
and elapsed seconds. Uploads use sequential 8 MiB parts; their timing includes
per-part API signing and completion, but not payload generation or upload start.
This is a controlled provider comparison, not CLI throughput: the Swift client
uploads up to ten 10 MiB parts concurrently and reuses connections. Qualify large
artifacts through that client too before drawing customer performance conclusions.
Synthetic bytes test transport, not Apple archive validity or successful execution.
Failed uploads remain for the one-day abort lifecycle;
completed artifacts expire after three days. Plan metadata follows ordinary
server retention. Stop if disk use exceeds 60%; the tiny pool is not a soak
capacity target. Policy readback alone does not prove reclamation.

For real execution, set `TUIST_E2E_CLI` to an absolute CLI executable path:

```bash
bash e2e/shard-storage-client.sh cargo
# On a Mac with the repository checkout and supported Xcode:
bash e2e/shard-storage-client.sh xcode
```

The Cargo wrapper reuses `CargoSharding/e2e.sh`: six tests exactly once across
two disjoint fresh workers, no compilation, and server reporting. It requires
Rust/Cargo/nextest. Xcode reuses `generated_ios_app_with_tests` and runs
`MacFrameworkTests` from a source-only worker after removing the build products.
Both additionally require the server's signed download host to match the
specified store. Raw CLI logs remain temporary/private and are removed on success.
On failure the harness prints their private directory for diagnosis; remove it
after inspection and never publish raw logs containing signed URLs.
Use a 45-minute CI job timeout around either wrapper. The Xcode fixture proves
archive consumption, not a UI-test simulator workload: also qualify an isolated
representative UI-test project before customer rollout.

## Fault, rollback and performance gates

Run baseline, one-fault, recovery and rollback cases separately and preserve
sanitized results. Faults are **operator-controlled, separately approved**;
the harness never drains nodes, deletes PVCs, changes flags or modifies Cilium.

- Healthy: split and bundle probes, real CLI workflows, service-user isolation,
  expired/tampered signed URL rejection, and checks from an external Mac/Linux
  runner plus our own Linux runner.
- One member unavailable: on this disposable release only, suspend one member
  (not a shared worker). Rerun retained reads and new uploads. With two drives
  per member EC:4 should retain read/write quorum with three members. Restore
  it and verify healing/health and fresh checksums before another fault. A pod
  deletion alone is a short restart, not a sustained node-loss test.
- Two members unavailable: expect bounded write failures; do not claim healthy
  write availability. Existing plans must never switch buckets. Restore and
  fully heal before proceeding. PDBs constrain eviction, not direct deletion,
  scaling, process failure or network partitions.
- Gateway loss and same-PVC store restart: retained and new-object checks,
  including in-flight client retries. Gateway readiness is process-only; the
  server's bounded bucket probe controls new enrollment. Never use `LIST`
  completeness in degraded mode as the sole durability check.
- Withdrawal: disable only the test account's public flag; a new plan must
  use the expected default/Tigris host, while `--read-manifest` must still read
  the RustFS plan. Outage before enrollment may fall back; outage after
  persistence must fail pinned rather than serve an unrelated object.
- Cleanup: prove service-user DELETE, incomplete upload abort, elapsed-time
  lifecycle deletion and normal server retention cleanup. For faster expiry
  experiments use another empty bucket/release, not shortened retained data.
- Performance: alternate Tigris and RustFS runs from the **same** external
  EU/US-East/US-West workers and our runners. Use 512 MiB and 2 GiB objects,
  concurrency 1/4/16, at least 20 successful samples per relevant cell plus a
  sustained soak sized to available disk. Report failures as well as median,
  p95 and p99; do not compare only successful fast attempts. Pre-agree a
  non-regression threshold (suggested: p95 <= 110% of Tigris with no additional
  timeouts). Hetzner staging results cannot justify OVH performance claims;
  repeat on proposed OVH hardware before broad enrollment/orders based on speed.

Private access is an optional **second route to the same store**, not a replica
or separate bucket. After actual vRack/gateway reachability is proven, add
`private_endpoint` and set `private_network_ready=true`; only verified same-site
Linux grants select it. This chart does not provision vRack, private DNS or
runner ingress. Its Hetzner-backed staging pool therefore starts public-only,
including for our runners. Never advertise its ClusterIP DNS to runner guests
without demonstrated reachability. The server signs the chosen endpoint; never
rewrite a hostname after signing. HTTPS private endpoints work with the same
harness; `TUIST_RUNNER_GRANT` is sent only to Tuist, never to S3.

Rollback disables new enrollment but retains the target ID, endpoint, bucket,
credentials and storage until plans and cleanup drain. Never repoint an ID,
fall back for an existing plan, or roll back to a server ignoring targets.
Deletion of the isolated release/volumes and test projects is a separate
explicit cleanup approval. Do not touch the existing Garage release.

## Local validation (no deployment)

```bash
bash infra/mise/tasks/helm/shard-storage-rustfs.sh
bash -n e2e/shard-storage-client.sh
python3 e2e/shard-storage.py --help
# From server/ with PostgreSQL and ClickHouse running:
mix test test/tuist/shards/storage_test.exs test/tuist/shards/storage_routing_test.exs \
  test/tuist/shards_test.exs test/tuist_web/controllers/api/shards_controller_test.exs
```

Helm checks are offline render checks, not proof of Kubernetes scheduling,
NetworkPolicy enforcement, TLS ingress, erasure quorum or healing. Gateway
configuration changes require an explicit controlled gateway rollout after
updating the ConfigMap; RustFS uses OnDelete, never automatic rolling restarts.
RustFS [cluster lifecycle rules](https://github.com/rustfs/rustfs/blob/1.0.6/docs/operations/cluster-lifecycle-operations.md)
and [disk preparation](https://docs.rustfs.com/en/installation/requirement/disk-preparation)
remain prerequisites for production qualification.
