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

## Linux runner substrate: Hetzner Robot bare-metal hosts

Linux runner Pods run on Hetzner Robot dedicated servers (AX42-U
class, FSN1 datacenter). The hosts join the staging workload cluster
as worker Nodes via `kubeadm join` and are taint+labeled so that only
runner Pods land on them.

In v1 they are **not CAPI-managed** — `caph`'s `HetznerBareMetalHost`
flow (rescue-boot + `installimage` + cloud-init `kubeadm join`) is
the eventual target for production scale-up, but for staging
bring-up the operator drives this manually. Each host is ordered
via the Robot panel, joined once, and lives for as long as it makes
economic sense.

### Bringing up a new bare-metal host

Prerequisites:
- Host has been ordered from [robot.hetzner.com](https://robot.hetzner.com),
  provisioned, and is reachable via SSH using the shared key in
  1Password (`tuist-k8s-staging/HETZNER_BARE_METAL_SSH_KEY`).
- The workload cluster control plane is healthy and reachable on the
  cluster's API server endpoint.

Steps (run from a workstation that has both the workload-cluster
kubeconfig and SSH access to the new bare-metal host):

```bash
HOST_IP=188.40.215.109   # IP of the new bare-metal box
POOL_NAME=runners-linux  # matches runnersFleetLinux.name in values

# 1. Generate a fresh bootstrap join token from a control-plane node
#    of the workload cluster. The KUBECONFIG path is the staging
#    workload cluster's kubeconfig (`kubeconfig: tuist-staging` in
#    1P, vault: tuist-k8s-staging).
JOIN_CMD=$(kubectl --kubeconfig "$STAGING_KUBECONFIG" \
  --namespace kube-system \
  exec -i $(kubectl --kubeconfig "$STAGING_KUBECONFIG" \
    --namespace kube-system get pods -l component=kube-apiserver \
    -o name | head -1) \
  -- kubeadm token create --print-join-command --ttl 1h)

# 2. Pull the shared SSH private key from 1P (terminal-only, never
#    to a permanent file)
op read "op://tuist-k8s-staging/HETZNER_BARE_METAL_SSH_KEY/private-key" \
  --account=tuist.1password.com > /tmp/hbm
chmod 600 /tmp/hbm

# 3. SSH in and run the join procedure
ssh -i /tmp/hbm -o StrictHostKeyChecking=no root@"$HOST_IP" "
  set -euo pipefail

  # Install containerd + kubeadm + kubelet matching the workload
  # cluster's k8s version. Adjust K8S_VERSION to track the value in
  # cluster-staging.yaml's spec.topology.version (currently v1.34.6).
  K8S_VERSION=v1.34
  curl -fsSL https://pkgs.k8s.io/core:/stable:/\${K8S_VERSION}/deb/Release.key | \
    gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo \"deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/\${K8S_VERSION}/deb/ /\" | \
    tee /etc/apt/sources.list.d/kubernetes.list

  apt-get update
  apt-get install -y containerd kubeadm kubelet
  systemctl enable --now containerd
  systemctl enable kubelet

  # Pre-pull the pause image to keep first-Pod start tight.
  containerd-config-default | tee /etc/containerd/config.toml
  systemctl restart containerd

  # Run the join command captured in step 1.
  $JOIN_CMD

  # Wait for the node to register, then apply runner-tier label +
  # taint. Without these, runner Pods don't schedule here and other
  # workloads might.
"

# 4. From the workstation, apply the pool label + tier taint
kubectl --kubeconfig "$STAGING_KUBECONFIG" \
  label node "<node-name>" \
  "node.cluster.x-k8s.io/pool=$POOL_NAME"

kubectl --kubeconfig "$STAGING_KUBECONFIG" \
  taint node "<node-name>" \
  "tuist.dev/runner-tier=bare-metal:NoSchedule"

# 5. Shred the local key
shred -u /tmp/hbm
```

The host now hosts runner Pods exclusively (the `bare-metal:NoSchedule`
taint repels everything that doesn't tolerate it; the runners-controller
podtemplate stamps the matching toleration on Linux Pods).

### Future: CAPI-managed bare metal (`caph` adoption)

For production scale-up the manual flow above is replaced by:

1. `HetznerBareMetalHost` CR per box, referencing the Robot
   webservice credentials in 1P (`tuist-k8s-staging/HETZNER_WEBSERVICE`).
2. `HetznerBareMetalMachineTemplate` referencing the host pool.
3. A `bare-metal-worker` MachineDeployment class added to the
   `tuist-hcloud` ClusterClass.
4. `installimage` cloud-init that runs `kubeadm join` automatically.

This is intentionally deferred — staging bring-up doesn't need
automated lifecycle management, and the CAPI integration is its own
focused piece of work once the substrate is proven.
