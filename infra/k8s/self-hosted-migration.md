# Self-Hosted Kubernetes Migration: From Syself Apalla to Tuist-Owned

Replace Syself's managed Cluster API control with our own management cluster running the same OSS stack: [Cluster API](https://cluster-api.sigs.k8s.io/), Syself's [`caph`](https://github.com/syself/cluster-api-provider-hetzner) Hetzner provider, and [`cluster-stack-operator`](https://github.com/SovereignCloudStack/cluster-stack-operator). Workload-cluster manifests do not change shape: only where the control plane that reconciles them lives.

This document is a one-time migration plan. The successor onboarding doc (replacing [`syself-onboarding.md`](syself-onboarding.md)) is a separate artifact written after the cutover proves out.

## Why

- **Cost.** Syself adds ~25% on top of Hetzner. Roughly €85/mo (~€1k/yr) at current scale. Engineer cost dominates, but the line item isn't zero and grows with usage.
- **Control over RBAC.** The current blocker on [#10571](https://github.com/tuist/tuist/pull/10571) (cluster-autoscaler) and the long-blocked preview scaler ([syself-onboarding.md §9.6](syself-onboarding.md)) is the same gate: Syself OIDC users can't `create serviceaccounts,roles,rolebindings` in `org-tuist` without a support ticket. Owning the management cluster removes the gate permanently.
- **Vendor surface.** `caph`, `cluster-stack-operator`, and the `syself/cluster-stacks` releases are open source and free to consume directly. We don't lose anything technical by self-hosting; we lose the human curation Syself provides on top.

## Decisions locked

1. **Management cluster hosting**: separate Hetzner Cloud project (`tuist-mgmt`), isolated blast radius from the prod workload project.
2. **Management cluster shape**: single CCX13 VM (€16/mo) running [k3s](https://k3s.io) with embedded etcd. Cattle, not pet: rebuilt from manifests + an etcd snapshot in ~30 min if it dies.
3. **CA topology**: per-workload-cluster, exactly the shape [#10571](https://github.com/tuist/tuist/pull/10571) wires (CA runs in the workload cluster, talks to the management cluster via a kubeconfig Secret).
4. **SSO replacement**: per-person kubeconfigs distributed via 1Password (we already use ESO + 1Password everywhere). No Tailscale dependency to introduce.

## Scope and non-scope

**In scope:** the four Cluster CRs in [`infra/k8s/syself/`](syself/): `tuist-staging`, `tuist-canary`, `tuist`, `tuist-preview`. The `ClusterStack` CR in [`infra/k8s/syself/cluster-stack.yaml`](syself/cluster-stack.yaml).

**Out of scope (today):** the cache, xcode-processor, and search clusters are not on Syself today — their workflows hold separate `KUBECONFIG_*` secrets pointing at different infrastructure. They're planned to consolidate onto Syself-shaped Cluster API in the future; when they do, they'll land directly on our self-hosted management cluster (no Syself path needed) and join `org-tuist` alongside the four migrated here.

---

## Prerequisites

- A Hetzner Cloud account with permission to create a new project.
- The current Syself management-cluster kubeconfig (per-person OIDC, used during `clusterctl move`).
- CLI tools installed via mise:
  ```bash
  mise use -g kubectl helm clusterctl
  ```
- The 1Password CLI (`op`).
- An existing Tigris bucket for etcd snapshots, or willingness to create one in this migration.

## Phase 1: Stand up the management cluster

### 1.1 Hetzner project + secrets

```bash
# In the Hetzner Cloud console:
#   1. Create project: tuist-mgmt
#   2. Generate API token (read+write)
#   3. Upload an SSH key

op item create --vault Founders --category='API Credential' \
  --title='hetzner-tuist-mgmt' \
  credential='<paste token>'

ssh-keygen -t ed25519 -f ~/.ssh/tuist-mgmt -N ''
# Upload .pub via Hetzner Cloud → Security → SSH Keys.
```

### 1.2 Provision the management VM

One CCX13 in `fsn1`, public IP, the SSH key just uploaded.

```bash
# Variables.
HCLOUD_TOKEN="$(op read 'op://Founders/hetzner-tuist-mgmt/credential')"

# Create the VM via API (or Cloud console). CCX13 = 2 dedicated vCPU, 8 GiB,
# enough headroom for k3s + CAPI controllers + a buffer for future tooling.
curl -sX POST https://api.hetzner.cloud/v1/servers \
  -H "Authorization: Bearer $HCLOUD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "tuist-mgmt",
    "server_type": "ccx13",
    "image": "ubuntu-24.04",
    "location": "fsn1",
    "ssh_keys": ["tuist-mgmt"],
    "public_net": {"enable_ipv4": true, "enable_ipv6": true}
  }' | jq '.server.public_net.ipv4.ip'
# Save the IP as MGMT_IP for the next steps.
```

### 1.3 Install k3s

Install k3s directly via SSH using the canonical installer. Disable Traefik (we don't need ingress on the mgmt cluster) and ServiceLB (no LoadBalancer services).

```bash
export MGMT_IP=<ip from previous step>

ssh -i ~/.ssh/tuist-mgmt -o StrictHostKeyChecking=accept-new root@$MGMT_IP \
  'curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik --disable=servicelb --write-kubeconfig-mode=0644" sh -'

# Pull the kubeconfig back, rewrite the embedded server URL from
# 127.0.0.1 to the public IP, and cache locally.
ssh -i ~/.ssh/tuist-mgmt root@$MGMT_IP 'cat /etc/rancher/k3s/k3s.yaml' \
  | sed "s/127.0.0.1/$MGMT_IP/" > ~/.kube/tuist-mgmt.yaml
chmod 600 ~/.kube/tuist-mgmt.yaml

export KUBECONFIG=~/.kube/tuist-mgmt.yaml
kubectl get nodes
# Expect 1 Ready control-plane.
```

### 1.4 Lock down the API server

`:22` is allowlisted to operator IPs. `:6443` is left public, gated by k3s's x509 client-cert auth.

The reason `:6443` isn't allowlisted: cluster-autoscaler runs in each workload cluster and talks to the mgmt API from its node's IP. CAPI replaces nodes on scale and health events, so per-node allowlisting isn't maintainable. Hetzner Cloud Networks would solve it (private API), but cross-project networks don't exist and we locked mgmt into a separate Hetzner project for blast-radius isolation. Cert auth is robust enough on its own; we accept the trade.

```bash
HCLOUD_TOKEN="$(op read 'op://Founders/hetzner-tuist-mgmt/credential')"
MGMT_SERVER_ID=<id from §1.2 server-create response>

# Operator IPs to allowlist for SSH. Add more as the team grows.
OPERATOR_IPS='["<your-ip>/32"]'

curl -sX POST https://api.hetzner.cloud/v1/firewalls \
  -H "Authorization: Bearer $HCLOUD_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --argjson ops "$OPERATOR_IPS" --argjson sid "$MGMT_SERVER_ID" '{
    name: "tuist-mgmt",
    rules: [
      {direction: "in", protocol: "tcp", port: "22",   source_ips: $ops},
      {direction: "in", protocol: "tcp", port: "6443", source_ips: ["0.0.0.0/0", "::/0"]}
    ],
    apply_to: [{type: "server", server: {id: $sid}}]
  }')"
```

Distribute the kubeconfig to each operator via 1Password:

```bash
op document create ~/.kube/tuist-mgmt.yaml \
  --vault Founders \
  --title 'kubeconfig: tuist-mgmt'
```

### 1.5 Initialize CAPI + caph + cluster-stack-operator

`clusterctl init` bootstraps the providers directly into k3s. Three pieces, three version pins.

**Versions to pin** (latest stable as of writing; refresh from upstream release pages at execution time if any have moved):

| Component | Version | Source |
|---|---|---|
| CAPI core | `v1.13.1` | <https://github.com/kubernetes-sigs/cluster-api/releases> |
| caph | `v1.1.0`  | <https://github.com/syself/cluster-api-provider-hetzner/releases> |
| cluster-stack-operator | `v0.1.0-alpha.9` | <https://github.com/SovereignCloudStack/cluster-stack-operator/releases> |

CSO has been on `alpha.9` since April 2025 with no further releases — it's the version Syself runs in production today, alpha-suffix notwithstanding. clusterctl 1.13 is v1beta2-native and reads Syself's v1beta1 CRs cleanly via conversion webhooks, so a version skew with Syself's controllers (which we can't introspect from `org-tuist`) is safe.

```bash
export KUBECONFIG=~/.kube/tuist-mgmt.yaml

export CAPI_VERSION=v1.13.1
export CAPH_VERSION=v1.1.0
export CSO_VERSION=v0.1.0-alpha.9

clusterctl init \
  --core "cluster-api:$CAPI_VERSION" \
  --bootstrap "kubeadm:$CAPI_VERSION" \
  --control-plane "kubeadm:$CAPI_VERSION" \
  --infrastructure "hetzner:$CAPH_VERSION"

# cluster-stack-operator ships as a Helm chart from the SCS OCI registry.
helm install cso oci://registry.scs.community/cluster-stack-operator/cso \
  --version "$CSO_VERSION" \
  -n cso-system --create-namespace

# Verify everything is Running.
kubectl get pods -A
```

### 1.6 Recreate the org namespace + Hetzner Secret

Keep the namespace name `org-tuist` so existing manifests reference unchanged.

```bash
kubectl create namespace org-tuist

# The hetzner Secret caph reads when reconciling Cluster CRs. The token must
# match the Hetzner project that owns the workload-cluster servers (NOT the
# mgmt project). Reuse the existing `hetzner-tuist-syself` token for now;
# rotate post-migration as a separate hardening step.
kubectl -n org-tuist create secret generic hetzner \
  --from-literal=hcloud="$(op read 'op://Founders/hetzner-tuist-syself/credential')" \
  --from-literal=hcloud-ssh-key-name=tuist-syself
```

### 1.7 Apply the ClusterStack

Same manifest, same namespace. caph + cluster-stack-operator pull the same `hetzner-apalla-1-34-v6` release from `syself/cluster-stacks`.

```bash
kubectl apply -f infra/k8s/syself/cluster-stack.yaml
kubectl -n org-tuist get clusterstackrelease -w
# Wait for hetzner-apalla-1-34-v6 to reach Ready=True.
```

### 1.8 etcd snapshots → Tigris

k3s has built-in etcd snapshots via S3. Hourly cadence, retention 168 (= 7 days). Bucket `tuist-mgmt-etcd-snapshots`, dedicated bucket-scoped access key in 1Password as `tigris-tuist-mgmt-etcd` with `access_key_id` + `secret_access_key` fields.

Create the bucket + scoped key in the Tigris dashboard first, save the keys to 1Password, then on the mgmt VM:

```bash
ssh -i ~/.ssh/tuist-mgmt root@$MGMT_IP

# Pull the keys from 1Password (run from your laptop, paste into the SSH session
# or use a temp script — don't bake the values into shell history).
TIGRIS_KEY="$(op read 'op://Founders/tigris-tuist-mgmt-etcd/access_key_id')"
TIGRIS_SECRET="$(op read 'op://Founders/tigris-tuist-mgmt-etcd/secret_access_key')"

mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/config.yaml <<EOF
etcd-snapshot-schedule-cron: '0 * * * *'
etcd-snapshot-retention: 168
etcd-s3: true
etcd-s3-endpoint: fly.storage.tigris.dev
etcd-s3-bucket: tuist-mgmt-etcd-snapshots
etcd-s3-access-key: $TIGRIS_KEY
etcd-s3-secret-key: $TIGRIS_SECRET
EOF
chmod 600 /etc/rancher/k3s/config.yaml

systemctl restart k3s
```

Verify the first snapshot:

```bash
kubectl get etcdsnapshotfile
# Expect at least one entry within the next hour.
```

The mgmt cluster's etcd holds CAPI CRs, Secrets, and ClusterStack state — everything `clusterctl move` would replay if we ever rebuild from a snapshot. The workload clusters' own etcds (per-cluster KubeadmControlPlane quorums) are *not* covered by this; that's intentional, since workload clusters hold no state we can't reconstruct from Helm + ESO + 1Password. If a stateful in-cluster service ever lands, revisit.

---

## Phase 2: Cutover preflight

> **Important constraint:** [`clusterctl move`](https://cluster-api.sigs.k8s.io/clusterctl/commands/move.html) is **namespace-scoped, not cluster-scoped**: it moves every CAPI object in `org-tuist` in a single operation, including all four Clusters and the shared `ClusterStack` / `HetznerClusterStackReleaseTemplate`. There's no `--filter-cluster`. The block-move annotation pauses the *whole* move, not individual clusters. So a per-cluster pilot via `clusterctl` isn't cleanly possible: it's all-or-nothing in one window.
>
> Hand-rolling a per-cluster move (manually exporting + applying CRs, stripping finalizers) is technically possible but has real risk: mishandling finalizers can trigger Hetzner-resource teardown on the source side. For a small team without deep CAPI operational experience, all-at-once with strong preflight is safer than per-cluster handcrafting.

The plan: cut over all four clusters in one maintenance window. Workload clusters keep serving traffic during and after the move (kubelet certificates are signed by each workload cluster's own CA, independent of the management plane).

### 2.1 Source preflight

```bash
export KUBECONFIG=~/.kube/tuist-syself-mgmt.yaml
ORG_NS=org-tuist

# All four Clusters healthy.
kubectl -n "$ORG_NS" get cluster
# Each: Ready=True, ControlPlaneReady=True, InfrastructureReady=True.

# Note the ClusterStack release version.
kubectl -n "$ORG_NS" get clusterstackrelease

# Inventory what `clusterctl move` will be touching. Save the output: it's
# the rollback reference.
clusterctl describe cluster --show-tree > /tmp/syself-pre-move-tree.txt
```

### 2.2 Target preflight

```bash
export KUBECONFIG=~/.kube/tuist-mgmt.yaml

# Same ClusterStack version Ready on the target.
kubectl -n org-tuist get clusterstackrelease
# Match Syself's version exactly. If not Ready, the move will succeed but
# reconciliation on the new side will hang.

# `hetzner` Secret exists in org-tuist (created in §1.6). Without it, caph
# on the new side can't reconcile any HCloudMachine.
kubectl -n org-tuist get secret hetzner

# Provider versions match.
kubectl -n caph-system get deploy caph-controller-manager -o jsonpath='{.spec.template.spec.containers[0].image}'
KUBECONFIG=~/.kube/tuist-syself-mgmt.yaml \
  kubectl -n caph-system get deploy caph-controller-manager -o jsonpath='{.spec.template.spec.containers[0].image}'
# Strings should match.
```

### 2.3 Dry-run

```bash
clusterctl move \
  --kubeconfig ~/.kube/tuist-syself-mgmt.yaml \
  --to-kubeconfig ~/.kube/tuist-mgmt.yaml \
  --namespace org-tuist \
  --dry-run

# Read the output carefully. It enumerates every object that will be moved.
# Expect: 4 Clusters, their KCPs, MachineDeployments, KubeadmConfigTemplates,
# HetznerClusters, HCloudMachineTemplates, HCloudMachines, Machines, Secrets,
# plus the shared ClusterStack + HetznerClusterStackReleaseTemplate.
```

If the dry-run reports anything unexpected (e.g. cross-namespace owner refs, missing target-side CRDs), resolve before proceeding.

---

## Phase 3: Cutover (all four clusters, one maintenance window)

Schedule a ~2h window during low traffic. The actual move takes 5–10 min; the rest is verification + soak start.

Comms: post in the team channel that the management plane is moving: workload clusters keep serving, but nothing CAPI-driven (scaling, node replacement, preview workflows) will succeed during the window. CI deploys to workload clusters are unaffected (they target the workload kubeconfig, not the mgmt cluster).

### 3.1 Snapshot etcd on both sides

```bash
# Source side: Syself manages this; nothing to do.

# Target side (our mgmt): force a snapshot before the move.
ssh -i ~/.ssh/tuist-mgmt root@$MGMT_IP \
  k3s etcd-snapshot save --name pre-cutover
```

### 3.2 Move

```bash
clusterctl move \
  --kubeconfig ~/.kube/tuist-syself-mgmt.yaml \
  --to-kubeconfig ~/.kube/tuist-mgmt.yaml \
  --namespace org-tuist
```

The command sets `Cluster.Spec.Paused=true` on each Cluster on the source before transferring objects. After all objects land on the target, finalizers are stripped from the source copies and the source Clusters are deleted bookkeeping-only (no Hetzner-side teardown). Workload clusters never notice.

### 3.3 Verify

```bash
# On the new mgmt cluster: all four Clusters, controllers reconciling.
export KUBECONFIG=~/.kube/tuist-mgmt.yaml
kubectl -n org-tuist get cluster
# Expect: tuist-staging, tuist-canary, tuist, tuist-preview: all Ready=True.

kubectl -n org-tuist get machinedeployment,machine,hcloudmachine
# Counts match what was on Syself (compare against /tmp/syself-pre-move-tree.txt).

# Each workload cluster: nodes still Ready, pods still running.
for kc in ~/.kube/tuist-{staging,canary,preview}.yaml ~/.kube/tuist.yaml; do
  echo "=== $kc ==="
  KUBECONFIG=$kc kubectl get nodes
done
```

The workload-cluster `KUBECONFIG_*` GitHub Environment secrets do **not** change: they point at each workload cluster's API server, which didn't move.

### 3.4 Smoke test deploys

```bash
gh workflow run server-deployment.yml -f environment=staging
gh workflow run server-deployment.yml -f environment=canary
# Production: only after staging + canary land cleanly.
```

A clean deploy proves CI-side reachability is intact for each environment.

### 3.5 Rollback (if §3.3 or §3.4 fails)

```bash
clusterctl move \
  --kubeconfig ~/.kube/tuist-mgmt.yaml \
  --to-kubeconfig ~/.kube/tuist-syself-mgmt.yaml \
  --namespace org-tuist
```

Same command, source and target swapped. Workload clusters again unaffected.

---

## Phase 4: cluster-autoscaler activation ([#10571](https://github.com/tuist/tuist/pull/10571) step 3)

The PR ships everything we need; we apply it against our mgmt cluster instead of waiting on a Syself ticket. Run this only after Phase 3's smoke tests are clean.

```bash
# 1. Apply the management-cluster RBAC. PR #10571 ships this at
#    infra/k8s/syself/processor-autoscaler-mgmt-rbac.yaml (will be renamed
#    to infra/k8s/mgmt/processor-autoscaler-rbac.yaml in a follow-up).
sed 's/__ORG_NS__/org-tuist/g' infra/k8s/syself/processor-autoscaler-mgmt-rbac.yaml \
  | kubectl --kubeconfig ~/.kube/tuist-mgmt.yaml apply -f -

# 2. Mint the kubeconfig the workload-cluster CA reads to talk to the mgmt
#    cluster. The token Secret was created by step 1.
SERVER=$(kubectl --kubeconfig ~/.kube/tuist-mgmt.yaml config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl --kubeconfig ~/.kube/tuist-mgmt.yaml -n org-tuist get secret processor-autoscaler-token -o jsonpath='{.data.ca\.crt}')
TOKEN=$(kubectl --kubeconfig ~/.kube/tuist-mgmt.yaml -n org-tuist get secret processor-autoscaler-token -o jsonpath='{.data.token}' | base64 -d)

cat > /tmp/ca-mgmt-kubeconfig.yaml <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: tuist-mgmt
    cluster:
      server: $SERVER
      certificate-authority-data: $CA
contexts:
  - name: ca
    context: { cluster: tuist-mgmt, namespace: org-tuist, user: processor-autoscaler }
users:
  - name: processor-autoscaler
    user: { token: $TOKEN }
current-context: ca
EOF

# 3. Push the kubeconfig to 1Password so ESO can sync it.
op document create /tmp/ca-mgmt-kubeconfig.yaml \
  --vault tuist-k8s-production \
  --title 'kubeconfig: cluster-autoscaler → tuist-mgmt'
shred -u /tmp/ca-mgmt-kubeconfig.yaml

# 4. The ExternalSecret in the platform chart picks it up. Flip the toggles.
helm upgrade platform infra/helm/platform \
  -n platform -f infra/helm/platform/values-hetzner.yaml \
  --set cluster-autoscaler.enabled=true \
  --set processor.autoscaling.enabled=true   # already true in production overlay; explicit here

# 5. Verify CA is up and seeing the MachineDeployment.
KUBECONFIG=~/.kube/tuist.yaml kubectl -n cluster-autoscaler logs -l app.kubernetes.io/name=cluster-autoscaler --tail=200
# Expect "Registered node group md-processor (min: 2, max: 6)".
```

Validate scaling end-to-end. Drop a synthetic burst of `process_build` jobs (or wait for the next real spike). Watch:

```bash
# KEDA scaling pods.
KUBECONFIG=~/.kube/tuist.yaml kubectl -n tuist-production get scaledobject,hpa,pods -l app.kubernetes.io/component=processor

# CA scaling nodes.
KUBECONFIG=~/.kube/tuist-mgmt.yaml kubectl -n org-tuist get machinedeployment md-processor -w
# Replicas climb from 2 → 3 → 4 as KEDA pushes pending pods.

# New cpx62s appearing in Hetzner Cloud (~60–120s each).
```

---

## Phase 5: Preview scaler activation ([syself-onboarding.md §9.6](syself-onboarding.md))

The preview Cluster CR is already on our mgmt cluster after Phase 3. What's left is unblocking the worker-pool scaling that's been pinned to `replicas: 1` since onboarding.

```bash
# Apply the preview-scaler RBAC against our mgmt cluster (same manifest, new
# target).
sed 's/__ORG_NS__/org-tuist/g' infra/k8s/syself/preview-mgmt-rbac.yaml \
  | kubectl --kubeconfig ~/.kube/tuist-mgmt.yaml apply -f -

# Mint a kubeconfig for the preview-scaler SA following the same pattern as
# §4 step 2-3 above. Push to 1Password and set as KUBECONFIG_MGMT in the
# server-k8s-preview GitHub Environment.

# Remove the `replicas: 1` pin in infra/k8s/syself/workload-cluster-preview.yaml
# (see the comment block at the top of that file). Re-apply against our
# new mgmt cluster:
kubectl --kubeconfig ~/.kube/tuist-mgmt.yaml apply -f infra/k8s/syself/workload-cluster-preview.yaml
```

This unblocks the design from §9.6 of [syself-onboarding.md](syself-onboarding.md): preview workers scale 0→1 on PR open, hourly sweep deletes both the namespace and the worker.

---

## Phase 6: Decommission Syself

Only after all four clusters have soaked on our mgmt cluster for ≥1 week and CA + preview scaler are active.

1. **Confirm no workflow references the Syself mgmt kubeconfig.**
   ```bash
   gh secret list --env <each environment>
   grep -r 'syself' .github/workflows/
   ```
2. **Rotate the shared Hetzner API token.** During migration we kept reusing `hetzner-tuist-syself` so caph on both old and new mgmt clusters could read it without coordination. Now: generate a fresh token in the workload-cluster Hetzner project, update our mgmt cluster's `hetzner` Secret, verify caph reconciliation lands a no-op, then revoke the old token in the Hetzner console.
   ```bash
   # New token in the workload Hetzner project, save to 1Password.
   op item edit 'hetzner-tuist-syself' credential='<new token>'

   # Push to our mgmt cluster.
   kubectl --kubeconfig ~/.kube/tuist-mgmt.yaml -n org-tuist \
     create secret generic hetzner \
     --from-literal=hcloud="$(op read 'op://Founders/hetzner-tuist-syself/credential')" \
     --from-literal=hcloud-ssh-key-name=tuist-syself \
     --dry-run=client -o yaml \
     | kubectl --kubeconfig ~/.kube/tuist-mgmt.yaml apply -f -

   # Confirm caph reconciles with the new token (no spurious server replacements).
   kubectl --kubeconfig ~/.kube/tuist-mgmt.yaml -n caph-system \
     logs -l control-plane=controller-manager --tail=200

   # Revoke the old token in Hetzner Cloud console once verified.
   ```
   Consider renaming the 1Password item to `hetzner-tuist-mgmt` post-rotation since the `-syself` suffix no longer reflects reality.
3. **Cancel the Syself subscription** via their console / support.
4. **Delete the Syself OIDC kubeconfig** from operator machines and 1Password:
   ```bash
   rm -rf ~/.kube/tuist-syself-mgmt.yaml ~/.kube/cache/oidc-login
   ```
5. **Replace [`syself-onboarding.md`](syself-onboarding.md) with a successor `onboarding.md`** that covers our mgmt cluster + workload bootstrap. Rename `infra/k8s/syself/` → `infra/k8s/clusters/`. Move the autoscaler RBAC manifest from `infra/k8s/syself/processor-autoscaler-mgmt-rbac.yaml` to `infra/k8s/mgmt/processor-autoscaler-rbac.yaml`.
6. **Archive this migration doc.** Move it to `infra/k8s/archive/2026-Q2-self-host-migration.md` so it stays as historical context without cluttering the active runbook surface.

---

## Operations going forward

| Activity | Cadence | Owner | Notes |
|---|---|---|---|
| OS patching of the mgmt VM | Monthly | Agent PR + human review | `apt update && apt upgrade && reboot`; mgmt cluster downtime is fine, workload clusters keep serving |
| caph + CSO upgrade | Quarterly | Agent PR + human review | Match upstream releases; test in staging by re-pointing to a throwaway mgmt cluster first |
| CAPI minor upgrade | ~Yearly | Engineer + agent | `clusterctl upgrade plan` then `clusterctl upgrade apply`; do alongside K8s minor bumps |
| Kubernetes minor bump (4 clusters) | Yearly | Engineer + agent | Bump `ClusterStack` version + each Cluster CR's `topology.version`; staging → canary → production over a few days |
| Etcd snapshot restore drill | Quarterly | Agent + supervise | Spin up a throwaway VM, restore the latest Tigris snapshot, confirm `kubectl get clusters` returns the expected state |
| ClusterStack release watch | Continuous | Agent | Issue when `syself/cluster-stacks` ships a new tag |
| Mgmt cluster downtime | Rare | Engineer | Workload clusters keep serving; preview scaling + autoscaler stop until restored |

Steady state: ~1–2h/month of engineer time with agent execution, plus a half-day for the K8s minor bump once or twice a year.

---

## Open items

All four originally-open items have been settled and folded into the runbook:

- **Firewall posture**: `:22` allowlisted to operator IPs, `:6443` public with cert auth. See §1.4 for why allowlisting `:6443` isn't tenable when CAPI replaces nodes.
- **Hetzner token rotation**: post-migration as a Phase 6 hardening step, not during cutover. See §Phase 6 step 2.
- **Tigris bucket**: `tuist-mgmt-etcd-snapshots`, retention 168 (7 days hourly), dedicated bucket-scoped key in 1Password as `tigris-tuist-mgmt-etcd`. See §1.8.
- **Workload-cluster etcd backup**: explicitly accepted as a gap. Workload clusters hold no state we can't reconstruct from Helm + ESO + 1Password; recovery is `kubectl apply` against the Cluster CR + ~30 min for nodes to come up. Revisit if a stateful in-cluster service ever lands. See trailing paragraph in §1.8.

---

## Troubleshooting

**`clusterctl move` fails partway through.**
The source mgmt cluster pauses reconciliation before the move; if it errors mid-flight, manually unpause on the source (`kubectl annotate cluster <name> cluster.x-k8s.io/paused-`) and try again with `--dry-run` first.

**Workload cluster nodes go NotReady right after `clusterctl move`.**
Almost certainly unrelated to the move (kubelet doesn't talk to the mgmt cluster). Check kubelet logs on the affected node, or look for an unrelated infrastructure issue.

**caph on the new mgmt cluster doesn't see existing HCloudMachines.**
The `hetzner` Secret in `org-tuist` is missing or has the wrong token. caph reconciles by querying Hetzner's API for the existing servers; without a valid token it can't observe state.

**`HCloudMachineTemplate` references a `ClusterStack` version that's missing on the new mgmt cluster.**
[`infra/k8s/syself/cluster-stack.yaml`](syself/cluster-stack.yaml) wasn't applied to the new mgmt cluster (Phase §1.7). Apply it; the operator will pull the release within a few minutes.

**cluster-autoscaler logs `failed to register node group: forbidden`.**
The `processor-autoscaler` SA in `org-tuist` is missing or its RoleBinding wasn't applied. Re-apply [`processor-autoscaler-mgmt-rbac.yaml`](syself/processor-autoscaler-mgmt-rbac.yaml) (the path moves in Phase 6 cleanup).
