# Syself Onboarding Guide — Tuist Server on Kubernetes

Stand up a Syself-managed Kubernetes cluster on Hetzner and deploy the Tuist server to it.

Syself Apalla runs a **management cluster** as SaaS. You apply [Cluster API](https://cluster-api.sigs.k8s.io/) CRs against that management cluster, and the `caph` provider spins up nodes in your Hetzner project. You never operate the management cluster — you just talk to it.

Target here is **staging**. Production follows the same shape with HA tuning bumped.

---

## Prerequisites

- Access to the Syself Apalla management cluster (you should have a kubeconfig template from Syself onboarding).
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

Syself hands you a kubeconfig template. It uses `kubectl oidc-login` as the auth plugin — the first `kubectl` invocation opens a browser, you SSO in, and a short-lived token is cached in `~/.kube/cache/oidc-login/`.

```bash
# Save the kubeconfig Syself provided. The `namespace:` field in the
# context must be your org's namespace (they will have told you what).
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

Syself provisions into **your** Hetzner account. Two sides to the setup: Hetzner Cloud (for the control-plane VMs) and Hetzner Robot (for the dedicated bare-metal worker).

### 2a. Hetzner Cloud (control plane + LBs)

1. **Create a dedicated Hetzner Cloud project** at <https://console.hetzner.cloud/projects> (e.g. `tuist-staging`). Keeping staging / production in separate projects isolates blast radius and simplifies billing.
2. **Generate an API token** in that project with **read + write** permissions. Save it to 1Password immediately — Hetzner only shows it once.
   ```bash
   op item create --vault Tuist --category='API Credential' \
     --title='hetzner-tuist-staging' \
     hcloud_token='<paste token>'
   ```
3. **Upload an SSH key pair** to the project (Syself uses it to bootstrap the bare-metal worker from rescue mode):
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/tuist-syself -N ''
   # Upload the .pub contents via Hetzner Cloud console: Security → SSH Keys → Add.
   op document create ~/.ssh/tuist-syself --vault Tuist --title='ssh-tuist-syself'
   ```

### 2b. Hetzner Robot (bare-metal worker)

1. **Rent a dedicated server** at <https://robot.hetzner.com> in **Falkenstein** (to match `region: fsn1`). Recommended for staging:
   - **AX41-NVMe** or **AX42** — 6-core Ryzen, 64 GB RAM, 2× 512 GB NVMe (~€50/mo)
   - **EX44** — 6-core i5-13500, 64 GB RAM, 2× 512 GB NVMe (~€49/mo) as a fallback
2. **Create a Webservice/app user** so Syself's `caph` provider can drive the Robot API: Settings (👤) → *Webservice and app settings* → create a user + password. Save both to 1Password:
   ```bash
   op item create --vault Tuist --category='API Credential' \
     --title='hetzner-robot-tuist-staging' \
     robot_user='<paste user>' \
     robot_password='<paste password>'
   ```
3. **Upload the same SSH key** from §2a into Robot (Settings → Key management) so the same private key unlocks rescue mode on dedicated boxes.
4. Note the **server ID** of the rented machine — visible as `#<id>` in the Robot server list. You'll plug it into the HetznerBareMetalHost CR below.

## 3. Create the Hetzner Secrets in the management cluster

These live **in the management cluster's namespace for your org**. Syself's `caph` provider reads them when it provisions nodes.

```bash
export KUBECONFIG=~/.kube/tuist-syself-mgmt.yaml
ORG_NS="$(kubectl config view --minify -o jsonpath='{.contexts[0].context.namespace}')"

# Hetzner Cloud API token — caph uses it to create/destroy VMs and LBs.
kubectl -n "$ORG_NS" create secret generic hetzner-staging \
  --from-literal=hcloud="$(op read 'op://Tuist/hetzner-tuist-staging/hcloud_token')"

# Robot credentials + SSH key — caph uses these to reinstall bare-metal
# servers from rescue mode.
kubectl -n "$ORG_NS" create secret generic hetzner-ssh-staging \
  --from-literal=sshkey-name=tuist-syself \
  --from-file=ssh-privatekey=$HOME/.ssh/tuist-syself \
  --from-file=ssh-publickey=$HOME/.ssh/tuist-syself.pub \
  --from-literal=robot-user="$(op read 'op://Tuist/hetzner-robot-tuist-staging/robot_user')" \
  --from-literal=robot-password="$(op read 'op://Tuist/hetzner-robot-tuist-staging/robot_password')"
```

Verify:

```bash
kubectl -n "$ORG_NS" get secrets
```

## 4. Register the bare-metal worker

Before applying the Cluster CR, tell Apalla which Robot server to take over. Template is in [`infra/k8s/syself/baremetal-host-worker.yaml.example`](syself/baremetal-host-worker.yaml.example) — copy it, fill in the `serverID` and namespace, apply.

```bash
cp infra/k8s/syself/baremetal-host-worker.yaml.example /tmp/worker-1.yaml
# Edit /tmp/worker-1.yaml:
#   metadata.namespace: <your org namespace>
#   spec.serverID:      <Robot server ID>
kubectl apply -f /tmp/worker-1.yaml
```

First provisioning boots the server into rescue mode, detects the disks, and populates status. Watch it:

```bash
kubectl -n "$ORG_NS" describe hetznerbaremetalhost tuist-staging-worker-1
# Look at status.hardwareDetails.storage[] for the NVMe WWN, then edit the
# CR to pin spec.rootDeviceHints.wwn so reinstalls always land on the same
# disk. (You can also leave it empty and let Apalla pick — fine for a
# single-disk box.)
```

## 5. Provision the workload cluster

The Cluster CR template is checked in at [`infra/k8s/syself/workload-cluster-staging.yaml`](syself/workload-cluster-staging.yaml). Shape:

- Region: `fsn1` (Falkenstein)
- Control plane: 3 × `cpx11` cloud VMs (HA, tolerates 1 node failure, enables zero-downtime upgrades)
- Worker: 1 × Hetzner Robot bare-metal server registered in §4 (matched via `workerHostSelectorBareMetal: {role: worker, cluster: tuist-staging}`)
- Pod/service CIDRs and `topology.class` match the Syself docs example for Kubernetes 1.34

Before applying:

1. Replace `REPLACE_ME_ORG_NAMESPACE` with your org's namespace.
2. Confirm `topology.class` matches a currently-available `ClusterStackRelease`:
   ```bash
   kubectl get clusterstackreleases
   ```
   Bump `class` + `version` together if a newer release is out.
3. Apply:
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

Fetch the workload cluster kubeconfig:

```bash
clusterctl -n "$ORG_NS" get kubeconfig tuist-staging > ~/.kube/tuist-staging.yaml
chmod 600 ~/.kube/tuist-staging.yaml

# Switch to the workload cluster.
export KUBECONFIG=~/.kube/tuist-staging.yaml
kubectl get nodes
# Expect 3 control-plane + 1 worker, all Ready.
```

## 6. Install ingress-nginx (Hetzner LB integration)

Staging exposes the server via a Hetzner Cloud LoadBalancer. Helm values for the LB annotations are checked in at [`infra/k8s/syself/ingress-nginx-values.yaml`](syself/ingress-nginx-values.yaml).

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  -f infra/k8s/syself/ingress-nginx-values.yaml

# External IP surfaces in ~60s once Hetzner provisions the LB.
kubectl -n ingress-nginx get svc ingress-nginx-controller -w
```

Point `staging.tuist.dev` at that IP via Cloudflare (A record, proxied off while cert-manager is doing DNS-01, flip on afterwards).

## 7. Bootstrap the server secrets

`MASTER_KEY` (decrypts `priv/secrets/stag.yml.enc` baked into the image) is synced from 1Password via [external-secrets-operator](https://external-secrets.io). Same pattern as on GKE — see [gke-onboarding.md §3](gke-onboarding.md) for the 1Password / ESO flow. The chart's `externalSecrets` block in `values-managed-common.yaml` already references a `ClusterSecretStore` named `onepassword`; install ESO and the store once per workload cluster:

```bash
# ESO CRDs + controller
helm repo add external-secrets https://charts.external-secrets.io
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace \
  --set installCRDs=true

# ClusterSecretStore pointing at the 1Password SDK (token in a Secret).
# See the GKE onboarding doc §3b for the exact manifest — it's identical
# between providers, just applied into a different cluster.
```

## 8. Create the CI ServiceAccount + kubeconfig

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

## 9. First deploy

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

## 10. Observability

The in-cluster Alloy chart at [`infra/helm/alloy/`](../helm/alloy/) forwards metrics / traces / logs to Grafana Cloud. Install it once per workload cluster:

```bash
helm upgrade --install alloy infra/helm/alloy \
  -n observability --create-namespace
```

Prerequisite: the ClusterSecretStore from §7 must already exist — the chart pulls the three Grafana Cloud tokens (Prometheus, Loki, Tempo) through it.

## 11. Teardown

Workload cluster:

```bash
export KUBECONFIG=~/.kube/tuist-syself-mgmt.yaml
kubectl -n "$ORG_NS" delete cluster tuist-staging
```

Syself will drain + delete the nodes and release the Hetzner resources. The Hetzner Cloud project, LB, and DNS records are yours to clean up separately if you're done with the provider.

---

## Troubleshooting crib

**`kubectl get clusters` opens the browser but fails afterwards**
Check the `namespace:` in the kubeconfig context — Syself's template ships with a placeholder that must be overwritten with your org namespace.

**`Cluster` stuck in `InfrastructureReady: false`**
```bash
kubectl -n "$ORG_NS" describe cluster tuist-staging
kubectl -n "$ORG_NS" get hetznercluster,hcloudmachine,machine
```
Most often a bad `hetzner-staging` Secret (API token typo or missing permission).

**`Cluster` stuck in `WaitingForAvailableMachines` on the worker**
The bare-metal worker isn't ready yet. Check:
```bash
kubectl -n "$ORG_NS" describe hetznerbaremetalhost tuist-staging-worker-1
kubectl -n "$ORG_NS" get hetznerbaremetalmachines
```
Common causes: wrong `serverID`, the Robot user doesn't have API access to that server, or the `role=worker, cluster=tuist-staging` labels on the host don't match the Cluster's `workerHostSelectorBareMetal`.

**ingress-nginx LoadBalancer stuck in `<pending>`**
Hetzner's cloud-controller-manager needs the `load-balancer.hetzner.cloud/location` annotation to pick a DC. Verify `kubectl -n ingress-nginx describe svc ingress-nginx-controller` includes it. Also check the `hcloud-cloud-controller-manager` logs:
```bash
kubectl -n kube-system logs -l app=hcloud-cloud-controller-manager
```

**cert-manager certificate stuck at `Issuing`**
DNS-01 challenges need the Cloudflare token to have `Zone.DNS:Edit` on `tuist.dev`. Propagation usually completes in 60–90s.

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
