# Workload Cluster Onboarding — Tuist Server on Kubernetes

Stand up a new Tuist workload cluster (staging / canary / production / preview) on Hetzner via our self-hosted CAPI management cluster, and deploy the Tuist server to it. Production Kura regions are node pools inside the production workload cluster, not separate clusters.

We run a **management cluster** (a single-node Talos VM in Hetzner project `tuist-mgmt`) that hosts CAPI v1.13 + caph v1.1. You apply [Cluster API](https://cluster-api.sigs.k8s.io/) CRs against it; caph spins up workload nodes in the workload Hetzner project. The mgmt cluster's manifests live in [`infra/k8s/mgmt/`](mgmt/); workload Cluster CRs (and the shared `tuist-hcloud` ClusterClass) live in [`infra/k8s/clusters/`](clusters/) and are auto-applied to the mgmt cluster on push to `main` by [`mgmt-cluster-apply.yml`](../../.github/workflows/mgmt-cluster-apply.yml).

This doc is the runbook for onboarding **a new workload cluster** end-to-end. The mgmt cluster itself is bootstrapped by the migration PR's runbook; re-bootstrapping it is documented inline in [`mgmt/tailscale.yaml`](mgmt/tailscale.yaml).

If you just want to **read** an existing cluster (the day-to-day case — `kubectl get pods`, `logs`, `describe`), you don't need any of the cluster-provisioning steps below. Jump to [Engineer read access](#engineer-read-access-pomerium-kubeconfig).

---

## Engineer read access (Pomerium kubeconfig)

Every engineer's Google Workspace identity already carries `view`-tier read access to all three workload clusters through the Pomerium gateway — no grant, no per-person provisioning. There's nothing secret to download: you assemble a small kubeconfig locally that registers `pomerium-cli` as an [exec credential plugin](https://kubernetes.io/docs/reference/access-authn-authz/authentication/#client-go-credential-plugins). On the first call the plugin opens a browser for Google OIDC and caches the session for ~24h. The full identity flow is documented in [`infra/helm/pomerium/NOTES.md`](../helm/pomerium/NOTES.md); the agent-facing rules (read is always allowed, writes go through the JIT Slack flow) are in [`infra/AGENTS.md`](../AGENTS.md#cluster-access-for-agents).

`view` deliberately excludes `Secret`s, so `MASTER_KEY`, `DATABASE_URL`, and ESO-synced secrets stay out of reach on this path. Mutating operations (`apply`, `delete`, `scale`, `patch`, `create`) return `403` until you elevate via `/elevate <env>` in Slack.

### Setup

1. `pomerium-cli` is pinned in the root [`mise.toml`](../../mise.toml) — `mise install` from the repo root puts it on your `PATH`.
2. Merge the three contexts below into your `~/.kube/config`. They contain no secrets — the hostnames are public and all auth happens at call time. Each env needs its own gateway host in the exec `args`, so there's one user per env. Production's host is `kube-prod`, not `kube-production`.

   ```yaml
   clusters:
     - name: tuist-k8s-staging
       cluster: { server: https://kube-staging.tuist.dev }
     - name: tuist-k8s-canary
       cluster: { server: https://kube-canary.tuist.dev }
     - name: tuist-k8s-production
       cluster: { server: https://kube-prod.tuist.dev }
   contexts:
     - name: tuist-k8s-staging
       context: { cluster: tuist-k8s-staging, user: pomerium-staging }
     - name: tuist-k8s-canary
       context: { cluster: tuist-k8s-canary, user: pomerium-canary }
     - name: tuist-k8s-production
       context: { cluster: tuist-k8s-production, user: pomerium-production }
   users:
     - name: pomerium-staging
       user:
         exec:
           apiVersion: client.authentication.k8s.io/v1beta1
           command: pomerium-cli
           args: ["k8s", "exec-credential", "https://kube-staging.tuist.dev"]
     - name: pomerium-canary
       user:
         exec:
           apiVersion: client.authentication.k8s.io/v1beta1
           command: pomerium-cli
           args: ["k8s", "exec-credential", "https://kube-canary.tuist.dev"]
     - name: pomerium-production
       user:
         exec:
           apiVersion: client.authentication.k8s.io/v1beta1
           command: pomerium-cli
           args: ["k8s", "exec-credential", "https://kube-prod.tuist.dev"]
   ```

3. Verify (a browser opens once per env for the Google login):

   ```bash
   kubectl --context tuist-k8s-staging get pods -A
   ```

> **This is not the admin kubeconfig.** The cluster-admin kubeconfigs in the `tuist-k8s-<env>` 1Password vaults bypass Pomerium and impersonation entirely; they're break-glass only and gated behind 1Password biometric on purpose. Don't reach for them for routine reads, and never have an agent fetch one. See [Workload-cluster incident recovery](#workload-cluster-incident-recovery).

---

## Prerequisites

- Tailscale on the `tuist.dev` tailnet, with `talosctl` reachable on the mgmt VM at `100.92.208.109:50000` (see [`mgmt/tailscale.yaml`](mgmt/tailscale.yaml) for tailnet onboarding).
- Mgmt cluster kubeconfig in 1Password as `kubeconfig: tuist-mgmt` in the `tuist-k8s-mgmt` vault.
- Hetzner Cloud project `tuist-workloads` (separate from `tuist-mgmt`) with API access. Token in 1Password as `tuist-workloads`.
- A Cloudflare account with an API token stored as `cloudflare-tuist-dns`. Local bootstrap reads it from the `Founders` vault.
- The `cloudflare-tuist-dns` token must be able to edit DNS for `tuist.dev`, read `tuist.dev` zone metadata, manage zone Load Balancers, and manage account-level Load Balancing pools/monitors.
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

Run the `k8s:bootstrap-workload` task. It is idempotent and handles every step the workload cluster needs before CI deploys can target it: Cilium, HCCM, hcloud-csi, the `hetzner` Secret on the workload, the platform chart, ESO + the per-env `onepassword` ClusterSecretStore, the monitoring chart, the app namespace + the Cloudflare origin TLS Secret, and a final ingress smoke test.

```bash
mise run k8s:bootstrap-workload <cluster_name> <env> [kubeconfig_item]
# e.g. mise run k8s:bootstrap-workload tuist-canary-2 canary
```

On success the script uploads the freshly-minted workload kubeconfig to the per-env 1Password vault. Clusters use the default `kubeconfig: tuist-<env>` title unless you explicitly pass a different document title.

## 5. Wire the GitHub Actions deployer

CI uses a namespace-scoped ServiceAccount with a long-lived token, defined in [`mgmt/ci-service-account.yaml`](mgmt/ci-service-account.yaml). Apply it on the workload cluster, mint a kubeconfig, and load it into the GitHub Environment secret:

```bash
WL_KUBECONFIG=~/.kube/<cluster_name>.yaml
APP_NS=tuist-<env>   # production uses tuist (no suffix); preview uses preview-system

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

# If the workload cluster's control-plane endpoint changes later (for
# example after a load-balancer recreation), re-run the minting flow
# above and refresh the GitHub Environment secret. The kubeconfig
# embeds `clusters[].cluster.server`, so it does not follow endpoint
# changes automatically.
```

## 5b. CAPI workload kubeconfig (Mac-mini fleets only)

Skip this for clusters without a Mac-mini fleet (`macosFleet.enabled: false` and `runnersFleet.enabled: false`).

The chart runs an in-cluster CAPI that manages the Mac minis as `Machine`/`MachineDeployment` objects in this same cluster. CAPI core's cluster cache reaches the cluster through a `<release>-capi-kubeconfig` Secret; the chart's [`capi-cluster.yaml`](../helm/tuist/templates/capi-cluster.yaml) sets a stub `controlPlaneEndpoint` (`127.0.0.1`), so that Secret has to be supplied. Without it CAPI can't bind Machines to Nodes, every fleet `MachineDeployment` stays unavailable, and the server deploy's `helm --wait` times out on them.

The chart creates the identity (`capi-remote` SA + scoped `ClusterRole` + non-expiring token Secret) and an `ExternalSecret` that syncs the kubeconfig from 1Password (`capi.remoteKubeconfig.externalSecrets`, on for managed envs). You populate the 1Password item once.

The kubeconfig's `server` **must be the in-cluster API endpoint** (the kubernetes Service ClusterIP). CAPI core's cluster cache ([`controllers/clustercache`](https://github.com/kubernetes-sigs/cluster-api/blob/v1.10.4/controllers/clustercache/cluster_accessor_client.go)) builds its REST config from this Secret and runs an initial reachability probe with the Secret's `server` *before* it overrides `Host`/`CAData` with the controller's own in-cluster config. So the `server` has to be reachable + TLS-valid from inside the cluster — the external control-plane LB IP is unroutable from a Pod (instant "no route"), and `kubernetes.default.svc` risks a cert-SAN mismatch. The ClusterIP is exactly what the controller's own client uses, so the probe is guaranteed to pass.

```bash
export KUBECONFIG=~/.kube/<cluster_name>.yaml
NS=tuist-<env>   # production uses tuist
APISERVER="https://$(kubectl -n default get svc kubernetes -o jsonpath='{.spec.clusterIP}'):443"
TOKEN=$(kubectl -n "$NS" get secret tuist-tuist-capi-remote-token -o jsonpath='{.data.token}' | base64 -d)
CA=$(kubectl -n "$NS" get secret tuist-tuist-capi-remote-token -o jsonpath='{.data.ca\.crt}')   # already base64
KCFG=$(printf 'apiVersion: v1\nkind: Config\nclusters:\n- name: tuist-tuist-capi\n  cluster: { server: %s, certificate-authority-data: %s }\ncontexts:\n- name: tuist-tuist-capi\n  context: { cluster: tuist-tuist-capi, user: tuist-tuist-capi }\ncurrent-context: tuist-tuist-capi\nusers:\n- name: tuist-tuist-capi\n  user: { token: %s }\n' "$APISERVER" "$CA" "$TOKEN")
op item create --vault tuist-k8s-<env> --category "Secure Note" --title capi-workload-kubeconfig "kubeconfig[password]=$KCFG"
unset TOKEN KCFG
```

ESO then materializes `<release>-capi-kubeconfig` and CAPI binds the fleet. The `capi-remote-token` Secret is non-expiring, so this is a one-time step per cluster.

> **Node `providerID`:** CAPI binds a Node to its Machine by matching `Node.spec.providerID` to `Machine.spec.providerID` (`scw-applesilicon://<zone>/<id>`). tart-kubelet does not yet set this, so a freshly-bootstrapped fleet node needs a one-time patch until that ships:
> `kubectl patch node <node> --type merge -p '{"spec":{"providerID":"<machine providerID>"}}'`

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

---

## Workload-cluster incident recovery

When the workload cluster (not the mgmt one) is misbehaving, work against its kubeconfig:

```bash
op document get "kubeconfig: tuist-<env>" --vault tuist-<env> > ~/.kube/tuist-<env>.yaml
chmod 600 ~/.kube/tuist-<env>.yaml
export KUBECONFIG=~/.kube/tuist-<env>.yaml
```

If 1Password is unhandy, CAPI also keeps a copy on the mgmt cluster:
```bash
KUBECONFIG=~/.kube/tuist-mgmt.yaml kubectl -n org-tuist \
  get secret tuist-<env>-kubeconfig -o jsonpath='{.data.value}' | base64 -d > ~/.kube/tuist-<env>.yaml
```

**Pods stuck `1/1 Running` but Deployment shows `0/N Available`**
The Node went `NotReady` and kubelet hasn't confirmed pod state since. Kubernetes' default 300s `unreachable` toleration gets reset on every brief reconnect, so pods stay pinned for hours. Force them off:
```bash
# Strip finalizers off any Terminating pod in the namespace
kubectl -n <ns> get pods -o jsonpath='{range .items[?(@.metadata.deletionTimestamp)]}{.metadata.name}{"\n"}{end}' \
  | xargs -I{} kubectl -n <ns> patch pod {} -p '{"metadata":{"finalizers":[]}}' --type=merge
# Force-delete any pod scheduled to an unreachable Node
unreachable=$(kubectl get nodes -o json | jq -r '.items[] | select(.spec.taints // [] | map(.key) | index("node.kubernetes.io/unreachable")) | .metadata.name')
for n in $unreachable; do
  kubectl -n <ns> get pods --field-selector spec.nodeName=$n -o name | xargs -r kubectl -n <ns> delete --grace-period=0 --force
done
kubectl -n <ns> rollout restart deployment --all
```

**Cloudflare returns 525 (origin TLS handshake fails)**
Almost always the ingress LB targeting dead Node IPs. HCCM owns the target list; if it's wedged, kick it:
```bash
kubectl -n kube-system rollout restart deployment/hcloud-cloud-controller-manager
# Trigger a fresh reconcile of the ingress Service:
kubectl -n platform annotate svc platform-ingress-nginx-controller "tuist.dev/lb-refresh=$(date -u +%s)" --overwrite
kubectl -n kube-system logs -l app.kubernetes.io/name=hcloud-cloud-controller-manager --tail=80
```

If HCCM logs `unable to parse server id: hcloud://nocloud` or `no matching server found for node`, a stale Node object is starving its reconcile queue:
```bash
# Bare-metal Nodes with the bad providerID (fixed at the source, but
# old ones lying around still block HCCM):
kubectl get nodes -o json | jq -r '.items[] | select(.spec.providerID=="hcloud://nocloud") | .metadata.name' \
  | xargs -r kubectl delete node
# Cloud-worker ghosts (Node exists, hcloud VM is gone):
kubectl get nodes -o json | jq -r '.items[] | select(.spec.providerID | startswith("hcloud://")) | select(.status.conditions[] | select(.type=="Ready" and .status!="True")) | .metadata.name' \
  | xargs -r -n1 -I{} sh -c 'kubectl get node {} -o json | jq -e ".spec.providerID | sub(\"hcloud://\";\"\") | tonumber" >/dev/null 2>&1 || echo {}'  # validate ID is numeric
# Then `kubectl delete node` the ones whose VM is confirmed gone in
# the Hetzner Cloud console.
```

Deleting a Node object is safe — CAPI re-creates it on the next reconcile if the underlying VM is still alive.

## Rolling a bare-metal host

When a chart bump changes `postInstallScript` (or any
`KubeadmConfigTemplate` / `HetznerBareMetalMachineTemplate` field) and
you need it to take effect before natural Node churn, force a
re-install. Work against the **mgmt** kubeconfig:

```bash
export KUBECONFIG=~/.kube/tuist-mgmt.yaml
CLUSTER=staging  # or canary / production

# Find the HBM bound to the cluster's HBMM, and snapshot its
# creationTimestamp — that's how we'll know the controller has
# re-created it (the HBMM name stays the same on re-bind).
HBMM=$(kubectl get hetznerbaremetalmachine -n org-tuist \
  -l cluster.x-k8s.io/cluster-name=tuist-$CLUSTER \
  -o jsonpath='{.items[0].metadata.name}')
HBM=$(kubectl get hetznerbaremetalhost -n org-tuist \
  -o jsonpath="{.items[?(@.spec.consumerRef.name=='$HBMM')].metadata.name}")
OLD_TS=$(kubectl get hetznerbaremetalhost -n org-tuist $HBM \
  -o jsonpath='{.metadata.creationTimestamp}')

# Delete the HBM (NOT the HBMM): caph fast-rebinds a fresh HBMM to
# an already-provisioned HBM without re-running installimage, so
# only deleting the HBM forces caph to discard the OS state.
kubectl delete hetznerbaremetalhost -n org-tuist $HBM --wait=false --timeout=2m
# Strip caph's finalizer if the HBMM still references the HBM after
# 2 min — otherwise the HBM lingers and `hetzner-robot-controller`
# can't re-create it cleanly.
kubectl patch hetznerbaremetalhost -n org-tuist $HBM \
  -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true

# Wait ~8–15 min for the full cycle:
#   (empty) → preparing → registering → image-installing →
#   ensure-provisioned → provisioned → kubeadm-joined
# Watch for a fresh creationTimestamp AND HBMM Ready=true:
while sleep 30; do
  NEW=$(kubectl get hetznerbaremetalhost -n org-tuist -o jsonpath='{.items[0].metadata.creationTimestamp}')
  READY=$(kubectl get hetznerbaremetalmachine -n org-tuist \
    -l cluster.x-k8s.io/cluster-name=tuist-$CLUSTER \
    -o jsonpath='{.items[0].status.ready}')
  echo "$(date +%H:%M:%S) ts=$NEW ready=$READY"
  [ "$NEW" != "$OLD_TS" ] && [ "$READY" = "true" ] && break
done
```

Bare-metal Nodes carry `tuist.dev/runner-tier=bare-metal:NoSchedule`,
so the only workload on them is idempotent runner Pods — no need to
cordon/drain. The autoscaler reconverges replica count automatically
after the new Node joins. Run a smoke afterward
(`linux-runners-staging-smoke.yml`) to confirm the new bootstrap is healthy.
