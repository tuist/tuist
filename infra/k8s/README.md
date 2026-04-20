# Tuist Runners — Kubernetes control plane

The Tuist Runners fleet is managed through a `tuist.dev/v1 OrchardWorkerPool`
custom resource. An in-cluster operator pod watches these CRs and drives
the fleet on Scaleway via the Scaleway API + SSH.

## Deployment shape

```
 Render                         K8s cluster (tuist-runners namespace)
 ┌────────────────────┐         ┌─────────────────────────────────────┐
 │ Tuist Phoenix      │         │ CRDs + etcd                         │
 │  (TUIST_ROLE=web)  │◄───────►│  OrchardWorkerPool CRs              │
 │  ├── LiveViews     │ k8s API │                                     │
 │  ├── Postgres ─────┼─────────┼──► tuist-runners-operator Deployment│
 │  └── Oban :default │ (shared │     (TUIST_ROLE=operator)           │
 │                    │ Postgres│     ├── Tuist.Operator (Bonny)      │
 │ NO Scaleway creds  │  conn)  │     ├── Oban :runners queue         │
 │ NO SSH key         │         │     ├── Scaleway creds (Secret)     │
 └────────────────────┘         │     └── SSH key (Secret)            │
                                │                │                    │
                                │                │ HTTPS + SSH        │
                                │                ▼                    │
                                │      Scaleway bare-metal Macs       │
                                │                                     │
                                │ (+ future: Orchard controller as    │
                                │    a Deployment in the same NS)     │
                                └─────────────────────────────────────┘
```

**Why this split:**
- Scaleway + SSH credentials only exist in the cluster, never on Render.
- The operator runs next to the CRs it reconciles; no out-of-cluster kubeconfig to rotate.
- The web tier and the operator share Postgres via a managed connection string but are otherwise isolated.
- When Phoenix eventually moves into k8s, delete the `TUIST_ROLE=web` deployment on Render and run one in-cluster deployment with `TUIST_ROLE=all`. Operator code is untouched.

## Oban queues per role

| Role | Queues |
|---|---|
| `all` (default, Render today) | `default` + `runners` |
| `web` | `default` |
| `operator` | `runners` |

`ProvisionOrchardWorkerWorker`, `DeprovisionOrchardWorkerWorker`, and
`ReconcilePoolsWorker` all enqueue into `:runners` and therefore only
execute on pods that process that queue (today: `all`; tomorrow:
`operator` only).

## Local end-to-end flow (kind + stubs)

Fully local, no Scaleway calls, no bare-metal Mac. The Tuist dev server
plays both roles (`TUIST_ROLE=all` default) and targets the kind cluster
via a kubeconfig file.

```bash
# 1. Bring up a local kind cluster + install CRDs
mise run runner:k8s:up

# 2. Start the Tuist dev server with Bonny connected to kind.
#    Dev config auto-stubs Scaleway + the SSH provisioner.
export TUIST_KUBECONFIG_PATH=$HOME/.kube/config
export TUIST_BONNY_ENABLED=true
mise run dev

# 3. Apply an example pool CR (new terminal).
mise run runner:k8s:apply-example -- 1 3

# 4. Watch reconciliation
kubectl get owp -o wide
kubectl describe owp dev-pool

# 5. Scale
kubectl patch owp dev-pool --type merge -p '{"spec":{"desiredSize":5}}'

# 6. Delete (drains the pool)
kubectl delete owp dev-pool

# 7. Tear down
mise run runner:k8s:down
```

## Production / staging rollout

1. **Stand up the cluster.** Any tiny managed k8s works (DOKS, Kapsule,
   Hetzner, GKE autopilot). It only hosts CRs + the operator pod.

2. **Apply CRDs + RBAC.**
   ```bash
   cd server && mix bonny.gen.manifest --out /tmp/bonny.yaml
   kubectl apply -f /tmp/bonny.yaml
   ```
   This creates the `OrchardWorkerPool` CRD, the `tuist-runners`
   ServiceAccount, and the operator's RBAC bindings.

3. **Create secrets** in the `tuist-runners` namespace:
   ```bash
   kubectl -n tuist-runners create secret generic tuist-runners-database \
     --from-literal=DATABASE_URL="postgres://..."

   kubectl -n tuist-runners create secret generic tuist-runners-scaleway \
     --from-literal=TUIST_SCALEWAY_SECRET_KEY="..." \
     --from-literal=TUIST_SCALEWAY_PROJECT_ID="..."

   kubectl -n tuist-runners create secret generic tuist-runners-ssh \
     --from-file=id_ed25519=/path/to/runners.key
   ```
   The SSH key's public half must be uploaded to the Scaleway account so
   new Macs inject it automatically.

4. **Deploy the operator pod.**
   ```bash
   kubectl apply -f infra/k8s/operator-deployment.yaml
   kubectl -n tuist-runners rollout status deploy/tuist-runners-operator
   ```
   The pod reads the in-cluster service account, connects to the k8s API,
   and starts watching `OrchardWorkerPool` CRs.

5. **Reconfigure Render** to run `TUIST_ROLE=web` so the Render pods stop
   processing the `:runners` queue and don't need Scaleway/SSH creds. Drop
   those env vars from Render.

6. **Apply a pool CR** or have customers use the dashboard scale UI. Both
   paths converge through the same reconciler.

Run multiple operator pods by bumping `replicas` in the deployment —
Bonny's leader election via k8s Lease kicks in automatically, so only one
replica reconciles at a time. The others are standbys for instant
failover.
