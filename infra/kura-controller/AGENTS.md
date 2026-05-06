# Kura Controller

This module contains the Kubernetes controller that reconciles Kura account endpoint custom resources.

## Scope

- API group: `kura.tuist.dev`
- Primary resource: `KuraInstance`
- Controller output: Kubernetes workload resources for one account-region Kura deployment.

## Development

- Run tests with `go test ./...` from this directory.
- Keep generated CRDs in `infra/helm/tuist/crds/` aligned with API changes.
- Keep the controller independent from the Scaleway Apple Silicon CAPI provider. Kura endpoint lifecycle is a product workload concern, not a macOS node infrastructure concern.

