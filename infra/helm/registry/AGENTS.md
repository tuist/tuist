# Swift Registry Helm Chart

This chart deploys the standalone Swift package registry service to the managed Kubernetes clusters.

## Deployment Shape
- The chart is deployed independently from the main `tuist` chart.
- The registry API is served at the ingress root, for example `https://registry.tuist.dev`.
- S3 remains the durable source of truth for registry artifacts and metadata.
- PVCs are used for local SQLite state and local artifact cache.

## Secrets
- Managed environments should use `runtimeSecrets.externalSecret.enabled: true`.
- The `onepassword` ClusterSecretStore is scoped to the environment vault by cluster bootstrap.
- Prefer a dedicated 1Password item named `REGISTRY` with fields matching `runtimeSecrets.externalSecret.fields`.
