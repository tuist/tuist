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
