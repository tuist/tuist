# Atlas Cluster Onboarding Runbook

End-to-end: stand up a fresh Atlas workload cluster on Hetzner under the
self-hosted CAPI + caph management cluster (`tuist-mgmt`), and deploy
Atlas to it. Single environment (`production`), single Phoenix release,
in-cluster CloudNativePG with backups to Hetzner Object Storage.

Most of this is one-time. Day-to-day deploys go through the
`Deploy` GitHub Actions workflow.

## Prerequisites

- Operator access to `tuist-mgmt` (the self-hosted management cluster
  bootstrapped in [tuist/tuist#10586](https://github.com/tuist/tuist/pull/10586)). The kubeconfig is in
  1Password as `kubeconfig-tuist-mgmt`. Reachable on the tuist.dev
  tailnet at `100.92.208.109`; kube-apiserver is on the public IP at
  `:6443`.
- A Cloudflare API token scoped to `Zone.DNS:Edit` on `tuist.dev`.
- A 1Password Service Account token with read access to the
  `atlas-k8s-production` vault (created in §5).
- CLI tools (mise):
  ```bash
  mise use -g kubectl helm clusterctl
  ```
- `op` (1Password CLI), `gh`, `jq`.

Atlas reuses tuist's `org-tuist` namespace on `tuist-mgmt` and inherits
its `hetzner` Secret (workload Hetzner Cloud project + `tuist-ops` SSH
key). No separate Hetzner project, API token, or SSH key for atlas —
the `tuist-hcloud` ClusterClass hardcodes `hetznerSecretRef.name:
hetzner`, so the workload VMs land in tuist's Hetzner project. Full
blast-radius isolation would need a dedicated org namespace (and a
per-namespace `hetzner` Secret); accepted as a v1 constraint.

## 1. Provision the workload cluster

```bash
export KUBECONFIG=~/.kube/tuist-mgmt.yaml

# Sanity: tuist-hcloud ClusterClass is present.
kubectl -n org-tuist get clusterclass tuist-hcloud

# The Cluster CR is NOT applied by hand any more: it is reconciled by Flux
# from tuist/tuist (infra/k8s/clusters/workloads/atlas/cluster.yaml).
# Applying a copy from here would fight Flux and re-introduce drift.
kubectl -n org-tuist get cluster atlas-production -w   # 10–20 min on first boot
```

Pull the workload kubeconfig out of the CAPI-managed Secret. Nodes
will be `NotReady` at this point — that's expected; CNI / cloud
controller / CSI install in §2 below.

```bash
kubectl -n org-tuist get secret atlas-production-kubeconfig \
  -o jsonpath='{.data.value}' | base64 -d > ~/.kube/atlas-production.yaml
chmod 600 ~/.kube/atlas-production.yaml
export KUBECONFIG=~/.kube/atlas-production.yaml
kubectl get nodes   # 3 CP + 2 workers, all NotReady until §2 completes
```

## 2. Workload bootstrap: CNI + cloud controller + CSI

`tuist-hcloud` deliberately ships a bare kubeadm + kube-apiserver, with
`skipPhases: [addon/kube-proxy]`. Cilium replaces kube-proxy, the
hcloud-cloud-controller-manager (HCCM) sets node `providerID`s and
reconciles `Service type=LoadBalancer` to Hetzner LBs, and the
hcloud-csi-driver provisions the `hcloud-volumes` `StorageClass` that
backs the CNPG PVCs. None of these come from the Cluster CR; install
them now, in this order. Cribbed from the bootstrap configs in
[tuist/tuist `infra/k8s/mgmt/bootstrap/`](https://github.com/tuist/tuist/tree/main/infra/k8s/mgmt/bootstrap).

```bash
# Workload-side `hetzner` Secret. HCCM and hcloud-csi both read it
# (key: `hcloud`). The token is the same one the mgmt-side `hetzner`
# Secret in `org-tuist` carries — atlas inherits tuist's workload
# Hetzner project, so we just mirror the value.
HCLOUD_TOKEN=$(KUBECONFIG=~/.kube/tuist-mgmt.yaml kubectl -n org-tuist \
  get secret hetzner -o jsonpath='{.data.hcloud}' | base64 -d)
kubectl -n kube-system create secret generic hetzner \
  --from-literal=hcloud="$HCLOUD_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
unset HCLOUD_TOKEN

# Cilium — must be first, nothing networks without it.
# `k8sServiceHost` is the cluster's API LB IP from the mgmt-side
# HetznerCluster status; needed because we skip kube-proxy.
helm repo add cilium https://helm.cilium.io
API_HOST=$(KUBECONFIG=~/.kube/tuist-mgmt.yaml kubectl -n org-tuist \
  get cluster atlas-production -o jsonpath='{.spec.controlPlaneEndpoint.host}')
helm upgrade --install cilium cilium/cilium --version 1.18.7 \
  --namespace kube-system \
  -f <(curl -fsSL https://raw.githubusercontent.com/tuist/tuist/main/infra/k8s/mgmt/bootstrap/cilium-values.yaml) \
  --set "k8sServiceHost=$API_HOST" --set "k8sServicePort=443"

# hcloud-cloud-controller-manager — provider IDs + LoadBalancer Services.
helm repo add hcloud https://charts.hetzner.cloud
helm upgrade --install hccm hcloud/hcloud-cloud-controller-manager \
  --namespace kube-system \
  -f <(curl -fsSL https://raw.githubusercontent.com/tuist/tuist/main/infra/k8s/mgmt/bootstrap/hccm-values.yaml) \
  --set env.HCLOUD_LOAD_BALANCERS_LOCATION.value=fsn1 \
  --wait --timeout 3m

# hcloud-csi-driver — provisions the `hcloud-volumes` StorageClass for CNPG PVCs.
helm upgrade --install hcloud-csi hcloud/hcloud-csi \
  --namespace kube-system \
  -f <(curl -fsSL https://raw.githubusercontent.com/tuist/tuist/main/infra/k8s/mgmt/bootstrap/hcloud-csi-values.yaml) \
  --wait --timeout 3m

# Wait for nodes to flip Ready.
kubectl wait --for=condition=Ready nodes --all --timeout=5m
```

## 3. Platform bootstrap (one-time)

cert-manager, ingress-nginx, external-dns, external-secrets-operator,
and CloudNativePG. Each one is a single `helm install`.

```bash
# cert-manager
helm repo add jetstack https://charts.jetstack.io
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace --set crds.enabled=true

# ingress-nginx (Hetzner LB annotations on the Service get a cloud LB).
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  --set controller.service.annotations."load-balancer\.hetzner\.cloud/location"=fsn1 \
  --set controller.service.annotations."load-balancer\.hetzner\.cloud/name"=atlas-production-ingress

# Cloudflare token Secret (external-dns reads it)
kubectl create namespace external-dns --dry-run=client -o yaml | kubectl apply -f -
kubectl -n external-dns create secret generic cloudflare-api-token \
  --from-literal=token="$(op read 'op://Founders/cloudflare-tuist-dns/credential')"

helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm upgrade --install external-dns external-dns/external-dns \
  -n external-dns \
  --set provider=cloudflare \
  --set 'sources={ingress}' \
  --set 'domainFilters={tuist.dev}' \
  --set env[0].name=CF_API_TOKEN \
  --set env[0].valueFrom.secretKeyRef.name=cloudflare-api-token \
  --set env[0].valueFrom.secretKeyRef.key=token

# external-secrets-operator
helm repo add external-secrets https://charts.external-secrets.io
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace --set installCRDs=true

# CloudNativePG operator (cluster-scoped CRDs + controller)
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm upgrade --install cnpg cnpg/cloudnative-pg \
  -n cnpg-system --create-namespace
```

### Let's Encrypt ClusterIssuer

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ops@tuist.io
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx
YAML
```

## 4. 1Password vault + ClusterSecretStore

Atlas gets its own 1Password vault, scoped tightly: a dedicated **Service
Account** with read-only access to it (and nothing else). Same pattern
tuist/tuist uses — one per-environment vault, one per-environment SA, no
shared credentials.

1. In the 1Password admin console, create a new vault named
   `atlas-k8s-production`.
2. Create a **Service Account** named `atlas-k8s-production-sa`. Grant
   it **read-only** access to that vault and nothing else. 1Password
   auto-generates a credential item titled
   `Service Account Auth Token: atlas-k8s-production-sa` in your default
   vault — leave it there (matches the convention tuist uses for its
   SA tokens). It's the only copy of the token, so don't delete it.

Then stash the SA token in the cluster and register the
ClusterSecretStore — the `vault:` field below is what scopes ESO
lookups; per-`ExternalSecret` `remoteRef.key` is just `<item>/<field>`.

```bash
kubectl create namespace onepassword --dry-run=client -o yaml | kubectl apply -f -
kubectl -n onepassword create secret generic onepassword-sa-token \
  --from-literal=token="$(op read 'op://Founders/<atlas-1p-sa-uuid>/credential')" \
  --dry-run=client -o yaml | kubectl apply -f -

cat <<'YAML' | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: onepassword
spec:
  provider:
    onepasswordSDK:
      vault: atlas-k8s-production
      auth:
        serviceAccountSecretRef:
          name: onepassword-sa-token
          namespace: onepassword
          key: token
YAML

kubectl get clustersecretstore onepassword   # READY=True
```

## 5. Populate the 1Password vault

Each row is a separate item in the `atlas-k8s-production` vault, mapped
1:1 to an `ExternalSecret` declared by `infra/helm/atlas/values.yaml`
under `externalSecrets.items` / `postgres.backup.externalSecret` / the
GHCR pull secret block. Adding a new app secret means: add an item in
1P, add a line in `values.yaml`, redeploy.

| Item                              | Field           | Value                                                                |
| --------------------------------- | --------------- | -------------------------------------------------------------------- |
| `atlas-secret-key-base`           | `password`      | `mix phx.gen.secret`                                                 |
| `atlas-encryption-key`            | `password`      | `elixir -e 'IO.puts(Base.encode64(:crypto.strong_rand_bytes(32)))'`  |
| `atlas-license-signing-key`       | `password`      | Base64-encoded 32-byte Ed25519 private key generated from cryptographically secure random bytes. Coordinate its corresponding public key with the Tuist consumer before enabling Atlas-issued licenses, while retaining trust for existing Keygen certificates. |
| `atlas-google-oauth`              | `username`      | Google OAuth client ID                                               |
| `atlas-google-oauth`              | `credential`    | Google OAuth client secret                                           |
| `atlas-super-admin`               | `password`      | Random — gates `/admin/*` HTTP basic auth                            |
| `atlas-stripe-api-key`            | `password`      | Stripe live secret key (from Stripe dashboard → Developers → API keys) |
| `atlas-sentry`                    | `dsn`           | Sentry project DSN (from Sentry → Project Settings → Client Keys)    |
| `atlas-slack-company`             | `credential`    | Slack bot token for the company Tuist Atlas Slack app                |
| `atlas-slack-company`             | `password`      | Slack signing secret for the company Tuist Atlas Slack app           |
| `atlas-hive-inference-token`      | `credential`    | Hive inference token for Atlas language-model requests               |
| `atlas-hive-embedding-token`      | `credential`    | Hive token for Atlas document embedding requests                     |
| `atlas-granola-api-key`           | `credential`    | Granola API key for meeting-note ingestion                           |
| `atlas-inbox-webhook-secret`      | `password`      | Shared secret signing inbound emails from the Cloudflare inbox Worker; same value goes into the Worker via `wrangler secret put ATLAS_INBOX_WEBHOOK_SECRET` from `workers/inbox/` |
| `atlas-postgres-backup`           | `username`      | Hetzner Object Storage access key ID                                 |
| `atlas-postgres-backup`           | `credential`    | Hetzner Object Storage secret access key                             |
| `atlas-object-storage`            | `username`      | Hetzner Object Storage access key ID for app-level object persistence |
| `atlas-object-storage`            | `credential`    | Hetzner Object Storage secret access key for app-level object persistence |
| `atlas-object-storage`            | `bucket`        | Hetzner Object Storage bucket name for app-level object persistence  |
| `atlas-pingen`                    | `username`      | Pingen client ID                                                       |
| `atlas-pingen`                    | `password`      | Pingen client secret                                                   |
| `atlas-pingen`                    | `organisation_id` | Pingen organisation ID                                               |
| `atlas-tuist-gmbh`                | `sender_name`, `sender_street`, `sender_postal_code`, `sender_city`, `sender_country` | Tuist GmbH sender profile for tax-certificate requests |
| `atlas-tuist-gmbh`                | `tax_id`, `vat_id`, `signatory_title`, `foundation_date`, `legal_form`, `signing_location` | Tuist GmbH company details for tax-certificate requests |
| `atlas-tuist-gmbh`                | `tax_office_name`, `tax_office_street`, `tax_office_postal_code`, `tax_office_city` | Default German tax-office recipient for tax-certificate requests |
| `atlas-ghcr-pull`                 | `notesPlain`    | base64 of `~/.docker/config.json` for `ghcr.io` (see below)          |

These map 1:1 to `externalSecrets.items` / `postgres.backup.externalSecret` /
`externalSecrets.pullSecret` in `infra/helm/atlas/values.yaml`. If you add a
new app secret, add it both there and here.

To rotate any of these, update the field in 1P. ESO re-syncs on the
chart's `refreshInterval` (default 1h); force an immediate sync with
`kubectl -n atlas-production annotate externalsecret atlas-app
external-secrets.io/force-sync=$(date +%s) --overwrite`. The
`external-secrets.io/` prefix is required: a bare `force-sync`
annotation is silently ignored and the `LAST SYNC` age won't reset.

ESO updates the K8s `atlas-app` Secret out-of-band, which the Deployment
consumes via `envFrom` — and pods only read `envFrom` at process start.
There is no chart-level mechanism to trigger a rollout when the synced
data changes (a Helm `checksum/secret` annotation wouldn't help: Helm
hashes the rendered template, not the ESO-fetched values). After
rotating, restart the pods so they pick up the new value:

```bash
kubectl -n atlas-production rollout restart deployment/atlas
kubectl -n atlas-production rollout status deployment/atlas
```

If we ever rotate often enough that this becomes a footgun, install
[stakater/Reloader](https://github.com/stakater/Reloader) and annotate
the Deployment — it watches Secret data and rolls Deployments
automatically. Not worth the extra controller for the current cadence.

Generate the GHCR pull-secret payload:

```bash
# Create a GitHub Personal Access Token (classic) with `read:packages`,
# scoped to the `tuist` org. Store the token itself in 1P too if you
# want — only the dockerconfigjson is referenced by the chart.
USER='<your-gh-username>'
PAT='<the-pat>'
AUTH=$(printf '%s:%s' "$USER" "$PAT" | base64)
DCJ=$(printf '{"auths":{"ghcr.io":{"auth":"%s"}}}' "$AUTH" | base64)
echo "$DCJ"
# Paste into the `notesPlain` field of `atlas-ghcr-pull` in 1P.
```

## 6. Hetzner Object Storage bucket

Backups and app-level persisted objects land in Hetzner Object Storage.
Create the buckets in the same `fsn1` region as the cluster to keep
transfer free.

```bash
# Hetzner Cloud Console → Object Storage → Create bucket
#   Name: atlas-postgres-backups
#   Region: fsn1
#   Access keys: create a new pair, save to 1P (item `atlas-postgres-backup`).

# Hetzner Cloud Console → Object Storage → Create bucket
#   Name: atlas-object-storage
#   Region: fsn1
#   Access keys: create a new pair, save to 1P (item `atlas-object-storage`).
```

## 7. CI ServiceAccount + kubeconfig in 1Password

Same pattern tuist/tuist uses: the deployer kubeconfig is stored as a
Document item in the per-cluster 1P vault (`atlas-k8s-production`),
fetched at deploy time via the read-only `atlas-k8s-production-sa`
Service Account. Nothing cluster-shaped lives in GitHub repo/env
secrets — the only GH secret is `OP_SERVICE_ACCOUNT_TOKEN`, which
gates access to the vault.

```bash
export KUBECONFIG=~/.kube/atlas-production.yaml
kubectl apply -f infra/k8s/ci-service-account.yaml

SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl -n atlas-production get secret github-actions-deployer-token \
  -o jsonpath='{.data.ca\.crt}')
TOKEN=$(kubectl -n atlas-production get secret github-actions-deployer-token \
  -o jsonpath='{.data.token}' | base64 -d)

cat > /tmp/atlas-ci-kubeconfig.yaml <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: atlas-production
    cluster:
      server: $SERVER
      certificate-authority-data: $CA
contexts:
  - name: ci
    context:
      cluster: atlas-production
      namespace: atlas-production
      user: github-actions-deployer
users:
  - name: github-actions-deployer
    user:
      token: $TOKEN
current-context: ci
EOF

KUBECONFIG=/tmp/atlas-ci-kubeconfig.yaml kubectl -n atlas-production get pods   # sanity

# Upload to 1Password as a Document item.
# Uses your own (admin-level) op session, not the read-only SA token —
# the SA can't write.
op document create /tmp/atlas-ci-kubeconfig.yaml \
  --title "kubeconfig: atlas-production" \
  --vault atlas-k8s-production
shred -u /tmp/atlas-ci-kubeconfig.yaml

# In the GitHub repo, set OP_SERVICE_ACCOUNT_TOKEN on the `production`
# environment to the SA token from
# `op://Founders/Service Account Auth Token: atlas-k8s-production-sa/credential`.
# That's the only deploy-time secret CI needs; the workflow fetches the
# kubeconfig itself with `op document get` (see .github/workflows/deploy.yml).
gh secret set OP_SERVICE_ACCOUNT_TOKEN --env production --repo tuist/atlas \
  --body "$(op read 'op://Founders/Service Account Auth Token: atlas-k8s-production-sa/credential')"
```

## 8. First deploy

### Manual dry-run

```bash
export KUBECONFIG=~/.kube/atlas-production.yaml

helm upgrade --install atlas infra/helm/atlas \
  -n atlas-production --create-namespace \
  --set image.tag="sha-$(git rev-parse --short=12 HEAD)" \
  --atomic --timeout 10m
```

Watch:

```bash
kubectl -n atlas-production rollout status deploy/atlas
kubectl -n atlas-production logs -l app.kubernetes.io/name=atlas -f
```

Once the LB has an IP and DNS has propagated:

```bash
curl -v https://atlas.tuist.dev/ready
```

### Then via CI

After the manual smoke test passes, normal flow takes over: every push
to `main` runs `.github/workflows/deploy.yml`, which builds the image
and runs the same `helm upgrade` against `production`.

## 9. Restoring Postgres from a backup

CNPG handles PITR via the same `barmanObjectStore`. To restore into a
new Cluster (e.g. for a clone or after a destructive incident):

```bash
# Create an alternate Cluster CR with `bootstrap.recovery.source` pointing
# at the existing cluster's backup catalog, and an `externalClusters`
# entry referencing the same S3 bucket + credentials Secret.
# Reference: https://cloudnative-pg.io/documentation/current/recovery/
```

Don't try to restore in-place over a live cluster — bootstrap a sibling,
verify, swap the `Service` if needed, then delete the old `Cluster`.

## 10. Teardown

```bash
export KUBECONFIG=~/.kube/tuist-mgmt.yaml
kubectl -n org-tuist delete cluster atlas-production
```

Hetzner Object Storage bucket + DNS records are yours to delete
separately if you're done.

## Troubleshooting

**Backup never appears in the bucket.**
`kubectl -n atlas-production describe cluster <name>-postgres` — look for
the `BackupNotConfigured` / `Failed` conditions. Most often the
credentials ExternalSecret hasn't synced; check
`kubectl -n atlas-production get externalsecret`.

**Migration job fails: "ENCRYPTION_KEY is missing".**
ESO sync issue. `kubectl -n atlas-production describe externalsecret atlas-app`
shows the upstream error from 1Password.

**Ingress LB stuck `<pending>`.**
The Hetzner cloud-controller-manager needs the `load-balancer.hetzner.cloud/location`
annotation on the Service, AND HCCM itself needs to be running. `kubectl
describe svc -n ingress-nginx ingress-nginx-controller` should show the
annotation; if not, re-run the ingress-nginx `helm upgrade` in §3. If
the annotation is there but the LB still doesn't materialize, check
`kubectl -n kube-system get pods -l app.kubernetes.io/name=hcloud-cloud-controller-manager`
and re-run the HCCM `helm upgrade` from §2.
