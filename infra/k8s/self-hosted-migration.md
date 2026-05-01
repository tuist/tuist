# Self-Hosted Kubernetes Migration: From Syself Apalla to Tuist-Owned

Replace Syself's managed Cluster API control with our own management cluster running [Cluster API](https://cluster-api.sigs.k8s.io/) + Syself's [`caph`](https://github.com/syself/cluster-api-provider-hetzner) Hetzner provider directly. The topology layer that Syself's Apalla product provides via a proprietary `hetzner-apalla` ClusterStack gets replaced by a `ClusterClass` we author ourselves (see [`infra/k8s/clusters/`](clusters/)).

This document is a one-time migration plan. The successor onboarding doc (replacing [`syself-onboarding.md`](syself-onboarding.md)) is a separate artifact written after the cutover proves out.

## Why

- **Cost.** Syself adds ~25% on top of Hetzner. Roughly €85/mo (~€1k/yr) at current scale. Engineer cost dominates, but the line item isn't zero and grows with usage.
- **Control over RBAC.** The current blocker on [#10571](https://github.com/tuist/tuist/pull/10571) (cluster-autoscaler) and the long-blocked preview scaler ([syself-onboarding.md §9.6](syself-onboarding.md)) is the same gate: Syself OIDC users can't `create serviceaccounts,roles,rolebindings` in `org-tuist` without a support ticket. Owning the management cluster removes the gate permanently.
- **Vendor surface.** `caph` is the open-source Hetzner provider and stays. The piece we lose by leaving Syself is their `hetzner-apalla` ClusterStack (proprietary to Apalla, not publicly distributed); we replace it with a self-authored ClusterClass we control.

## Decisions locked

1. **Management cluster hosting**: separate Hetzner Cloud project (`tuist-mgmt`), isolated blast radius from the prod workload project.
2. **Management cluster shape**: single CCX13 VM (€16/mo) running [Talos Linux](https://www.talos.dev) as a single-node Kubernetes control plane (etcd embedded in the kubelet's static-pod manifests, scheduling allowed on the control plane). Cattle, not pet: rebuilt from machine config + an etcd snapshot in ~30 min if it dies. Talos is immutable, configured declaratively via `talosctl apply-config`, no SSH.
3. **CA topology**: per-workload-cluster, exactly the shape [#10571](https://github.com/tuist/tuist/pull/10571) wires (CA runs in the workload cluster, talks to the management cluster via a kubeconfig Secret).
4. **SSO replacement**: per-person kubeconfigs + talosconfigs distributed via 1Password (we already use ESO + 1Password everywhere). No Tailscale dependency to introduce.
5. **Workload-cluster runtime stays kubeadm-based.** Talos is the mgmt cluster only. The four workload clusters keep running kubeadm-bootstrapped vanilla Ubuntu nodes (provisioned by caph). Two distributions to operate, but the boundary is clean: Talos on the controller node only.
6. **Topology layer: a ClusterClass we author**, not a third-party ClusterStack. Syself's `hetzner-apalla` stack is proprietary and unavailable outside their Apalla product, so we replace it with a ClusterClass forked from caph's reference templates and adapted for our two-pool production topology. No `cluster-stack-operator` to install. See [`infra/k8s/clusters/`](clusters/).

## Scope and non-scope

**In scope:** the four Cluster CRs in [`infra/k8s/syself/`](syself/) (`tuist-staging`, `tuist-canary`, `tuist`, `tuist-preview`) and their CAPI-rendered children (KubeadmControlPlane, KubeadmConfigTemplate, HCloudMachineTemplate, MachineDeployment, Machine). These get rewritten to topology mode against our `tuist-hcloud` ClusterClass during cutover.

**Explicitly NOT migrated:** the Apalla `ClusterStack` + `HetznerClusterStackReleaseTemplate` CRs in [`infra/k8s/syself/cluster-stack.yaml`](syself/cluster-stack.yaml). These reference Apalla machinery we don't have on the new mgmt cluster (no CSO, no `clusterstack.x-k8s.io` CRDs).

**Out of scope (today):** the cache, xcode-processor, and search clusters are not on Syself today; their workflows hold separate `KUBECONFIG_*` secrets pointing at different infrastructure. They're planned to consolidate onto Syself-shaped Cluster API in the future; when they do, they'll land directly on our self-hosted management cluster (no Syself path needed) and join `org-tuist` alongside the four migrated here.

---

## Prerequisites

- A Hetzner Cloud account with permission to create a new project.
- The current Syself management-cluster kubeconfig (per-person OIDC, used during `clusterctl move`).
- CLI tools:
  ```bash
  mise use -g kubectl helm clusterctl talosctl
  ```
  Plus [`hcloud-upload-image`](https://github.com/apricote/hcloud-upload-image) (one-time install: `go install github.com/apricote/hcloud-upload-image@latest` or grab the binary from the release page).
- The 1Password CLI (`op`).
- A Tigris bucket for etcd snapshots (we'll create one in §1.8 if it doesn't exist yet).

## Phase 1: Stand up the management cluster

### 1.1 Hetzner project + token

In the Hetzner Cloud console:
1. Create a new project named `tuist-mgmt`. Switch into it.
2. Security → API tokens → Generate API token. Permission is read+write (only option). Name it `tuist-mgmt-caph`.

Save the token to 1Password:

```bash
op item create --vault Founders --category='API Credential' \
  --title='hetzner-tuist-mgmt' \
  credential='<paste token>'
```

No SSH key needed. Talos doesn't run an SSH daemon; all node operations go through `talosctl` over its own mTLS API on `:50000`.

### 1.2 Upload a Talos snapshot to Hetzner Cloud

Hetzner Cloud only boots its own images, so we publish a Talos disk image as a Hetzner Cloud snapshot first. One-time per Talos version.

The Talos image factory builds Talos with the extensions you specify. We don't need any extensions for the mgmt cluster: vanilla Talos has Hetzner support built in. The vanilla schematic id is `376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba` (visit <https://factory.talos.dev> if you want to add extensions later).

```bash
export HCLOUD_TOKEN="$(op read 'op://Founders/hetzner-tuist-mgmt/credential')"

export TALOS_VERSION=v1.13.0
export TALOS_SCHEMATIC=376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba

hcloud-upload-image upload \
  --image-url "https://factory.talos.dev/image/${TALOS_SCHEMATIC}/${TALOS_VERSION}/hcloud-amd64.raw.xz" \
  --compression xz \
  --architecture x86 \
  --description "talos-${TALOS_VERSION}" \
  --labels "talos-version=${TALOS_VERSION},purpose=mgmt-cluster"

# Output includes the snapshot id. Capture it.
hcloud image list --type snapshot --output noheader \
  | awk -v desc="talos-${TALOS_VERSION}" '$0 ~ desc {print $1}'
```

Save the snapshot id; we'll reference it in §1.3.

### 1.3 Provision the VM and apply the Talos machine config

```bash
export TALOS_IMAGE_ID=<snapshot id from 1.2>

# Create the server from the Talos snapshot. CCX13 = 2 dedicated vCPU, 8 GiB.
hcloud server create \
  --name tuist-mgmt \
  --type ccx13 \
  --image "$TALOS_IMAGE_ID" \
  --location fsn1 \
  --output json \
  | tee /tmp/tuist-mgmt-create.json \
  | jq -r '"server_id=\(.server.id) ip=\(.server.public_net.ipv4.ip)"'

export MGMT_SERVER_ID=$(jq -r '.server.id' /tmp/tuist-mgmt-create.json)
export MGMT_IP=$(jq -r '.server.public_net.ipv4.ip' /tmp/tuist-mgmt-create.json)

# Wait for Talos to boot into maintenance mode (~30s).
until talosctl version --nodes "$MGMT_IP" --insecure --short 2>/dev/null; do sleep 5; done

# Generate machine config (controlplane + worker + talosconfig). For a
# single-node cluster, we only use controlplane.yaml, plus a strategic
# merge patch to allow scheduling on the control plane.
mkdir -p /tmp/tuist-mgmt-config
cat > /tmp/tuist-mgmt-config/patch.yaml <<'YAML'
cluster:
  allowSchedulingOnControlPlanes: true
YAML

talosctl gen config tuist-mgmt "https://${MGMT_IP}:6443" \
  --output /tmp/tuist-mgmt-config \
  --with-docs=false \
  --with-examples=false \
  --config-patch @/tmp/tuist-mgmt-config/patch.yaml

# Apply the controlplane config (insecure = trust on first use; thereafter
# the talosconfig has client certs and we drop --insecure).
talosctl apply-config --insecure \
  --nodes "$MGMT_IP" \
  --file /tmp/tuist-mgmt-config/controlplane.yaml

# Bootstrap etcd (single member quorum).
export TALOSCONFIG=/tmp/tuist-mgmt-config/talosconfig
talosctl config endpoint "$MGMT_IP"
talosctl config node "$MGMT_IP"
until talosctl bootstrap; do sleep 5; done

# Pull the kubeconfig.
talosctl kubeconfig ~/.kube/tuist-mgmt.yaml
chmod 600 ~/.kube/tuist-mgmt.yaml

export KUBECONFIG=~/.kube/tuist-mgmt.yaml
until kubectl get nodes 2>/dev/null | grep -q Ready; do sleep 5; done
kubectl get nodes
# Expect 1 Ready node, both control-plane and worker roles.
```

Stash the talosconfig and kubeconfig in 1Password:

```bash
op document create /tmp/tuist-mgmt-config/talosconfig \
  --vault Founders --title 'talosconfig: tuist-mgmt'
op document create ~/.kube/tuist-mgmt.yaml \
  --vault Founders --title 'kubeconfig: tuist-mgmt'

# Wipe local generated configs once they're in 1Password (they hold
# admin certs).
shred -u /tmp/tuist-mgmt-config/controlplane.yaml \
        /tmp/tuist-mgmt-config/worker.yaml \
        /tmp/tuist-mgmt-config/talosconfig
```

### 1.4 Lock down the API endpoints

Two ports on the VM matter:
- `:50000`: talosctl API (machine config, etcd snapshots, system logs). Operator-IP allowlist.
- `:6443`: kube-apiserver. Public + x509 client-cert auth.

The reason `:6443` isn't allowlisted: cluster-autoscaler runs in each workload cluster and talks to the mgmt API from its node's IP. CAPI replaces nodes on scale and health events, so per-node allowlisting isn't maintainable. Hetzner Cloud Networks would solve it (private API) but cross-project networks don't exist and we locked mgmt into a separate Hetzner project for blast-radius isolation. Cert auth is robust enough on its own; we accept the trade.

Talos's etcd ports (`:2379`, `:2380`) and kubelet API (`:10250`) are exposed only on the loopback / node interface by default; no firewall rule needed to keep them off the public internet.

```bash
HCLOUD_TOKEN="$(op read 'op://Founders/hetzner-tuist-mgmt/credential')"

# Operator IPs to allowlist for talosctl. Add more as the team grows.
OPERATOR_IPS='["<your-ip>/32"]'

curl -sX POST https://api.hetzner.cloud/v1/firewalls \
  -H "Authorization: Bearer $HCLOUD_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --argjson ops "$OPERATOR_IPS" --argjson sid "$MGMT_SERVER_ID" '{
    name: "tuist-mgmt",
    rules: [
      {direction: "in", protocol: "tcp", port: "50000", source_ips: $ops},
      {direction: "in", protocol: "tcp", port: "6443",  source_ips: ["0.0.0.0/0", "::/0"]}
    ],
    apply_to: [{type: "server", server: {id: $sid}}]
  }')"
```

### 1.5 Initialize CAPI + caph

`clusterctl init` bootstraps the providers directly into Talos. Two pieces, two version pins.

| Component | Version | Source |
|---|---|---|
| CAPI core | `v1.13.1` | <https://github.com/kubernetes-sigs/cluster-api/releases> |
| caph | `v1.1.0`  | <https://github.com/syself/cluster-api-provider-hetzner/releases> |

clusterctl 1.13 is v1beta2-native and reads v1beta1 CRs cleanly via conversion webhooks, so a version skew with Syself's controllers (which we can't introspect from `org-tuist`) is safe.

We do **not** install `cluster-stack-operator`. The original plan was to use it with Syself's `hetzner-apalla` ClusterStack, but that stack turned out to be Apalla-proprietary. Topology is handled by a ClusterClass we author ourselves (Phase 1.5).

```bash
export KUBECONFIG=~/.kube/tuist-mgmt.yaml

export CAPI_VERSION=v1.13.1
export CAPH_VERSION=v1.1.0

clusterctl init \
  --core "cluster-api:$CAPI_VERSION" \
  --bootstrap "kubeadm:$CAPI_VERSION" \
  --control-plane "kubeadm:$CAPI_VERSION" \
  --infrastructure "hetzner:$CAPH_VERSION"

# Verify everything is Running.
kubectl get pods -A
```

### 1.6 Recreate the org namespace + Hetzner Secret

Keep the namespace name `org-tuist` so existing manifests reference unchanged.

```bash
kubectl create namespace org-tuist

# The hetzner Secret caph reads when reconciling Cluster CRs. The token must
# match the Hetzner project that owns the workload-cluster servers (NOT the
# mgmt project). Reuse the existing `hetzner-tuist-workloads` token for now;
# rotate post-migration as a separate hardening step.
kubectl -n org-tuist create secret generic hetzner \
  --from-literal=hcloud="$(op read 'op://Founders/hetzner-tuist-workloads/credential')" \
  --from-literal=hcloud-ssh-key-name=tuist-syself
```

### 1.7 Apply our ClusterClass

The Apalla ClusterStack does not migrate (proprietary, see Decisions §6). We apply our own ClusterClass forked from caph's reference templates. The class lives at [`infra/k8s/clusters/clusterclass-tuist.yaml`](clusters/) and is authored + validated in Phase 1.5.

```bash
kubectl apply -f infra/k8s/clusters/clusterclass-tuist.yaml
kubectl -n org-tuist get clusterclass tuist-hcloud
```

Phase 1.5 below covers the authoring + validation work that has to land before this step is meaningful.

### 1.8 etcd snapshots → Tigris

Talos doesn't ship with built-in S3 snapshot upload (k3s does; Talos doesn't). The standard pattern is an in-cluster `CronJob` that calls `talosctl etcd snapshot` against the node and uploads the resulting `.db` file to S3. Hourly cadence, retention 168 (= 7 days, enforced by Tigris bucket lifecycle policy). Bucket `tuist-mgmt-etcd-snapshots`, bucket-scoped access key in 1Password as `tigris-tuist-mgmt-etcd` with `access_key_id` + `secret_access_key` fields.

**1. Tigris setup.** Create the bucket + a bucket-scoped access key in the Tigris dashboard. The key needs `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject` on `tuist-mgmt-etcd-snapshots/*` and `s3:ListBucket` on the bucket itself. Tigris's "read-write" preset on a single bucket usually covers this, but verify after creation by uploading a test object from your laptop:

```bash
echo hi | AWS_ACCESS_KEY_ID="$(op read 'op://Founders/tigris-tuist-mgmt-etcd/access_key_id')" \
  AWS_SECRET_ACCESS_KEY="$(op read 'op://Founders/tigris-tuist-mgmt-etcd/secret_access_key')" \
  AWS_DEFAULT_REGION=auto \
  aws --endpoint-url=https://fly.storage.tigris.dev s3api put-object \
  --bucket tuist-mgmt-etcd-snapshots --key healthcheck.txt --body /dev/stdin
```

Add a lifecycle rule that deletes objects older than 7 days. Save the keys to 1Password.

**2. Generate a restricted talosconfig** for the snapshotter (role `os:etcd:backup` covers `etcd snapshot` and nothing else). The CronJob runs hostNetwork on the control-plane node and connects via the public IP because that's the only address in talosd's TLS cert SAN list (127.0.0.1 isn't):

```bash
# Use the admin talosconfig from /tmp/tuist-mgmt-config/talosconfig (Phase
# 1.3) or pull a fresh copy from 1Password if that's been shredded:
#   op document get 'talosconfig: tuist-mgmt' --vault Founders > /tmp/admin-talosconfig
#   export TALOSCONFIG=/tmp/admin-talosconfig
export TALOSCONFIG=/tmp/tuist-mgmt-config/talosconfig

talosctl config new --roles os:etcd:backup /tmp/snapshotter-talosconfig
talosctl --talosconfig /tmp/snapshotter-talosconfig config endpoint "$MGMT_IP"
talosctl --talosconfig /tmp/snapshotter-talosconfig config node "$MGMT_IP"
```

**3. Apply the CronJob and Secrets.** The manifest is checked in at [`infra/k8s/mgmt/etcd-snapshot.yaml`](mgmt/etcd-snapshot.yaml). It creates the `mgmt-system` namespace (labeled `pod-security.kubernetes.io/enforce: privileged` because hostNetwork is needed) and the CronJob. We add the two Secrets it expects: `talos-snapshotter-config` (the restricted talosconfig from step 2) and `tigris-credentials` (Tigris access key).

```bash
export KUBECONFIG=~/.kube/tuist-mgmt.yaml

kubectl apply -f infra/k8s/mgmt/etcd-snapshot.yaml

kubectl -n mgmt-system create secret generic talos-snapshotter-config \
  --from-file=talosconfig=/tmp/snapshotter-talosconfig

kubectl -n mgmt-system create secret generic tigris-credentials \
  --from-literal=access_key_id="$(op read 'op://Founders/tigris-tuist-mgmt-etcd/access_key_id')" \
  --from-literal=secret_access_key="$(op read 'op://Founders/tigris-tuist-mgmt-etcd/secret_access_key')"

shred -u /tmp/snapshotter-talosconfig
```

Verify the first run within an hour:

```bash
kubectl -n mgmt-system get cronjob etcd-snapshot
kubectl -n mgmt-system logs -l job-name --tail=50
# Or trigger immediately:
kubectl -n mgmt-system create job --from=cronjob/etcd-snapshot etcd-snapshot-manual
kubectl -n mgmt-system logs job/etcd-snapshot-manual
```

The mgmt cluster's etcd holds CAPI CRs, Secrets, and ClusterClass state: everything `clusterctl move` (or our hand-rolled equivalent) would replay if we ever rebuild from a snapshot. The workload clusters' own etcds (per-cluster KubeadmControlPlane quorums) are *not* covered by this; that's intentional, since workload clusters hold no state we can't reconstruct from Helm + ESO + 1Password. If a stateful in-cluster service ever lands, revisit.

---

## Phase 1.5: Author and validate the ClusterClass

The Apalla ClusterStack we used to depend on (`hetzner-apalla-1-34-v6`) is Syself-proprietary. Our replacement is a self-authored `ClusterClass` named `tuist-hcloud`, forked from caph's published reference templates and adapted for our two-pool production topology (general + processor) plus the simpler 1-pool shape used by staging / canary / preview.

This phase has to complete before Phase 2 cutover. Workload clusters can keep running on Syself's Apalla in the meantime.

### 1.5.1 Fork caph's reference ClusterClass

The reference templates are checked in unchanged at [`infra/k8s/clusters/reference-templates/`](clusters/reference-templates/). Start from `cluster-class.yaml` and adapt:

- **Class name**: `quick-start` → `tuist-hcloud`.
- **Add a worker pool variable for processor-class machines** (default `cpx62`), distinct from the default `hcloud-worker` class which is general-purpose. Mirrors the existing `md-processor` MachineDeployment in production.
- **Pool labels**: expose `node.cluster.x-k8s.io/pool` as a per-MachineDeployment variable so both `pool=general` (current `md-0` on production) and `pool=processor` (current `md-processor`) propagate to kubelet labels. The label prefix is required by kubeadm to allow the kubelet to set it during registration.
- **Cluster-autoscaler annotations**: emit `cluster.x-k8s.io/cluster-autoscaler-node-group-{min,max}-size` on the MachineDeployment template, sourced from variables. PR [#10571](https://github.com/tuist/tuist/pull/10571) currently sets these manually on `md-processor`; the ClusterClass should set them by default for any pool that opts in.

Save as `infra/k8s/clusters/clusterclass-tuist.yaml`.

### 1.5.2 Convert per-cluster manifests to topology mode

Adapt each existing `infra/k8s/syself/workload-cluster-{staging,canary,production,preview}.yaml` into a topology-mode Cluster CR pointing at `tuist-hcloud`. Save as `infra/k8s/clusters/cluster-<env>.yaml`. Each file shrinks from ~80 lines to ~30. Variables override what differs (control plane size, machine types, pool replica counts, scaling annotations).

The original `infra/k8s/syself/*.yaml` files stay in place until Phase 6 cleanup. Source-of-truth flip happens during Phase 2/3.

### 1.5.3 Validate against a throwaway 5th cluster

Don't apply the new ClusterClass to any of the four production-bound clusters yet. Validate by spinning up a disposable test cluster on the new mgmt cluster:

```bash
kubectl apply -f infra/k8s/clusters/clusterclass-tuist.yaml

# A minimal 1-CP + 1-worker test cluster, distinct from the four real clusters.
cat <<'YAML' | kubectl apply -f -
apiVersion: cluster.x-k8s.io/v1beta2
kind: Cluster
metadata:
  name: tuist-cc-validation
  namespace: org-tuist
spec:
  topology:
    classRef: { name: tuist-hcloud }
    version: v1.34.6
    controlPlane: { replicas: 1 }
    workers:
      machineDeployments:
        - class: hcloud-worker
          name: md-0
          replicas: 1
          failureDomain: fsn1
          variables:
            overrides:
              - name: hcloudWorkerMachineType
                value: cpx22
YAML

# Wait for Ready, sanity-check, then delete.
kubectl -n org-tuist get cluster tuist-cc-validation -w
# After Ready=True:
kubectl -n org-tuist delete cluster tuist-cc-validation
```

Total cost of the validation cluster: a few cents (it lives 10–15 min before deletion).

### 1.5.4 Compare rendered manifests against Syself's

To make Phase 2 cutover land as a no-op (so `clusterctl move` doesn't trigger a rolling rebuild on production nodes), the KubeadmControlPlane / KubeadmConfigTemplate / HCloudMachineTemplate that our ClusterClass renders must match what Syself's Apalla CSO already rendered. Read the existing rendered resources from Syself's mgmt cluster and diff:

```bash
KUBECONFIG=~/.kube/tuist-syself-mgmt.yaml \
  kubectl -n org-tuist get kubeadmcontrolplane,kubeadmconfigtemplate,hcloudmachinetemplate -o yaml \
  > /tmp/syself-rendered.yaml

# Compare against what the ClusterClass produces against tuist-cc-validation
# (or one of the env-specific test renderings via `clusterctl alpha topology plan`).
diff -u /tmp/syself-rendered.yaml /tmp/our-rendered.yaml | less
```

Iterate on the ClusterClass until the diff is either empty or limited to fields CAPI is happy to reconcile in place (label/annotation drift is fine; spec differences trigger rolling rebuilds we want to avoid during cutover).

If a no-op landing isn't achievable in reasonable time, the fallback is to accept a rolling rebuild during cutover, which means staggering env cutovers (staging first, week of soak per env) instead of the all-at-once cutover currently in Phase 3.

---

## Phase 2: Cutover preflight

> **Important constraint #1:** [`clusterctl move`](https://cluster-api.sigs.k8s.io/clusterctl/commands/move.html) is **namespace-scoped, not cluster-scoped**: it moves every CAPI object in `org-tuist` in a single operation, including all four Clusters at once. There's no `--filter-cluster`, and the block-move annotation pauses the *whole* move, not individual clusters.
>
> **Important constraint #2:** the source side has Apalla's `ClusterStack` + `HetznerClusterStackReleaseTemplate` CRs in `org-tuist`. The target side doesn't have CSO or its CRDs. `clusterctl move` will refuse to migrate those resources because the target lacks the `clusterstack.x-k8s.io` CRDs. We treat this as a feature (we don't want them on the target) and pre-strip references on the source side before invoking `move`.
>
> **Important constraint #3:** every `Cluster` CR on the source side currently has `topology.classRef.name: hetzner-apalla-1-34-v6`. After move (or hand-roll) we rewrite each Cluster CR to `topology.classRef.name: tuist-hcloud`. If Phase 1.5.4's diff exercise produced a no-op render, this swap is a CR edit only; no rolling rebuilds. If not, expect a controlled rolling replacement (stagger envs accordingly).

The plan: cut over all four clusters in one maintenance window. Workload clusters keep serving traffic during and after the move (kubelet certificates are signed by each workload cluster's own CA, independent of the management plane).

### 2.1 Source preflight

```bash
export KUBECONFIG=~/.kube/tuist-syself-mgmt.yaml
ORG_NS=org-tuist

# All four Clusters healthy.
kubectl -n "$ORG_NS" get cluster
# Each: Ready=True, ControlPlaneReady=True, InfrastructureReady=True.

# Inventory what `clusterctl move` will be touching. Save the output: it's
# the rollback reference.
clusterctl describe cluster --show-tree > /tmp/syself-pre-move-tree.txt
```

### 2.2 Target preflight

```bash
export KUBECONFIG=~/.kube/tuist-mgmt.yaml

# Our ClusterClass is applied and ready (Phase 1.5).
kubectl -n org-tuist get clusterclass tuist-hcloud
# Expect: present, no errors in describe.

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
# HetznerClusters, HCloudMachineTemplates, HCloudMachines, Machines, Secrets.
# The Apalla ClusterStack/HetznerClusterStackReleaseTemplate will surface as
# a CRD-mismatch error; that's expected; pre-strip them in Phase 3.1.
```

---

## Phase 3: Cutover (all four clusters, one maintenance window)

Schedule a ~2h window during low traffic. The actual move takes 5–10 min; the rest is verification + soak start.

Comms: post in the team channel that the management plane is moving: workload clusters keep serving, but nothing CAPI-driven (scaling, node replacement, preview workflows) will succeed during the window. CI deploys to workload clusters are unaffected (they target the workload kubeconfig, not the mgmt cluster).

### 3.1 Snapshot etcd on both sides

```bash
# Source side: Syself manages this; nothing to do.

# Target side (our mgmt): force a Talos etcd snapshot before the move.
talosctl --talosconfig "$(op read 'op://Founders/talosconfig: tuist-mgmt/document')" \
  etcd snapshot /tmp/pre-cutover.db
ls -la /tmp/pre-cutover.db
# Optional: upload to Tigris with a recognizable name for the rollback window.
```

### 3.2 Pre-strip Apalla references on the source side

`clusterctl move` will refuse to migrate Apalla's `ClusterStack` / `HetznerClusterStackReleaseTemplate` because the target lacks those CRDs. Pre-strip them on the source so the move is clean:

```bash
KUBECONFIG=~/.kube/tuist-syself-mgmt.yaml kubectl -n org-tuist \
  patch clusterstack hetzner-apalla-1-34 -p '{"metadata":{"finalizers":[]}}' --type=merge

KUBECONFIG=~/.kube/tuist-syself-mgmt.yaml kubectl -n org-tuist \
  delete clusterstack hetzner-apalla-1-34 \
    hetznerclusterstackreleasetemplate/hetzner-apalla-1-34 --wait=false
```

The four `Cluster` CRs still reference `topology.classRef.name: hetzner-apalla-1-34-v6`. That's fine for now; Apalla's CSO won't reconcile after we strip the ClusterStack, but the rendered children (KCP / MD / templates) keep CAPI happy until move.

### 3.3 Move

```bash
clusterctl move \
  --kubeconfig ~/.kube/tuist-syself-mgmt.yaml \
  --to-kubeconfig ~/.kube/tuist-mgmt.yaml \
  --namespace org-tuist
```

The command sets `Cluster.Spec.Paused=true` on each Cluster on the source before transferring objects. After all objects land on the target, finalizers are stripped from the source copies and the source Clusters are deleted bookkeeping-only (no Hetzner-side teardown). Workload clusters never notice.

### 3.4 Rewrite Cluster CRs to point at our ClusterClass

Each moved Cluster still has `topology.classRef.name: hetzner-apalla-1-34-v6`. Swap to `tuist-hcloud`. If Phase 1.5.4's diff exercise produced a no-op render, this is a one-line edit and CAPI sees no spec drift:

```bash
export KUBECONFIG=~/.kube/tuist-mgmt.yaml

for c in tuist-staging tuist-canary tuist tuist-preview; do
  kubectl -n org-tuist patch cluster $c --type=merge \
    -p '{"spec":{"topology":{"classRef":{"name":"tuist-hcloud"}}}}'
done

# Watch for any rolling rebuild signals (Machine deletions you didn't expect).
kubectl -n org-tuist get machine -w
```

If the render diff in Phase 1.5.4 wasn't fully no-op, expect rolling MachineDeployment replacement during this step. Stagger the patch calls and let each cluster stabilize before moving to the next.

### 3.5 Verify

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

### 3.6 Smoke test deploys

```bash
gh workflow run server-deployment.yml -f environment=staging
gh workflow run server-deployment.yml -f environment=canary
# Production: only after staging + canary land cleanly.
```

A clean deploy proves CI-side reachability is intact for each environment.

### 3.7 Rollback (if §3.5 or §3.6 fails)

Rollback is harder than the original plan because Apalla's stack was pre-stripped in §3.2: rolling back requires re-applying [`infra/k8s/syself/cluster-stack.yaml`](syself/cluster-stack.yaml) on Syself's mgmt cluster *and* reverting the Cluster CRs' `topology.classRef.name` swap. Sequence:

```bash
# 1. Re-apply Apalla's ClusterStack on Syself's mgmt cluster.
KUBECONFIG=~/.kube/tuist-syself-mgmt.yaml kubectl apply -f infra/k8s/syself/cluster-stack.yaml

# 2. Revert each Cluster CR's topology.classRef name (still on our mgmt cluster).
for c in tuist-staging tuist-canary tuist tuist-preview; do
  kubectl --kubeconfig ~/.kube/tuist-mgmt.yaml -n org-tuist patch cluster $c --type=merge \
    -p '{"spec":{"topology":{"classRef":{"name":"hetzner-apalla-1-34-v6"}}}}'
done

# 3. Move back.
clusterctl move \
  --kubeconfig ~/.kube/tuist-mgmt.yaml \
  --to-kubeconfig ~/.kube/tuist-syself-mgmt.yaml \
  --namespace org-tuist
```

Workload clusters keep serving traffic during rollback (kubelet certs are workload-cluster-CA signed).

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
2. **Rotate the shared Hetzner API token.** During migration we kept reusing `hetzner-tuist-workloads` so caph on both old and new mgmt clusters could read it without coordination. Now: generate a fresh token in the workload-cluster Hetzner project, update our mgmt cluster's `hetzner` Secret, verify caph reconciliation lands a no-op, then revoke the old token in the Hetzner console.
   ```bash
   # New token in the workload Hetzner project, save to 1Password.
   op item edit 'hetzner-tuist-workloads' credential='<new token>'

   # Push to our mgmt cluster.
   kubectl --kubeconfig ~/.kube/tuist-mgmt.yaml -n org-tuist \
     create secret generic hetzner \
     --from-literal=hcloud="$(op read 'op://Founders/hetzner-tuist-workloads/credential')" \
     --from-literal=hcloud-ssh-key-name=tuist-syself \
     --dry-run=client -o yaml \
     | kubectl --kubeconfig ~/.kube/tuist-mgmt.yaml apply -f -

   # Confirm caph reconciles with the new token (no spurious server replacements).
   kubectl --kubeconfig ~/.kube/tuist-mgmt.yaml -n caph-system \
     logs -l control-plane=controller-manager --tail=200

   # Revoke the old token in Hetzner Cloud console once verified.
   ```
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
| Talos image upgrade for the mgmt VM | Monthly | Agent PR + human review | `talosctl upgrade --image=...`; Talos is immutable and atomic: bumps replace the running image, ~2 min of mgmt API downtime per upgrade. No `apt`. Workload clusters keep serving. |
| caph upgrade | Quarterly | Agent PR + human review | `clusterctl upgrade plan`/`apply` for caph; rebase our ClusterClass against any upstream changes in caph's reference templates (see [`infra/k8s/clusters/reference-templates/`](clusters/reference-templates/)) |
| CAPI minor upgrade | ~Yearly | Engineer + agent | `clusterctl upgrade plan` then `clusterctl upgrade apply`; do alongside K8s minor bumps |
| Kubernetes minor bump (4 clusters) | Yearly | Engineer + agent | Bump each Cluster CR's `topology.version`; refresh node images / cloud-init in the ClusterClass if needed; staging → canary → production over a few days |
| Etcd snapshot restore drill | Quarterly | Agent + supervise | Spin up a throwaway VM, restore the latest Tigris snapshot, confirm `kubectl get clusters` returns the expected state |
| caph reference-template refresh | On caph minor releases | Agent | `curl` the new release assets into [`infra/k8s/clusters/reference-templates/`](clusters/reference-templates/), diff against our `clusterclass-tuist.yaml`, port any upstream improvements |
| Mgmt cluster downtime | Rare | Engineer | Workload clusters keep serving; preview scaling + autoscaler stop until restored |

Steady state: ~1–2h/month of engineer time with agent execution, plus a half-day for the K8s minor bump once or twice a year.

---

## Open items

All four originally-open items have been settled and folded into the runbook:

- **Firewall posture**: `:50000` (talosctl) allowlisted to operator IPs, `:6443` public with cert auth. No SSH (Talos has no SSH daemon). See §1.4 for why allowlisting `:6443` isn't tenable when CAPI replaces nodes.
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

**`Cluster` reports `topology.classRef.name` not found.**
The `tuist-hcloud` ClusterClass wasn't applied to the new mgmt cluster, or it errored. `kubectl -n org-tuist describe clusterclass tuist-hcloud` and `kubectl apply -f infra/k8s/clusters/clusterclass-tuist.yaml` to retry.

**cluster-autoscaler logs `failed to register node group: forbidden`.**
The `processor-autoscaler` SA in `org-tuist` is missing or its RoleBinding wasn't applied. Re-apply [`processor-autoscaler-mgmt-rbac.yaml`](syself/processor-autoscaler-mgmt-rbac.yaml) (the path moves in Phase 6 cleanup).
