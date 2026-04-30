# Tuist Platform Helm Chart

Platform-level Helm umbrella chart installed **once per Kubernetes cluster** that hosts the Tuist-managed deployment. It bundles the infrastructure that our per-app chart (`infra/helm/tuist/`) assumes is already running.

## What's in it

| Component | Purpose |
|---|---|
| `cert-manager` | TLS certificate issuance via Let's Encrypt + Cloudflare DNS-01 |
| `ingress-nginx` | Ingress controller backed by a cloud LoadBalancer |
| `external-dns` | Sync Ingress / Service hostnames into Cloudflare DNS |
| `external-secrets` | Pull secrets from external stores (1Password, SOPS, etc.) into the cluster |
| `keda` | Event-driven pod autoscaler (used by the processor Deployment to scale on Oban queue depth) |
| `cluster-autoscaler` | Cluster API node-group autoscaler (off by default — see "Cluster autoscaler" below) |
| `ClusterIssuer` | Shared Let's Encrypt issuer wired to Cloudflare DNS-01 |

## Bootstrap

```bash
# 1. Create the target namespace.
kubectl create namespace platform

# 2. Create the Cloudflare API token Secret out-of-band. The token must have
#    Zone.DNS:Edit scope on the managed zone(s). Never commit this value.
kubectl -n platform create secret generic cloudflare-api-token \
  --from-literal=api-token="$CLOUDFLARE_API_TOKEN"

# 3. Fetch chart dependencies.
helm dependency update infra/helm/platform

# 4. Install the platform with the right provider overlay.
helm upgrade --install platform infra/helm/platform \
  -n platform \
  -f infra/helm/platform/values-hetzner.yaml
```

Other clouds can plug in by adding a `values-<provider>.yaml` overlay that
sets the provider-specific LoadBalancer annotations + any LB-specific
ingress-nginx config.

## Local validation

```bash
helm dependency update infra/helm/platform
helm template platform infra/helm/platform | kubectl apply --dry-run=client -f -
helm lint infra/helm/platform
```

## Cluster autoscaler

`cluster-autoscaler` is wired in via the `clusterapi` provider so it can grow / shrink the workload cluster's `MachineDeployments` based on Pending Pods. It pairs with the processor Deployment's KEDA `ScaledObject` (in `infra/helm/tuist/`): KEDA scales replicas on Oban queue depth, the new replicas go Pending under `DoNotSchedule` topology spread, and CA reacts by adding nodes to the `md-processor` pool up to its annotation-declared max-size.

It's **disabled by default** because it has bootstrap prereqs that aren't reproducible from this chart alone. To enable it for an environment, follow the runbook in [`infra/k8s/syself-onboarding.md`](../../k8s/syself-onboarding.md) under "Cluster autoscaler bootstrap" — TL;DR:

1. Apply [`infra/k8s/syself/processor-autoscaler-mgmt-rbac.yaml`](../../k8s/syself/processor-autoscaler-mgmt-rbac.yaml) on the Syself **management** cluster (requires Syself OIDC permission to create SA / Role / RoleBinding in `org-tuist`).
2. Extract the SA's token, package it as a kubeconfig, and create the `cluster-autoscaler-mgmt-kubeconfig` Secret in the workload cluster's `platform` namespace.
3. Re-run `helm upgrade platform ... --set cluster-autoscaler.enabled=true`.

## Notes

- The ingress-nginx LoadBalancer is annotated for Hetzner Cloud (Nuremberg region) by default. Adjust `ingress-nginx.controller.service.annotations` when the cluster lands on a different provider.
- external-dns is scoped by `txtOwnerId: tuist-platform` — one cluster, one TXT prefix. Run it with `policy: sync` only if you're happy with it deleting DNS records that aren't tracked by any Ingress.
- cert-manager CRDs are installed by the subchart (`installCRDs: true`). If another tool manages them, turn that off.
- KEDA and `cluster-autoscaler` are declared as chart dependencies but are independent: KEDA is on by default; cluster-autoscaler is off and requires the management-cluster bootstrap above before flipping on.
