# Swift Registry Helm Chart

Deploys the standalone Tuist Swift package registry service to Kubernetes.

## Validation

```bash
helm lint infra/helm/swift-registry -f infra/helm/swift-registry/values-ci.yaml
helm template swift-registry infra/helm/swift-registry -f infra/helm/swift-registry/values-ci.yaml
```

## 1Password

Managed overlays expect External Secrets Operator to read a `SWIFT_REGISTRY` item from the cluster's `onepassword` ClusterSecretStore. The store is already scoped to the environment vault by cluster bootstrap.
