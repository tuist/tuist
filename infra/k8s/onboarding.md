# Workload Cluster Onboarding — Tuist Server on Kubernetes

Stand up a new Tuist workload cluster (staging / canary / production / preview) on Hetzner via our self-hosted CAPI management cluster, and deploy the Tuist server to it.

We run a **management cluster** (a single-node Talos VM in Hetzner project `tuist-mgmt`) that hosts CAPI v1.13 + caph v1.1. You apply [Cluster API](https://cluster-api.sigs.k8s.io/) CRs against it; caph spins up workload nodes in the workload Hetzner project. The mgmt cluster's manifests live in [`infra/k8s/mgmt/`](mgmt/); workload Cluster CRs (and the shared `tuist-hcloud` ClusterClass) live in [`infra/k8s/clusters/`](clusters/) and are auto-applied to the mgmt cluster on push to `main` by [`mgmt-cluster-apply.yml`](../../.github/workflows/mgmt-cluster-apply.yml).

This doc is the runbook for onboarding **a new workload cluster** end-to-end. The mgmt cluster itself is bootstrapped by the migration PR's runbook; re-bootstrapping it is documented inline in [`mgmt/tailscale.yaml`](mgmt/tailscale.yaml).

---

## Prerequisites

- Tailscale on the `tuist.dev` tailnet, with `talosctl` reachable on the mgmt VM at `100.92.208.109:50000` (see [`mgmt/tailscale.yaml`](mgmt/tailscale.yaml) for tailnet onboarding).
- Mgmt cluster kubeconfig in 1Password as `kubeconfig: tuist-mgmt` in the `tuist-k8s-mgmt` vault.
- Hetzner Cloud project `tuist-workloads` (separate from `tuist-mgmt`) with API access. Token in 1Password as `tuist-workloads`.
- A Cloudflare account with an API token scoped to `Zone.DNS:Edit` on `tuist.dev` (1Password: `cloudflare-tuist-dns`).
- Per-env 1Password vault (`tuist-k8s-staging` / `tuist-k8s-canary` / `tuist-k8s-production` / `tuist-k8s-preview`) holding the runtime secrets (`MASTER_KEY`, `TUIST_LICENSE_KEY` for preview, Grafana Cloud tokens) and a Service Account token scoped to the vault.
- CLI tools installed via mise:
  ```bash
  mise use -g kubectl helm clusterctl talosctl
  ```
- The 1Password CLI (`op`).

## 1. Access the management cluster

```bash
mkdir -p ~/.kube
op document get "kubeconfig: tuist-mgmt" --vault tuist-k8s-mgmt > ~/.kube/tuist-mgmt.yaml
chmod 600 ~/.kube/tuist-mgmt.yaml

export KUBECONFIG=~/.kube/tuist-mgmt.yaml
kubectl get clusters -n org-tuist
```

The `org-tuist` namespace is where every Cluster CR + the `hetzner` Secret live.

## 2. Author the Cluster CR

Each workload cluster is a `Cluster` CR in topology mode referencing the `tuist-hcloud` ClusterClass. Existing per-env files:

- [`clusters/cluster-staging.yaml`](clusters/cluster-staging.yaml)
- [`clusters/cluster-canary.yaml`](clusters/cluster-canary.yaml)
- [`clusters/cluster-production.yaml`](clusters/cluster-production.yaml)
- [`clusters/cluster-preview.yaml`](clusters/cluster-preview.yaml)

For a new cluster, copy the closest existing file and adjust `metadata.name`, replica counts, machine types, and any per-pool labels/taints. Variables exposed by the ClusterClass are documented in [`clusters/README.md`](clusters/README.md). Run `mise run k8s:lint-version-drift` to confirm `topology.version` matches the ClusterClass's `KUBERNETES_VERSION` before applying.

## 3. Apply the Cluster CR

The `mgmt-cluster-apply.yml` workflow auto-applies anything under `infra/k8s/clusters/**` on push to `main`. For an out-of-band apply (e.g. before a PR is merged):

```bash
kubectl apply -f infra/k8s/clusters/cluster-<env>.yaml
kubectl -n org-tuist get cluster <name> -w
# Ready=True once control plane is up. ~3–5 min cold start.
```

## 4. Bootstrap the workload cluster

Run the `k8s:bootstrap-workload` task. It is idempotent and handles every step the workload cluster needs before CI deploys can target it (Cilium, HCCM, hcloud-csi, the `hetzner` Secret on the workload, the platform chart, ESO + the per-env `onepassword` ClusterSecretStore, the monitoring chart, the app namespace + the Cloudflare origin TLS Secret, and a final ingress smoke test):

```bash
mise run k8s:bootstrap-workload <cluster_name> <env>
# e.g. mise run k8s:bootstrap-workload tuist-canary-2 canary
```

On success the script uploads the freshly-minted workload kubeconfig to the per-env 1Password vault as `kubeconfig: <cluster_name>` so CI can read it.

## 5. Wire the GitHub Actions deployer

CI uses a namespace-scoped ServiceAccount with a long-lived token, defined in [`mgmt/ci-service-account.yaml`](mgmt/ci-service-account.yaml). Apply it on the workload cluster, mint a kubeconfig, and load it into the GitHub Environment secret:

```bash
WL_KUBECONFIG=~/.kube/<cluster_name>.yaml
APP_NS=tuist-<env>   # production uses tuist (no suffix)

sed "s/__NAMESPACE__/${APP_NS}/g" infra/k8s/mgmt/ci-service-account.yaml \
  | KUBECONFIG="$WL_KUBECONFIG" kubectl apply -f -

SERVER=$(KUBECONFIG="$WL_KUBECONFIG" kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(KUBECONFIG="$WL_KUBECONFIG" kubectl -n "$APP_NS" get secret github-actions-deployer-token -o jsonpath='{.data.ca\.crt}')
TOKEN=$(KUBECONFIG="$WL_KUBECONFIG" kubectl -n "$APP_NS" get secret github-actions-deployer-token -o jsonpath='{.data.token}' | base64 -d)

cat > /tmp/ci-kubeconfig.yaml <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: <cluster_name>
    cluster:
      server: $SERVER
      certificate-authority-data: $CA
contexts:
  - name: ci
    context:
      cluster: <cluster_name>
      namespace: $APP_NS
      user: github-actions-deployer
users:
  - name: github-actions-deployer
    user:
      token: $TOKEN
current-context: ci
EOF

KUBECONFIG=/tmp/ci-kubeconfig.yaml kubectl -n "$APP_NS" get pods   # sanity-check
base64 < /tmp/ci-kubeconfig.yaml | gh secret set KUBECONFIG \
  --env server-k8s-<env> --repo tuist/tuist
shred -u /tmp/ci-kubeconfig.yaml
```

## 6. First deploy

### Manual smoke test

```bash
export KUBECONFIG=~/.kube/<cluster_name>.yaml
helm upgrade --install tuist infra/helm/tuist \
  -n tuist-<env> --create-namespace \
  -f infra/helm/tuist/values-managed-common.yaml \
  -f infra/helm/tuist/values-managed-<env>.yaml \
  --set server.image.tag="sha-$(git rev-parse --short=12 HEAD)" \
  --atomic --timeout 10m

kubectl -n tuist-<env> rollout status deploy/tuist-tuist-server
curl -v https://<env>.tuist.dev/ready
```

### Then via CI

```bash
gh workflow run server-deployment.yml -f environment=<env>
```

## 7. Observability

The [`infra/helm/k8s-monitoring/`](../helm/k8s-monitoring/) chart forwards Kubernetes telemetry to Grafana Cloud. The bootstrap task in §4 installs it; the `observability-install` job in `server-deployment.yml` keeps it in sync on every deploy. After it lights up, look for the cluster name in **Observability → Kubernetes** in Grafana Cloud. Verification steps live in [`infra/helm/k8s-monitoring/README.md`](../helm/k8s-monitoring/README.md).

## 8. Preview environments (ephemeral PR / commit deploys)

Preview environments live on the `tuist-preview` workload cluster, which runs Postgres / ClickHouse / MinIO embedded alongside the server. Each preview is its own Helm release in its own namespace, with auto-deletion driven by a TTL label and an hourly sweep workflow.

### 8.1 Wildcard DNS + cert

In Cloudflare's `tuist.dev` zone, create a single A record pointing `*.preview.tuist.dev` at the preview cluster's ingress LB IP (the bootstrap task prints it at the end of step 12). The platform chart issues the wildcard cert via cert-manager DNS-01 against Cloudflare; ingress-nginx picks it up via the `--default-ssl-certificate` flag set in the chart values.

### 8.2 Preview-specific 1Password items

In the `tuist-k8s-preview` vault: `TUIST_LICENSE_KEY` (Login or Password category, `password` field). The `Service Account Auth Token: tuist-preview-k8s` 1P item authorizes ESO to read it.

### 8.3 Scaler ServiceAccount (management cluster)

The preview-deploy / preview-sweep workflows scale the preview MachineDeployment from CI via [`mgmt/preview-mgmt-rbac.yaml`](mgmt/preview-mgmt-rbac.yaml). Apply it against the mgmt cluster:

```bash
sed 's/__ORG_NS__/org-tuist/g' infra/k8s/mgmt/preview-mgmt-rbac.yaml \
  | KUBECONFIG=~/.kube/tuist-mgmt.yaml kubectl apply -f -
```

Mint a kubeconfig from the `preview-scaler-token` Secret (same recipe as §5, swapping the SA name + namespace), base64 it into the `KUBECONFIG_MGMT` GitHub Environment secret on the `server-k8s-preview` environment, then drop the `replicas: 1` pin on `cluster-preview.yaml` if you want elastic scale-to-zero.

### 8.4 First preview

```bash
gh workflow run preview-deploy.yml -f pr_number=1234 -f ttl_hours=24
# or, for a one-off commit:
gh workflow run preview-deploy.yml -f commit_sha=abc1234567890... -f ttl_hours=4
```

The hourly `preview-sweep.yml` workflow handles deletion + scale-down.

## 9. Teardown

```bash
KUBECONFIG=~/.kube/tuist-mgmt.yaml kubectl -n org-tuist delete cluster <cluster_name>
```

caph drains + deletes the nodes and releases the Hetzner LB and servers.

---

## Troubleshooting crib

**`Cluster` stuck in `InfrastructureReady: false`**
```bash
kubectl -n org-tuist describe cluster <name>
kubectl -n org-tuist get hetznercluster,hcloudmachine,machine
```
Most often a bad `hetzner` Secret in `org-tuist` (token typo, missing permission). The Secret must hold `hcloud=<token>` and `hcloud-ssh-key-name=<key>` (the SSH key uploaded to the workload Hetzner project).

**`HCloudMachine` stuck with `ServerCreateFailedIrrecoverableError` / "unsupported location"**
Hetzner per-DC capacity or server-type stock. Pick a different machine type (patch the Cluster CR's relevant variable) and `kubectl delete machine` the stuck ones so caph reconciles. For account-level limits, check `https://console.hetzner.cloud/your-account/limits`.

**LoadBalancer stuck in `<pending>`**
HCCM needs the `load-balancer.hetzner.cloud/location` annotation on the Service to pick a DC. The platform chart sets it; verify with `kubectl describe svc`. CCM logs:
```bash
kubectl -n kube-system logs -l app.kubernetes.io/name=hcloud-cloud-controller-manager
```

**`** (ArgumentError) argument error` from the server pod**
`MASTER_KEY` is wrong or missing. ESO sync issue or 1Password item name mismatch. Check:
```bash
kubectl -n tuist-<env> get externalsecret
kubectl -n tuist-<env> describe externalsecret tuist-master-key
```

**Helm upgrade times out on the migration Job**
```bash
kubectl -n tuist-<env> logs job/tuist-tuist-server-migrate-<revision>
```
Usually database connectivity — confirm `DATABASE_URL` decrypts cleanly and the Postgres host is reachable.
