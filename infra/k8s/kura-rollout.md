# Per-(account, cluster) Kura rollout

Runbook for deploying a regional [Kura](../../kura/README.md) cache mesh
for a Tuist account and registering it as a `:kura` cache endpoint
once the `:kura` feature flag has been enabled for that account.

The rollout is deliberately manual. Each mesh owns persistent volumes
and serves cache traffic that should not regress to misses during an
upgrade, so we rely on Kura's warm-rollout primitives ([PR #10446]) and
a human in the loop. Latency is the whole point of Kura, so each mesh
is pinned to a single backing cluster, which lives in one region — the
public ingress LB and the pods are always in the same place.

[PR #10446]: https://github.com/tuist/tuist/pull/10446

## Concepts

The deployment unit is `(account, cluster)`. A *cluster* is one backing
Kubernetes cluster identified by an opaque ID like `eu-1`, `us-east-1`.
The mapping from a cluster ID to its region (user-facing) and to its
provider/location (internal) lives in
[`kura/ops/helm/kura/clusters.yaml`](../../kura/ops/helm/kura/clusters.yaml).
Region is the only field accounts ever see — provider and location are
internal and may change without breaking any URL.

Multiple clusters can live in the same region. Two clusters in `eu`
might be `eu-1` (Hetzner fsn1) and `eu-2` (a different provider for
redundancy or capacity). They run as independent Kura meshes; an account
that opts into both gets two `account_cache_endpoints` rows, two URLs,
and the CLI picks the closest one.

| Element | Pattern | Example |
| --- | --- | --- |
| Helm release | `kura-<account>-<cluster>` | `kura-tuist-eu-1` |
| Namespace | `kura` | `kura` |
| Public host | `<account>-<cluster>.kura.tuist.dev` | `tuist-eu-1.kura.tuist.dev` |
| GitHub Environment | `kura-k8s-<cluster>` | `kura-k8s-eu-1` |
| Kura `KURA_REGION` tag | the cluster's region from `clusters.yaml` | `eu` |

## Pieces involved

- **Helm chart** — [`kura/ops/helm/kura/`](../../kura/ops/helm/kura/) packages
  the `StatefulSet`, headless Service, ClusterIP Service, optional
  Ingress, PDB, and ServiceAccount.
- **Layered values overlays** under `kura/ops/helm/kura/`:
  - `values-managed.yaml` — cross-cutting defaults for any managed
    cluster (image, ClusterIP service, ingress shape, ReadWriteOncePod,
    PDB, hostname spread, resource baseline, telemetry endpoint).
  - `values-managed-provider-<provider>.yaml` — provider-wide knobs
    (storage class, default volume size). One file per provider.
  - `values-managed-account-<account>.yaml` — account-specific knobs
    (`config.tenantId`, resource sizing tied to the account's
    expected traffic).
  The deploy workflow appends a generated per-instance overlay last to
  set `fullnameOverride`, the public host, the topology selector, and
  the public region tag from `clusters.yaml`.
- **Cluster catalog** — [`kura/ops/helm/kura/clusters.yaml`](../../kura/ops/helm/kura/clusters.yaml).
  Single source of truth for `cluster_id → { region, provider, location }`.
- **Warm rollout adapter** — [`kura/ops/helm/kura/rollout.sh`](../../kura/ops/helm/kura/rollout.sh).
  Stages the new revision behind a `StatefulSet` partition, rolls the
  highest ordinal first, gates each step on every pod's
  `/status/rollout`.
- **GitHub Actions workflow** — [`.github/workflows/kura-deployment.yml`](../../.github/workflows/kura-deployment.yml).
  `workflow_dispatch` only. Inputs: account, cluster, image tag.
- **Server feature flag** — `:kura`, FunWithFlags, scoped per account.
  When enabled for an account,
  [`Tuist.Accounts.get_cache_endpoints_for_handle/2`](../../server/lib/tuist/accounts.ex)
  in `:kura` mode returns the URLs from `account_cache_endpoints` with
  `technology = 'kura'`. When disabled it returns `[]` even if rows
  exist. The CLI selects `:kura` mode when its request carries the
  `kura` client feature header.

## First rollout (the `tuist` account on the `eu-1` cluster)

### 1. Pick a Kura version

```
gh release list --repo tuist/tuist --limit 20 | grep '^kura@'
```

The image is `ghcr.io/tuist/kura:<version-without-prefix>`.

### 2. Trigger the deploy workflow

```
gh workflow run kura-deployment.yml \
  -f account=tuist \
  -f cluster=eu-1 \
  -f image_tag=<kura version>
```

The workflow:

1. Reads `clusters.yaml` to resolve `eu-1`'s provider and region, picks
   the matching `values-managed-provider-<provider>.yaml`.
2. Loads `KUBECONFIG` from the `kura-k8s-eu-1` GitHub Environment.
3. Generates a per-instance values file with `fullnameOverride`, the
   public host, the TLS hosts, the topology selector, and
   `config.region: <public region>`.
4. Calls `kura/ops/helm/kura/rollout.sh kura-tuist-eu-1 kura -f ...`.
5. On first install the `StatefulSet` doesn't exist yet, so the
   partition loop is a no-op and a single `helm upgrade --install`
   brings up all three replicas. The gate then confirms every pod
   reports `serving`, the same membership generation, the expected
   ring size, zero bootstrap inflight peers, and outbox depth near
   baseline.
6. On a re-run the same workflow performs a partition-staged warm
   rollout, gating between ordinals.

### 3. Verify the public endpoint

```
curl -fsS https://tuist-eu-1.kura.tuist.dev/up
curl -fsS https://tuist-eu-1.kura.tuist.dev/ready
```

`/up` returns `200` once the pods are running; `/ready` flips to `200`
after each node has bootstrapped from the rest of the ring.

DNS for `*.kura.tuist.dev` is a `CNAME` to that cluster's ingress-nginx
public hostname; the TLS cert is the wildcard
`tuist-tls-cloudflare-origin-kura` Origin CA Secret.

### 4. Enable the `:kura` flag for the account

In a server `iex` session attached to production:

```elixir
account = Tuist.Accounts.get_account_by_handle("tuist")
FunWithFlags.enable(:kura, for_actor: account)
```

(Equivalent toggle is available in the FunWithFlags UI under
`/ops/flags`.)

### 5. Register the endpoint on the account

```elixir
account = Tuist.Accounts.get_account_by_handle("tuist")

{:ok, _endpoint} =
  Tuist.Accounts.create_account_cache_endpoint(account, %{
    url: "https://tuist-eu-1.kura.tuist.dev",
    technology: :kura
  })
```

After the row exists *and* the flag is enabled,
`get_cache_endpoints_for_handle("tuist", :kura)` returns
`["https://tuist-eu-1.kura.tuist.dev"]`. The CLI receives this list
when it sends the `x-tuist-feature-kura: true` header.

### 6. Smoke-test from the CLI

Run a Tuist build for a project owned by the `tuist` account, with the
Kura client feature flag enabled. Confirm in Grafana that
`kura_request_total` for `kura-tuist-eu-1-*` is non-zero and that the
build sees a normal cache hit ratio.

## Subsequent rollouts (Kura version bumps)

Re-run the workflow with a new `image_tag`. The warm rollout script
handles the partitioned drain. There is nothing to do on the server
side.

## Adding another cluster for the same account

1. Add the new cluster to
   [`kura/ops/helm/kura/clusters.yaml`](../../kura/ops/helm/kura/clusters.yaml)
   with its region, provider, and location. Pick the next ID for the
   region (e.g. `eu-2`, `us-east-1`).
2. Add the cluster ID to the `cluster` choice list in
   [`.github/workflows/kura-deployment.yml`](../../.github/workflows/kura-deployment.yml).
   Add a new `values-managed-provider-<provider>.yaml` if the provider
   is new.
3. Provision the Kubernetes cluster and create the
   `kura-k8s-<cluster>` GitHub Environment with its base64-encoded
   `KUBECONFIG` secret.
4. Provision DNS for `*.kura.tuist.dev` (or the relevant subset) as a
   `CNAME` to that cluster's ingress-nginx public hostname.
5. Run the deploy workflow.
6. Insert a second `account_cache_endpoints` row pointing at the new
   host. Both URLs will be returned to the CLI; it picks the nearest
   one. The flag is account-wide, so it does not need to be touched.

## Adding another account

1. Create
   [`kura/ops/helm/kura/values-managed-account-<account>.yaml`](../../kura/ops/helm/kura/)
   (`config.tenantId`, resource sizing).
2. Add `<account>` to the `account` choice list in
   [`.github/workflows/kura-deployment.yml`](../../.github/workflows/kura-deployment.yml).
3. Run the deploy workflow.
4. Enable the `:kura` flag and insert the row, as in steps 4–5 above.

## Rollback

- **App-side:** disable the `:kura` flag for the account
  (`FunWithFlags.disable(:kura, for_actor: account)`); the resolver
  immediately returns `[]` from the `:kura` path and the CLI falls back
  to the global Tuist-hosted endpoints. The mesh keeps running but
  receives no new traffic.
- **Image-side:** re-run the workflow with the previous Kura image tag.
  The compatibility harness
  ([`kura/test/e2e/kura_compatibility_rollout.sh`](../../kura/test/e2e/kura_compatibility_rollout.sh))
  validates `PREV → HEAD → PREV` on the same volumes, so adjacent
  versions are safe to swap.
