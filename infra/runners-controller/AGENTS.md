# runners-controller

Kubernetes controller for `RunnerPool` CRDs. Runs in the workload
cluster, reconciles Pods + per-Pod `ServiceAccount`s that the Tuist
server's dispatch endpoint authenticates via the TokenReview API.

Two reconcilers, both on the same `RunnerPool` resource but with
independent workqueues:

- **`RunnerPoolReconciler`** — converges Pods + SAs to match
  `spec.replicas`. Idle Pods (those without the
  `tuist.dev/runner-pool-owner` label) are the only ones eligible for
  scale-down deletion; runners mid-job are never killed.

- **`AutoscalerReconciler`** — on a 5-second cadence, calls the
  server's `/api/internal/runners/desired_replicas` endpoint and
  patches `spec.replicas` (and, when configured, the bound CAPI
  `MachineDeployment.spec.replicas` in the management cluster). The
  policy math lives in `internal/scaling/desired.go`; tuning knobs
  (`minWarmPoolFloor`, `maxReplicas`, `scaleDownCooldownSeconds`)
  live in the `RunnerPool` spec, so a tuning change is helm-only.

## Management-cluster scaling (`--mgmt-kubeconfig`)

When `runnersController.mgmtCluster.enabled: true` in the chart, the
controller mounts a kubeconfig at
`/etc/tuist-runners-controller/mgmt-kubeconfig/kubeconfig` and
passes `--mgmt-kubeconfig` so the autoscaler reconciler can also
patch CAPI MachineDeployments. With this, the Pod-layer autoscaler
drives the node-layer scaling too — no separate cluster-autoscaler
required.

For a `RunnerPool` to participate, its
`spec.autoscaling.machineDeployment` block must point at the
backing MD via labels:

```yaml
spec:
  autoscaling:
    machineDeployment:
      namespace: org-tuist            # mgmt-cluster ns where the MD lives
      clusterName: tuist-staging      # CAPI Cluster's name
      deploymentName: runners-linux   # topology.workers.machineDeployments[].name
```

CAPI generates MD names from the topology + a random suffix, so a
name pin would break across cluster recreations. The label selector
matches `cluster.x-k8s.io/cluster-name` AND
`topology.cluster.x-k8s.io/deployment-name`; the controller refuses
to act if more than one MD matches (a topology bug).

### Bootstrap: minting the mgmt-cluster kubeconfig

The controller needs RBAC on the management cluster's
`org-tuist` namespace (or wherever the topology lives) for
`machinedeployments.cluster.x-k8s.io` — list + get + patch. Steps,
run against the management cluster's kubeconfig:

```bash
# 1. ServiceAccount the workload-cluster controller authenticates as
kubectl -n org-tuist create serviceaccount tuist-runners-controller

# 2. Role granting only the verbs the autoscaler uses
kubectl -n org-tuist apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: tuist-runners-controller
  namespace: org-tuist
rules:
  - apiGroups: ["cluster.x-k8s.io"]
    resources: ["machinedeployments"]
    verbs: ["get", "list", "patch"]
EOF

# 3. Bind the SA to the role
kubectl -n org-tuist create rolebinding tuist-runners-controller \
  --role=tuist-runners-controller \
  --serviceaccount=org-tuist:tuist-runners-controller

# 4. Issue a long-lived token. The mgmt cluster's CAPI controllers
#    aren't compromise-blast-radius-equivalent to the workload
#    cluster, but a 1-year cap is still appropriate. Re-mint and
#    re-sync via 1Password when rotation comes due.
kubectl -n org-tuist create token tuist-runners-controller \
  --duration=8760h > /tmp/mgmt-token

# 5. Build the kubeconfig the controller will use
mgmt_server=$(kubectl config view --raw \
  --minify -o jsonpath='{.clusters[0].cluster.server}')
mgmt_ca=$(kubectl config view --raw --minify \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

cat > /tmp/mgmt-kubeconfig <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: mgmt
    cluster:
      server: ${mgmt_server}
      certificate-authority-data: ${mgmt_ca}
users:
  - name: tuist-runners-controller
    user:
      token: $(cat /tmp/mgmt-token)
contexts:
  - name: default
    context:
      cluster: mgmt
      user: tuist-runners-controller
      namespace: org-tuist
current-context: default
EOF

# 6. Upload to 1Password (vault: tuist-k8s-staging,
#    item: MGMT_CLUSTER_KUBECONFIG, field: kubeconfig).
#    ESO syncs it into the workload cluster as the
#    `tuist-runners-controller-mgmt-kubeconfig` Secret per
#    `templates/runners-controller-mgmt-kubeconfig-external-secret.yaml`.
op document create --vault tuist-k8s-staging \
  --title MGMT_CLUSTER_KUBECONFIG /tmp/mgmt-kubeconfig

# 7. Tear down the local copies
shred -u /tmp/mgmt-token /tmp/mgmt-kubeconfig
```

After step 6, the next `helm upgrade` of the workload cluster
brings the controller online with `--mgmt-kubeconfig` set; the
autoscaler's MD scaling path activates on the next reconcile tick.

If `--mgmt-kubeconfig` is unset or the kubeconfig is invalid, the
controller logs at warning level and the MD-scaling path is a
no-op; the Pod-layer autoscaler still works.

## Linux runner substrate: Hetzner Robot bare-metal hosts (caph)

Linux runner Pods run as Firecracker microVMs (via Kata Containers)
on Hetzner Robot dedicated servers (AX42-U class for staging,
AX162-R for production). The hosts are adopted by `caph` from
pre-ordered Robot inventory through the standard CAPI bare-metal
flow:

```
operator orders AX42-U via Robot panel
        │
        │ (operator records server ID, adds a HetznerBareMetalHost CR
        │  in `infra/k8s/clusters/bare-metal-staging.yaml` referencing
        │  that server ID)
        ▼
HetznerBareMetalHost (mgmt cluster, org-tuist namespace)
        │
        │ (caph sees the new CR, reads Robot credentials from
        │  `hetzner-robot-credentials` Secret, contacts Robot API to
        │  reboot the box into rescue mode)
        ▼
Box boots Hetzner rescue system; caph SSHes in via the shared key
from `hetzner-bare-metal-ssh-key` Secret
        │
        │ (caph runs `installimage` per the HetznerBareMetalMachineTemplate
        │  spec — writes Ubuntu 24.04 LTS to RAID 1 across both NVMes)
        ▼
Box reboots into the freshly installed OS
        │
        │ (cloud-init runs the bare-metal worker KubeadmConfigTemplate:
        │  installs containerd + kubeadm + kubelet, then `kubeadm join`s
        │  the workload cluster with the runner-tier taint)
        ▼
Node registers in workload cluster, labeled
`node.cluster.x-k8s.io/pool=runners-linux` (from MD `metadata.labels`)
and `tuist.dev/kata-runtime=true` (from the post-kubeadm script)
        │
        │ (kata-deploy DaemonSet sees the kata-runtime label, installs
        │  Kata Containers + Firecracker binaries, configures
        │  containerd, restarts containerd)
        ▼
Node ready to schedule runner Pods (which carry
`runtimeClassName: kata-fc`, so each Pod becomes a microVM)
```

### Fleet credentials

Robot user/pass and the shared SSH key are fleet-level — one
Hetzner Robot account spans every AX-class host across staging /
canary / production — so both 1P items live in the mgmt cluster's
own vault and the mgmt cluster's ESO ClusterSecretStore syncs
them automatically:

| 1Password item (vault: `tuist-k8s-mgmt`) | Synced to (`org-tuist` ns)         | Consumer                                                  |
| ---------------------------------------- | ---------------------------------- | --------------------------------------------------------- |
| `HETZNER_WEBSERVICE`                     | Secret `hetzner-robot-credentials` | caph (Robot API for rescue / installimage)                |
| `HETZNER_BARE_METAL_SSH_KEY`             | Secret `hetzner-bare-metal-ssh-key`| caph (SSH into the rescue system)                         |

caph wants the Robot user/pass in the **same** Secret as the
hcloud token (the one HetznerClusterTemplate's `hetznerSecretRef`
names, today `org-tuist/hetzner`). The first time this branch is
applied, the operator does a one-time merge of the ESO-synced
keys into that Secret:

```bash
ROBOT_USER=$(kubectl --kubeconfig "$MGMT_KUBECONFIG" -n org-tuist \
  get secret hetzner-robot-credentials -o jsonpath='{.data.hetznerRobotUser}')
ROBOT_PASS=$(kubectl --kubeconfig "$MGMT_KUBECONFIG" -n org-tuist \
  get secret hetzner-robot-credentials -o jsonpath='{.data.hetznerRobotPassword}')
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n org-tuist patch secret hetzner \
  --type=merge -p "{\"data\":{\"hetznerRobotUser\":\"${ROBOT_USER}\",\"hetznerRobotPassword\":\"${ROBOT_PASS}\"}}"
```

After this, ESO refreshes `hetzner-robot-credentials` from 1P
hourly. The `hetzner` Secret only needs another patch if the
Robot creds rotate (rare); the SSH key path is fully declarative
since caph reads it from its own Secret.

### Bringing up a new bare-metal host (operator workflow)

1. **Order an AX-class server from [robot.hetzner.com](https://robot.hetzner.com)**.
   FSN1 for staging (matches the Cloud cluster region). Paste the
   shared SSH public key from
   `tuist-k8s-mgmt/HETZNER_BARE_METAL_SSH_KEY` (1Password,
   `public-key` field) into the order form. Wait for the email with
   the server ID and IP.

2. **Add a `HetznerBareMetalHost` CR** to
   `infra/k8s/clusters/bare-metal-staging.yaml`, modeled on the
   existing `bm-staging-2986829` entry. Set `serverID` to the new
   number; `rootDeviceHints` stays the same. The Secrets the host
   references are ESO-synced from the mgmt vault on apply, so no
   per-env bootstrap is needed.

3. **Bump `replicas` on the `runners-linux` MachineDeployment** in
   `infra/k8s/clusters/cluster-staging.yaml` to match the number of
   `HetznerBareMetalHost` CRs you now have. caph won't satisfy more
   replicas than there are host CRs, so the MD-replicas count is the
   "how many of our pre-ordered hosts do we want active right now"
   knob.

4. **Apply the management-cluster manifests** (the
   `mgmt-cluster-apply.yml` workflow reconciles
   `infra/k8s/clusters/` on push to `main`).

5. **Watch caph adopt the host**:

   ```bash
   kubectl --kubeconfig "$MGMT_KUBECONFIG" \
     -n org-tuist get hetznerbaremetalhost -w
   ```

   Status goes through `available` → `preparing` → `image-installing`
   → `provisioned` → `kubeadm-joined`. Total ~8-15 minutes for an
   AX42-U.

6. **Verify the Node registered** in the workload cluster:

   ```bash
   kubectl --kubeconfig "$STAGING_KUBECONFIG" get nodes \
     -l node.cluster.x-k8s.io/pool=runners-linux
   ```

   The kata-deploy DaemonSet auto-installs on this node (it watches
   for `tuist.dev/kata-runtime=true`). Wait for it to mark the node
   `katacontainers.io/kata-runtime=true` before runner Pods will
   schedule:

   ```bash
   kubectl --kubeconfig "$STAGING_KUBECONFIG" \
     -n tuist-staging get pods -l app.kubernetes.io/name=kata-deploy
   ```

7. **Bump `runnersFleetLinux.pools[].autoscaling.maxReplicas`** in
   `values-managed-staging.yaml` to match the new host density (16
   microVMs per AX42-U at the standard 1vCPU/4GB slot size). Then
   re-deploy the workload cluster's `tuist` helm release.

### Emergency SSH access

If a bare-metal host misbehaves and caph isn't responding, the
operator can SSH in directly using the shared key from
`tuist-k8s-mgmt/HETZNER_BARE_METAL_SSH_KEY`:

```bash
op read "op://tuist-k8s-mgmt/HETZNER_BARE_METAL_SSH_KEY/private-key" \
  --account=tuist.1password.com > /tmp/hbm
chmod 600 /tmp/hbm
ssh -i /tmp/hbm root@<host-ip>
# remember to: shred -u /tmp/hbm afterwards
```

The key remains valid through reinstalls because caph configures it
into `/root/.ssh/authorized_keys` as part of the cloud-init
bootstrap.
