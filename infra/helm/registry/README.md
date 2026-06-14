# Swift Registry Helm Chart

Deploys the standalone Tuist Swift package registry service to Kubernetes.

## Validation

```bash
helm lint infra/helm/registry -f infra/helm/registry/values-ci.yaml
helm template registry infra/helm/registry -f infra/helm/registry/values-ci.yaml
```

## 1Password

Managed overlays expect External Secrets Operator to read a `REGISTRY` item from the cluster's `onepassword` ClusterSecretStore. The store is already scoped to the environment vault by cluster bootstrap.
