# GKE Onboarding Guide — Tuist Server on Kubernetes

Step-by-step to stand up a GKE cluster in `europe-west3` (Frankfurt) and deploy the Tuist server to it. Companion to `syself-onboarding.md` — structurally identical, differs only in where the cluster lives and how it's provisioned.

Scope here is **staging only**. Canary + production will follow once staging is green. This is also our provider-comparison run vs Syself — we want to feel the end-to-end on GKE before locking in a provider.

---

## Prerequisites

- A GCP account with billing enabled. New accounts get a $300 / 90-day credit.
- A Cloudflare account with an API token scoped to `Zone.DNS:Edit` on `tuist.dev`.
- CLI tools — install once via mise:
  ```bash
  mise use -g gcloud kubectl helm
  ```
- The 1Password CLI (`op`) for the secrets bootstrap.

## 1. Provision the cluster

### 1a. Set up the GCP project

We create a fresh `tuist-staging` GCP project — isolated from the legacy `tuist-cloud-*` projects used by Render. Isolation keeps budgets, IAM, and resource inventory clean per environment.

```bash
gcloud auth login

# Create the staging project (project IDs are globally unique; fall back to
# tuist-staging-<random-suffix> if "tuist-staging" is taken).
gcloud projects create tuist-staging --name="Tuist Staging"
gcloud config set project tuist-staging

# Link billing (reuses the existing Tuist billing account).
gcloud billing projects link tuist-staging \
  --billing-account=$(gcloud billing accounts list --format='value(name)' | head -1 | sed 's|billingAccounts/||')

# Enable required APIs.
gcloud services enable container.googleapis.com compute.googleapis.com
```

### 1b. Create the cluster

For staging we use a small **zonal Standard cluster** in `europe-west3-a`. Zonal is cheaper than regional (no control-plane HA), which is fine for staging. Production will be regional.

```bash
gcloud container clusters create tuist-staging \
  --zone europe-west3-a \
  --num-nodes 2 \
  --machine-type e2-standard-2 \
  --release-channel regular \
  --disk-type pd-standard \
  --disk-size 50
```

Expected runtime: ~5 minutes.

> Alternative: **Autopilot** (pay-per-pod, zero node management) —
> `gcloud container clusters create-auto tuist-staging --region europe-west3`.
> Simpler but pricier for our idle POC footprint.

### 1c. Grab the kubeconfig

```bash
gcloud container clusters get-credentials tuist-staging --zone europe-west3-a

# Verify:
kubectl get nodes
```

Save the merged kubeconfig to 1Password if you want CI access to this cluster:

```bash
# Produces a kubeconfig that uses a GCP service account key (portable to CI).
gcloud iam service-accounts create tuist-staging-deployer --display-name="Tuist staging deployer"
gcloud projects add-iam-policy-binding tuist-staging \
  --member="serviceAccount:tuist-staging-deployer@tuist-staging.iam.gserviceaccount.com" \
  --role="roles/container.developer"
gcloud iam service-accounts keys create /tmp/sa-key.json \
  --iam-account=tuist-staging-deployer@tuist-staging.iam.gserviceaccount.com
op item create --vault Tuist --category='API Credential' \
  --title='gke-poc-deployer' \
  sa_key="$(cat /tmp/sa-key.json)"
rm /tmp/sa-key.json
```

## 2. Install the platform chart

The platform chart (`infra/helm/platform/`) installs cert-manager, ingress-nginx, external-dns, and external-secrets. **Once per cluster**.

### 2a. Create the Cloudflare API token Secret

```bash
kubectl create namespace platform
kubectl -n platform create secret generic cloudflare-api-token \
  --from-literal=api-token="$(op read 'op://Tuist/Cloudflare/api-token')"
```

### 2b. Install with the GKE overlay

```bash
cd infra/helm/platform
helm dependency update .

helm upgrade --install platform . \
  -n platform \
  -f values-gke.yaml \
  --set letsencrypt.email=ops@tuist.dev
```

Wait for the ingress-nginx LoadBalancer to get a public IP:

```bash
kubectl -n platform get svc platform-ingress-nginx-controller -w
```

Expected: a GCP external IP appears within ~2 minutes.

## 3. Bootstrap server secrets

Same dance as the Syself onboarding (§3 there). Put these in 1Password:

- `master_key` — contents of `server/priv/secrets/stag.key`
- `database_password` — Supabase staging password
- `clickhouse_url` — ClickHouse Cloud HTTPS URL (port 8443)
- `tigris_access_key` / `tigris_secret_key` — Tigris API credentials

Then copy them into GitHub Actions secrets (scoped to the `server-k8s-staging` Environment):

- `KUBECONFIG_STAGING` — output of `kubectl config view --raw --flatten --minify | base64`
- `MASTER_KEY_STAGING`
- `DATABASE_PASSWORD_STAGING`
- `CLICKHOUSE_URL_STAGING`
- `TIGRIS_ACCESS_KEY_STAGING`
- `TIGRIS_SECRET_KEY_STAGING`

## 4. First deploy

### Manual dry-run

```bash
# Assumes you still have the GKE context active.
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

> You'll need a server image pushed to GHCR first. Either push it manually (`docker build … && docker push`) or trigger the CI workflow once and re-run this step pointing at the SHA it published.

Rollout:

```bash
kubectl -n tuist-staging rollout status deploy/tuist-server
kubectl -n tuist-staging logs -l app.kubernetes.io/component=server -f
```

Once external-dns has written `cloud-staging.tuist.dev` → the ingress IP, and cert-manager has issued the cert:

```bash
curl -v https://cloud-staging.tuist.dev/ready
```

### Then via CI

```bash
gh workflow run server-deployment.yml -f environment=staging
```

## 5. Observability

Same as Syself — Grafana Cloud is already the target. For this POC keep the external Alloy setup; if we keep GKE long-term we'd move Alloy in-cluster as a DaemonSet.

## 6. Teardown (if we drop GKE for Syself)

An idle GKE cluster is ~$5-10/day, so if we choose Syself instead, shut this down.

```bash
helm uninstall tuist -n tuist-staging
kubectl delete namespace tuist-staging
helm uninstall platform -n platform
kubectl delete namespace platform
gcloud container clusters delete tuist-staging --zone europe-west3-a --quiet
```

**Do not delete the `tuist-staging` project** — it's the legacy Render staging project and holds other resources. Only delete the GKE cluster we created.

---

## Troubleshooting crib

**`gcloud container clusters create` fails with a quota error**
The default compute quota on a fresh GCP project is low. Request a bump via the GCP console or pick a smaller machine type.

**ingress-nginx LoadBalancer stuck in `<pending>`**
Most common on new GCP projects: the `compute.networks.use` permission hasn't propagated yet. Give it a minute, then `kubectl -n platform describe svc platform-ingress-nginx-controller`. Quota issues also show up here.

**cert-manager certificate stuck at `Issuing`**
```bash
kubectl -n tuist-staging describe certificate cloud-staging-tuist-dev-tls
kubectl -n tuist-staging get challenges
```
The Cloudflare DNS-01 challenge needs ~60-90s to propagate. If it's longer than 5 min, verify the Cloudflare token has `Zone.DNS:Edit` on the `tuist.dev` zone.

**Server pod CrashLoopBackOff with `** (ArgumentError) argument error`**
`MASTER_KEY` is wrong or missing. See the equivalent note in `syself-onboarding.md` §Troubleshooting.

**`helm upgrade` times out on the pre-install hook (migrations)**
```bash
kubectl -n tuist-staging logs job/tuist-server-migrate-<revision>
```
Usually a DB connection issue (Supabase pooler + SSL). Check `TUIST_USE_SSL_FOR_DATABASE=1` is set (it is in the overlay by default).
