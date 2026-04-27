# Syself Onboarding Guide — Tuist Server on Kubernetes

Stand up a Syself-managed Kubernetes cluster on Hetzner and deploy the Tuist server to it.

Syself Apalla runs a **management cluster** as SaaS. You apply [Cluster API](https://cluster-api.sigs.k8s.io/) CRs against that management cluster, and the `caph` provider spins up nodes in your Hetzner project. You never operate the management cluster — you just talk to it.

Target here is **staging**. Production follows the same shape with HA tuning bumped.

---

## Prerequisites

- Access to the Syself Apalla management cluster. Grab the kubeconfig template from [Syself's docs](https://syself.com/docs/hetzner/apalla/getting-started/accessing-the-management-cluster) — it's the same file for every Apalla customer; auth is gated per-person via SSO at first `kubectl` call.
- A Hetzner Cloud project with API access enabled.
- A Cloudflare account with an API token scoped to `Zone.DNS:Edit` on `tuist.dev`.
- CLI tools installed via mise:
  ```bash
  mise use -g kubectl helm clusterctl
  ```
  Plus the kubelogin plugin for the management cluster OIDC login:
  ```bash
  kubectl krew install oidc-login
  ```
- The 1Password CLI (`op`).

## 1. Access the management cluster

Download the kubeconfig template from <https://syself.com/docs/hetzner/apalla/getting-started/accessing-the-management-cluster>. It uses `kubectl oidc-login` as the auth plugin — the first `kubectl` invocation opens a browser, you SSO in, and a short-lived token is cached in `~/.kube/cache/oidc-login/`.

```bash
# Save the kubeconfig you downloaded. The `namespace:` field in the
# context must be set to `org-tuist` (our Syself-managed org namespace).
mkdir -p ~/.kube
cp /path/to/syself-mgmt-kubeconfig.yaml ~/.kube/tuist-syself-mgmt.yaml
chmod 600 ~/.kube/tuist-syself-mgmt.yaml

export KUBECONFIG=~/.kube/tuist-syself-mgmt.yaml

# Triggers the browser-based OIDC flow on first use.
kubectl get clusters
```

Logout (invalidate cached token) later with:

```bash
rm -rf ~/.kube/cache/oidc-login
```

## 2. Prepare the Hetzner account

Syself provisions into **your** Hetzner Cloud account. We currently use cloud VMs only (no Hetzner Robot bare-metal) — see the migration PR's "Why not bare metal" section for the reasoning.

1. **Create a Hetzner Cloud project** at <https://console.hetzner.cloud/projects> (e.g. `tuist-syself`). All three managed clusters share one Hetzner project because Syself's ClusterClass hardcodes the Kubernetes Secret name that holds the API token.
2. **Generate an API token** in that project with **read + write** permissions. Save it to 1Password immediately — Hetzner only shows it once.
   ```bash
   op item create --vault Founders --category='API Credential' \
     --title='hetzner-tuist-syself' \
     credential='<paste token>'
   ```
3. **Upload an SSH key pair** to the project (Syself embeds it in every VM it creates, useful for `kubectl debug`-free troubleshooting):
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/tuist-syself -N ''
   # Upload the .pub contents via Hetzner Cloud console: Security → SSH Keys → Add.
   ```

## 3. Create the Hetzner Secret in the management cluster

Syself's `caph` provider reads this Secret when it provisions nodes. It lives in our org namespace on the management cluster (`org-tuist`). One Secret, shared across all workload clusters — see the Cluster CR file for context on why.

```bash
export KUBECONFIG=~/.kube/tuist-syself-mgmt.yaml
ORG_NS="$(kubectl config view --minify -o jsonpath='{.contexts[0].context.namespace}')"

kubectl -n "$ORG_NS" create secret generic hetzner \
  --from-literal=hcloud="$(op read 'op://Founders/hetzner-tuist-syself/credential')" \
  --from-literal=hcloud-ssh-key-name=tuist-syself

# Upload the SSH public key to Hetzner Cloud via API (the ClusterClass
# attaches it to every VM by name).
TOKEN=$(kubectl -n "$ORG_NS" get secret hetzner -o jsonpath='{.data.hcloud}' | base64 -d)
curl -sX POST https://api.hetzner.cloud/v1/ssh_keys \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg key "$(cat ~/.ssh/tuist-syself.pub)" '{name:"tuist-syself", public_key:$key}')"
```

Verify:

```bash
kubectl -n "$ORG_NS" get secret hetzner
```

## 4. Provision the workload cluster

The per-env Cluster CRs are checked in at [`infra/k8s/syself/workload-cluster-{staging,canary,production}.yaml`](syself/). Shape (staging shown; canary mirrors it; production swaps the worker type):

- Region: `fsn1` (Falkenstein)
- Control plane: 3 × `cpx22` cloud VMs (HA, tolerates 1 node failure, enables zero-downtime upgrades)
- Workers: 2 × `cpx22` (staging/canary) or 2 × `ccx23` (production, dedicated vCPU)
- Pod/service CIDRs and `topology.class` follow the Syself docs example for Kubernetes 1.34

Before applying:

1. Confirm `topology.class` matches a currently-available `ClusterStackRelease`:
   ```bash
   kubectl get clusterstackreleases
   ```
   Bump `class` + `version` together if a newer release is out.
2. Apply (staging shown; canary + production use their own CR files):
   ```bash
   kubectl apply -f infra/k8s/syself/workload-cluster-staging.yaml
   ```

Wait for it to come up — 10–20 minutes for the first boot:

```bash
kubectl -n "$ORG_NS" get cluster tuist-staging -w
# Ready=True once all nodes, control plane, and CNI are running.

kubectl -n "$ORG_NS" describe cluster tuist-staging
# Good for diagnosing stuck phases (InfrastructureReady, ControlPlaneReady, …).
```

Fetch the workload cluster kubeconfig directly from the CAPI-managed Secret (we avoid `clusterctl get kubeconfig` because the pinned v1.13 CLI is built for v1beta2 management clusters, while Syself's is v1beta1):

```bash
kubectl -n "$ORG_NS" get secret tuist-staging-kubeconfig -o jsonpath='{.data.value}' \
  | base64 -d > ~/.kube/tuist-staging.yaml
chmod 600 ~/.kube/tuist-staging.yaml

# Switch to the workload cluster.
export KUBECONFIG=~/.kube/tuist-staging.yaml
kubectl get nodes
# Expect 3 control-plane + 2 workers, all Ready.
```

## 5. Bootstrap the server secrets

`MASTER_KEY` (decrypts `priv/secrets/stag.yml.enc` baked into the image) is synced from 1Password via [external-secrets-operator](https://external-secrets.io). The chart's `externalSecrets` block in `values-managed-common.yaml` already references a `ClusterSecretStore` named `onepassword`. Install ESO + the store once per workload cluster:

```bash
# 1) ESO CRDs + controller
helm repo add external-secrets https://charts.external-secrets.io
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace \
  --set installCRDs=true

# 2) Stash the 1Password Service Account token in the cluster. The SA must
#    have read access to the tuist-k8s-staging vault which holds MASTER_KEY
#    (plus the Grafana Cloud tokens the k8s-monitoring chart consumes).
kubectl create namespace onepassword --dry-run=client -o yaml | kubectl apply -f -
kubectl -n onepassword create secret generic onepassword-sa-token \
  --from-literal=token="$(op read 'op://Founders/<1p-item-uuid>/credential')" \
  --dry-run=client -o yaml | kubectl apply -f -

# 3) Wire it up as a ClusterSecretStore.
cat <<'YAML' | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: onepassword
spec:
  provider:
    onepasswordSDK:
      vault: tuist-k8s-staging
      auth:
        serviceAccountSecretRef:
          name: onepassword-sa-token
          namespace: onepassword
          key: token
YAML

# 4) Confirm it went Ready.
kubectl get clustersecretstore onepassword
# NAME          READY
# onepassword   True
```

The Tuist chart's `ExternalSecret` resource will pick `MASTER_KEY` up automatically when Helm installs in the next section.

## 6. Create the CI ServiceAccount + kubeconfig

GitHub Actions deploys via a namespace-scoped ServiceAccount with a long-lived token (the Syself-documented headless pattern). The manifest is checked in at [`infra/k8s/syself/ci-service-account.yaml`](syself/ci-service-account.yaml).

```bash
export KUBECONFIG=~/.kube/tuist-staging.yaml
kubectl apply -f infra/k8s/syself/ci-service-account.yaml

# Build the kubeconfig CI will use. Embed the CA and token so the file is
# self-contained; no reliance on the caller's context.
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl -n tuist-staging get secret github-actions-deployer-token -o jsonpath='{.data.ca\.crt}')
TOKEN=$(kubectl -n tuist-staging get secret github-actions-deployer-token -o jsonpath='{.data.token}' | base64 -d)

cat > /tmp/ci-kubeconfig.yaml <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: tuist-staging
    cluster:
      server: $SERVER
      certificate-authority-data: $CA
contexts:
  - name: ci
    context:
      cluster: tuist-staging
      namespace: tuist-staging
      user: github-actions-deployer
users:
  - name: github-actions-deployer
    user:
      token: $TOKEN
current-context: ci
EOF

# Sanity-check.
KUBECONFIG=/tmp/ci-kubeconfig.yaml kubectl -n tuist-staging get pods

# Load into the GitHub Environment secret.
base64 < /tmp/ci-kubeconfig.yaml | gh secret set KUBECONFIG \
  --env server-k8s-staging --repo tuist/tuist

shred -u /tmp/ci-kubeconfig.yaml
```

The token is persistent — revoke by deleting the `github-actions-deployer-token` Secret, or rotate by recreating it.

## 7. First deploy

### Manual dry-run

```bash
export KUBECONFIG=~/.kube/tuist-staging.yaml

cd infra/helm/tuist
helm upgrade --install tuist . \
  -n tuist-staging --create-namespace \
  -f values-managed-common.yaml \
  -f values-managed-staging.yaml \
  --set server.image.tag="sha-$(git rev-parse --short=12 HEAD)" \
  --atomic --timeout 10m
```

Watch the rollout:

```bash
kubectl -n tuist-staging rollout status deploy/tuist-tuist-server
kubectl -n tuist-staging logs -l app.kubernetes.io/component=server -f
```

Once the ingress-nginx LB is up and DNS is pointing at it:

```bash
curl -v https://staging.tuist.dev/ready
```

### Then via CI

After the manual smoke test passes:

```bash
gh workflow run server-deployment.yml -f environment=staging
```

## 8. Observability

The in-cluster [`infra/helm/k8s-monitoring/`](../helm/k8s-monitoring/) chart forwards the full Kubernetes telemetry picture (cluster / pod / node metrics, events, pod logs, server traces) to Grafana Cloud. It's installed automatically by the `observability-install` job in [`.github/workflows/server-deployment.yml`](../../.github/workflows/server-deployment.yml) — no manual `helm install` needed, the first server deploy against a new cluster brings it up.

Prerequisite: the ClusterSecretStore from §5 must already exist before the first CI deploy — the chart pulls the three Grafana Cloud tokens (Prometheus, Loki, Tempo) through it.

If you do need to run it by hand (e.g. bringing up a fresh cluster before the first CI deploy, or debugging locally):

```bash
helm dependency update infra/helm/k8s-monitoring
helm upgrade --install k8s-monitoring infra/helm/k8s-monitoring \
  -n observability --create-namespace \
  -f infra/helm/k8s-monitoring/values-staging.yaml
```

After the chart is live, check **Observability → Kubernetes** in Grafana Cloud for the cluster named `tuist-staging` / `tuist-canary` / `tuist-production`. Full verification steps live in [`infra/helm/k8s-monitoring/README.md`](../helm/k8s-monitoring/README.md).

## 9. Preview environments (ephemeral PR / commit deploys)

Preview environments live on a dedicated workload cluster (`tuist-preview`) that runs everything embedded — Postgres, ClickHouse, MinIO — alongside the server. Each preview is its own Helm release in its own namespace, with auto-deletion driven by a TTL label and an hourly sweep workflow. The worker pool scales to 0 when no previews are live.

This section is the one-time bootstrap. Once it's done, deploys are purely a GitHub Actions affair — `Actions → Preview Deploy → Run workflow`.

### 9.1 Prerequisites

- The `tuist-k8s-preview` 1Password vault, with item `TUIST_LICENSE_KEY` (Login or Password category, value in the `password` field).
- A 1Password Service Account scoped to that vault. Stash its token in `Founders` as `1Password SA — tuist-k8s-preview`.
- A Cloudflare API token scoped to `Zone.DNS:Edit` on `tuist.dev` (you already have one for the other clusters — reuse).

### 9.2 Provision the cluster

```bash
export KUBECONFIG=~/.kube/tuist-syself-mgmt.yaml
ORG_NS="$(kubectl config view --minify -o jsonpath='{.contexts[0].context.namespace}')"

kubectl apply -f infra/k8s/syself/workload-cluster-preview.yaml
kubectl -n "$ORG_NS" get cluster tuist-preview -w
# Ready=True once control plane is up. Note: workers default to replicas: 0,
# so initially you'll see 1 control-plane and 0 workers — that's expected.
```

Fetch the workload kubeconfig the same way as staging:

```bash
kubectl -n "$ORG_NS" get secret tuist-preview-kubeconfig -o jsonpath='{.data.value}' \
  | base64 -d > ~/.kube/tuist-preview.yaml
chmod 600 ~/.kube/tuist-preview.yaml
```

### 9.3 ESO + 1Password store

```bash
export KUBECONFIG=~/.kube/tuist-preview.yaml

helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace \
  --set installCRDs=true

kubectl create namespace onepassword --dry-run=client -o yaml | kubectl apply -f -
kubectl -n onepassword create secret generic onepassword-sa-token \
  --from-literal=token="$(op read 'op://Founders/1Password SA — tuist-k8s-preview/password')" \
  --dry-run=client -o yaml | kubectl apply -f -

cat <<'YAML' | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: onepassword
spec:
  provider:
    onepasswordSDK:
      vault: tuist-k8s-preview
      auth:
        serviceAccountSecretRef:
          name: onepassword-sa-token
          namespace: onepassword
          key: token
YAML

kubectl get clustersecretstore onepassword
# Expect READY=True.
```

### 9.4 Wildcard DNS + cert

In Cloudflare's `tuist.dev` zone, create a single A record:

```
*.preview.tuist.dev   A   <preview cluster ingress IP>
```

The ingress IP is the LB Hetzner provisions when ingress-nginx is installed (next step). Bring up ingress-nginx first, grab the LB IP from `kubectl get svc -n ingress-nginx ingress-nginx-controller`, then create the record.

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  -f infra/k8s/syself/ingress-nginx-values.yaml \
  --set controller.extraArgs.default-ssl-certificate=ingress-nginx/preview-tuist-dev-wildcard-tls
kubectl -n ingress-nginx get svc ingress-nginx-controller -w
# Wait for EXTERNAL-IP, then create the *.preview.tuist.dev A record.
```

Issue the wildcard cert via cert-manager DNS-01 (re-uses the same Cloudflare token pattern as the other clusters):

```bash
helm repo add jetstack https://charts.jetstack.io
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace \
  --set installCRDs=true

# Cloudflare token Secret (same item the other clusters reuse).
kubectl -n cert-manager create secret generic cloudflare-api-token \
  --from-literal=api-token="$(op read 'op://Founders/cloudflare-tuist-dev-dns/credential')"

cat <<'YAML' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-cloudflare
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ops@tuist.dev
    privateKeySecretRef:
      name: letsencrypt-cloudflare-account
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              namespace: cert-manager
              key: api-token
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: preview-tuist-dev-wildcard
  namespace: ingress-nginx
spec:
  secretName: preview-tuist-dev-wildcard-tls
  issuerRef:
    name: letsencrypt-cloudflare
    kind: ClusterIssuer
  commonName: "*.preview.tuist.dev"
  dnsNames:
    - "*.preview.tuist.dev"
    - "preview.tuist.dev"
YAML

# Wait for issuance (DNS-01 is ~1–3 min).
kubectl -n ingress-nginx get certificate preview-tuist-dev-wildcard -w
```

The `--default-ssl-certificate=ingress-nginx/preview-tuist-dev-wildcard-tls` flag we passed to ingress-nginx makes this single Secret cover every preview Ingress automatically — no per-namespace TLS plumbing.

### 9.5 CI ServiceAccount (workload cluster)

```bash
export KUBECONFIG=~/.kube/tuist-preview.yaml
sed 's/__NAMESPACE__/preview-system/g' infra/k8s/syself/ci-service-account.yaml \
  | kubectl apply -f -

SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl -n preview-system get secret github-actions-deployer-token -o jsonpath='{.data.ca\.crt}')
TOKEN=$(kubectl -n preview-system get secret github-actions-deployer-token -o jsonpath='{.data.token}' | base64 -d)

cat > /tmp/preview-kubeconfig.yaml <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: tuist-preview
    cluster:
      server: $SERVER
      certificate-authority-data: $CA
contexts:
  - name: ci
    context: { cluster: tuist-preview, user: github-actions-deployer }
users:
  - name: github-actions-deployer
    user: { token: $TOKEN }
current-context: ci
EOF

base64 < /tmp/preview-kubeconfig.yaml | gh secret set KUBECONFIG \
  --env server-k8s-preview --repo tuist/tuist
shred -u /tmp/preview-kubeconfig.yaml
```

### 9.6 Scaler ServiceAccount (management cluster)

The deploy + sweep workflows scale the worker MachineDeployment up and down. The Cluster CR for that lives in the **management** cluster, so we mint a separate, narrowly-scoped SA there.

```bash
export KUBECONFIG=~/.kube/tuist-syself-mgmt.yaml
ORG_NS="$(kubectl config view --minify -o jsonpath='{.contexts[0].context.namespace}')"

sed "s/__ORG_NS__/$ORG_NS/g" infra/k8s/syself/preview-mgmt-rbac.yaml | kubectl apply -f -

SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl -n "$ORG_NS" get secret preview-scaler-token -o jsonpath='{.data.ca\.crt}')
TOKEN=$(kubectl -n "$ORG_NS" get secret preview-scaler-token -o jsonpath='{.data.token}' | base64 -d)

cat > /tmp/preview-mgmt-kubeconfig.yaml <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: syself-mgmt
    cluster:
      server: $SERVER
      certificate-authority-data: $CA
contexts:
  - name: ci
    context: { cluster: syself-mgmt, namespace: $ORG_NS, user: preview-scaler }
users:
  - name: preview-scaler
    user: { token: $TOKEN }
current-context: ci
EOF

base64 < /tmp/preview-mgmt-kubeconfig.yaml | gh secret set KUBECONFIG_MGMT \
  --env server-k8s-preview --repo tuist/tuist
shred -u /tmp/preview-mgmt-kubeconfig.yaml
```

### 9.7 First preview

```bash
gh workflow run preview-deploy.yml \
  -f pr_number=1234 \
  -f ttl_hours=24
```

Or for a one-off commit:

```bash
gh workflow run preview-deploy.yml \
  -f commit_sha=abc1234567890... \
  -f ttl_hours=4
```

The workflow scales the worker pool up if needed (~3–5 min cold start), labels/taints the new node, runs `helm upgrade --install`, and posts the URL back to the PR. The hourly `preview-sweep.yml` workflow handles deletion + scale-down.

## 10. Teardown

Workload cluster:

```bash
export KUBECONFIG=~/.kube/tuist-syself-mgmt.yaml
kubectl -n "$ORG_NS" delete cluster tuist-staging
```

Syself will drain + delete the nodes and release the Hetzner resources. The Hetzner Cloud project, LB, and DNS records are yours to clean up separately if you're done with the provider.

---

## Troubleshooting crib

**`kubectl get clusters` opens the browser but fails afterwards**
Check the `namespace:` in the kubeconfig context — Syself's template ships with a placeholder that must be overwritten with `org-tuist`.

**`Cluster` stuck in `InfrastructureReady: false`**
```bash
kubectl -n "$ORG_NS" describe cluster tuist-staging
kubectl -n "$ORG_NS" get hetznercluster,hcloudmachine,machine
```
Most often a bad `hetzner` Secret (API token typo, missing permission, or missing `hcloud-ssh-key-name`).

**`HCloudMachine` stuck with `ServerCreateFailedIrrecoverableError` / "unsupported location"**
Hetzner's per-DC capacity or server-type stock varies. Two common causes:
- Hetzner is out of stock for that type in that DC — pick a different server type (`kubectl patch cluster ... controlPlaneMachineTypeHcloud` or `workerMachineTypeHcloud`) and `kubectl delete machine` the stuck ones so CAPI reconciles.
- Customer-level limits hit (server count, dedicated vCPUs, primary IPs). Check `https://console.hetzner.cloud/your-account/limits` and request an increase via support.

**LoadBalancer stuck in `<pending>`**
Hetzner's cloud-controller-manager needs the `load-balancer.hetzner.cloud/location` annotation on the Service to pick a DC. Verify `kubectl describe svc <name>` includes it. CCM logs:
```bash
kubectl -n kube-system logs -l app=hcloud-cloud-controller-manager
```

**`** (ArgumentError) argument error` from the server pod**
`MASTER_KEY` is wrong or missing. ESO sync issue or 1Password item name mismatch. Check:
```bash
kubectl -n tuist-staging get externalsecret
kubectl -n tuist-staging describe externalsecret tuist-master-key
```

**Helm upgrade times out on the migration Job**
```bash
kubectl -n tuist-staging logs job/tuist-tuist-server-migrate-<revision>
```
Usually Supabase TLS — check `TUIST_USE_SSL_FOR_DATABASE=1` is set and the `ssl: verify_none` workaround is in `runtime.exs`.
