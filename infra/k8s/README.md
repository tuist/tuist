# Tuist Runners — Kubernetes control plane

Tuist Runners declare desired pool state through a `tuist.dev/v1
OrchardWorkerPool` custom resource. A Bonny operator inside the Tuist
Phoenix server watches these CRs and drives the fleet on Scaleway.

The operator process does not need to run inside the target cluster. Render
today, EKS tomorrow — as long as the server can reach the cluster's API.

## Local end-to-end flow (kind + stubs)

Fully local, no Scaleway calls, no bare-metal Mac.

```bash
# 1. Bring up a local kind cluster + install CRDs
mise run runner:k8s:up

# 2. Start the Tuist dev server with the operator connected to kind.
#    Dev config auto-stubs Scaleway + the SSH provisioner so the full
#    Bonny → Reconciler → Oban pipeline runs without leaving your machine.
export TUIST_KUBECONFIG_PATH=$HOME/.kube/config
export TUIST_BONNY_ENABLED=true
mise run dev

# 3. Apply an example pool CR (in a new terminal). `ACCOUNT_ID` is the
#    Tuist account id to attach the pool to -- use the seed user's id
#    for local dev (`tuistrocks@tuist.dev`).
mise run runner:k8s:apply-example -- 1 3

# 4. Watch reconciliation
kubectl get owp -o wide
kubectl describe owp dev-pool

# 5. Scale
kubectl patch owp dev-pool --type merge -p '{"spec":{"desiredSize":5}}'

# 6. Delete (drains the pool)
kubectl delete owp dev-pool

# 7. Tear down the cluster
mise run runner:k8s:down
```

The Tuist `/ops` dashboard (`http://localhost:8080/ops/orchard_workers`)
and `kubectl` show the same data — the CR is the control-plane interface,
Postgres is the materialised mirror, Bonny syncs status back into
`.status` on the CR.

## Remote cluster (staging / prod)

Once you want real Scaleway provisioning:

1. Stand up a managed k8s cluster (DOKS, Kapsule, any tiny cluster works —
   it only hosts CRs, not workloads).
2. Apply the CRD + RBAC:
   ```bash
   cd server && mix bonny.gen.manifest --out /tmp/bonny.yaml
   kubectl --context <remote-context> apply -f /tmp/bonny.yaml
   ```
3. Create a ServiceAccount + generate a kubeconfig for the Tuist server:
   ```bash
   kubectl --context <remote-context> -n tuist-runners \
     create token tuist-runners --duration=87600h  # 10 years; rotate via secret mgmt
   ```
4. Build a kubeconfig referencing that token and the cluster's public API
   endpoint. Store it as a Render secret.
5. In Render / runtime env:
   ```
   TUIST_KUBECONFIG_PATH=/etc/secrets/kubeconfig
   TUIST_BONNY_ENABLED=true
   TUIST_SCALEWAY_SECRET_KEY=...
   TUIST_SCALEWAY_PROJECT_ID=...
   ```
   Remove the dev-only stub config via runtime.exs — the default client
   modules (`Tuist.Scaleway.Client`, `Tuist.Runners.OrchardWorkerProvisioner`)
   hit real Scaleway + SSH.

The Tuist server pod (or Render container) is the sole operator replica
today. Scaling to multiple replicas works as soon as you turn on Bonny's
leader election (via k8s Lease, one config line).
