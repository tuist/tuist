# Syself Onboarding Guide — Tuist Server on Kubernetes

This document is the step-by-step we follow to stand up a Syself-managed Kubernetes cluster on Hetzner and deploy the Tuist server to it. It covers both the **initial provisioning** and the **secrets bootstrap** — the non-obvious glue that GitHub Actions and the Helm chart assume is already in place.

This is a **proof-of-concept** run. Production cutover will follow in a separate runbook (`infra/k8s/MIGRATION.md`) once we've validated the shape end-to-end.

---

## Prerequisites

- A Syself account ([syself.com](https://syself.com)) with platform access
- A Hetzner Cloud project (Syself provisions nodes into your account, not theirs)
- Cloudflare account with API token scoped to `Zone.DNS:Edit` on `tuist.dev`
- The CLI tools: `kubectl`, `helm` (installed via `mise use -g kubectl helm`)
- The 1Password CLI (`op`) — we already use it for other secrets

## 1. Provision the cluster

From the Syself dashboard, create a new workload cluster with the following shape. These are the starting values from `infra/k8s/provider-evaluation.md`; tune later based on real usage.

| Field | Staging | Production |
|---|---|---|
| Region | Hetzner NBG1 (Nuremberg) | Hetzner NBG1 (Nuremberg) |
| Control-plane HA | single-master | 3-master HA |
| Worker pool | 1× CPX21 (3 vCPU / 4 GB) | 2× CPX31 (4 vCPU / 8 GB) |
| Autoscaler | off | on, max 5 |
| Kubernetes version | current stable | current stable |
| CNI | Cilium (Syself default) | Cilium |
| CSI | `hcloud-volumes` | `hcloud-volumes` |

Syself exposes provisioning as Cluster API CRDs on their management cluster. The dashboard walks you through generating those; save the resulting kubeconfig files securely in 1Password:

- `Tuist / Infra / kubeconfig-staging`
- `Tuist / Infra / kubeconfig-production`

Verify access:

```bash
kubectl --kubeconfig /tmp/kubeconfig-staging get nodes
```

## 2. Install the platform chart

The platform chart (`infra/helm/platform/`) sets up cert-manager, ingress-nginx, external-dns, and external-secrets-operator. It runs **once per cluster**.

### 2a. Create the Cloudflare API token Secret

Create this out-of-band so the token never lands in a values file or Helm history:

```bash
export KUBECONFIG=/tmp/kubeconfig-staging

kubectl create namespace platform
kubectl -n platform create secret generic cloudflare-api-token \
  --from-literal=api-token="$(op read 'op://Tuist/Cloudflare/api-token')"
```

### 2b. Install

```bash
cd infra/helm/platform
helm dependency update .

helm upgrade --install platform . \
  -n platform \
  --set letsencrypt.email=ops@tuist.dev
```

Wait for the ingress-nginx LoadBalancer to come up; Hetzner will provision a public IP. That IP is what Cloudflare will point `cloud-staging.tuist.dev` / `cloud.tuist.dev` at once external-dns syncs the records.

```bash
kubectl -n platform get svc
# Look for EXTERNAL-IP on the ingress-nginx-controller service.
```

## 3. Bootstrap the server secrets

The Tuist server image bakes encrypted `priv/secrets/<env>.yml.enc` files in. The `MASTER_KEY` that decrypts them is mounted at runtime via a k8s Secret created by the Helm chart — we pass it to `helm upgrade` via `--set server.masterKey=…`, which the chart materializes into the `app-secrets` Secret.

In addition to the master key, the chart needs these values that live outside the encrypted file:

| Value | Source | Chart key |
|---|---|---|
| Postgres password | Supabase dashboard | `postgresql.external.password` |
| ClickHouse URL | ClickHouse Cloud dashboard | `clickhouse.external.url` |
| Tigris access / secret keys | Tigris dashboard | `objectStorage.external.{accessKey,secretKey}` |

Store them in 1Password so they feed CI:

```bash
op item create \
  --vault Tuist \
  --category='API Credential' \
  --title='tuist-server-k8s-staging' \
  master_key="$(cat priv/secrets/stag.key)" \
  database_password='<from Supabase>' \
  clickhouse_url='<from ClickHouse Cloud>' \
  tigris_access_key='<from Tigris>' \
  tigris_secret_key='<from Tigris>'
```

Then mirror these into GitHub Actions Secrets (scoped to the `server-k8s-staging` Environment):

- `KUBECONFIG_STAGING` — `base64 -i /tmp/kubeconfig-staging`
- `MASTER_KEY_STAGING`
- `DATABASE_PASSWORD_STAGING`
- `CLICKHOUSE_URL_STAGING`
- `TIGRIS_ACCESS_KEY_STAGING`
- `TIGRIS_SECRET_KEY_STAGING`

(Repeat with the `PRODUCTION` suffix for the production Environment, and make that Environment require manual approval.)

## 4. First deploy

### Manual first (to validate)

Exercise the Helm chart with a locally-run command before we trust CI:

```bash
export KUBECONFIG=/tmp/kubeconfig-staging

cd infra/helm/tuist
helm upgrade --install tuist . \
  -n tuist-staging --create-namespace \
  -f values-managed-common.yaml \
  -f values-managed-staging.yaml \
  --set server.image.tag="sha-$(git rev-parse --short=12 HEAD)" \
  --set server.masterKey="$(op read 'op://Tuist/tuist-server-k8s-staging/master_key')" \
  --set postgresql.external.password="$(op read 'op://Tuist/tuist-server-k8s-staging/database_password')" \
  --set clickhouse.external.url="$(op read 'op://Tuist/tuist-server-k8s-staging/clickhouse_url')" \
  --set objectStorage.external.accessKey="$(op read 'op://Tuist/tuist-server-k8s-staging/tigris_access_key')" \
  --set objectStorage.external.secretKey="$(op read 'op://Tuist/tuist-server-k8s-staging/tigris_secret_key')" \
  --atomic --timeout 10m
```

The migration Job runs as a `pre-install`/`pre-upgrade` Helm hook, so `helm upgrade` will block until migrations succeed.

Watch the rollout:

```bash
kubectl -n tuist-staging rollout status deploy/tuist-server
kubectl -n tuist-staging logs -l app.kubernetes.io/component=server -f
```

Once `kubectl -n tuist-staging get ingress` shows an `ADDRESS`, and external-dns has written the Cloudflare A record, verify:

```bash
curl -v https://cloud-staging.tuist.dev/ready
```

### Then via CI

After the manual smoke test passes, trigger the CI workflow:

```bash
gh workflow run server-deployment.yml -f environment=staging
```

## 5. Observability wiring

Grafana Cloud scraping today runs from an external Alloy instance configured in `infra/grafana-alloy/`. For the Syself cluster we deploy Alloy **in-cluster** as a DaemonSet so it can discover pod endpoints via the k8s API.

Follow-up PR — not covered here. The current setup keeps the external Alloy running and pointed at the cluster's Ingress-exposed `/metrics` endpoint, which is good enough for the POC.

## 6. Teardown (when comparing providers)

To destroy everything on Syself for this POC and try another provider:

```bash
export KUBECONFIG=/tmp/kubeconfig-staging
helm uninstall tuist -n tuist-staging
kubectl delete namespace tuist-staging
helm uninstall platform -n platform
kubectl delete namespace platform
```

Then delete the cluster via the Syself dashboard. Hetzner will release the nodes.

---

## Troubleshooting crib

**Ingress 503 / cert not issued**

- `kubectl -n platform describe certificate cloud-staging-tuist-dev-tls` shows the ACME challenge status.
- Most common failure: Cloudflare token missing `Zone.DNS:Edit` scope.

**Pods crash looping with `** (ArgumentError) argument error`**

- Almost always means `MASTER_KEY` is wrong or missing. Secrets can't decrypt → secrets map is empty → a function expecting `database_url()` returns nil → crash.
- Check the app-secrets Secret:
  ```bash
  kubectl -n tuist-staging get secret tuist-app-secrets -o jsonpath='{.data.server-master-key}' | base64 -d | wc -c
  # Expect 32 bytes.
  ```

**Helm upgrade times out on the migration Job**

- `kubectl -n tuist-staging logs job/tuist-server-migrate-<revision>` shows the Ecto output.
- Common: Supabase pooler needs `TUIST_USE_SSL_FOR_DATABASE=1` (default for the overlay) and the `ssl: verify_none` workaround in `runtime.exs`. Check the log for TLS errors.

**external-dns isn't writing records**

- `kubectl -n platform logs deploy/external-dns` will show 403 / scope errors if the Cloudflare token is wrong.
- Verify `txtOwnerId` isn't colliding with another cluster managing the same zone.
