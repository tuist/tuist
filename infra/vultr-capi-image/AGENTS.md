# Vultr CAPI Image

Builds and tracks the Vultr snapshot used by CAPVULTR workload nodes.

## Ownership

- The Vultr API token is a secret and stays in 1Password.
- The Vultr snapshot ID is an infrastructure artifact reference and belongs in Git at `infra/k8s/clusters/vultr/images.yaml`.
- Keep the Kubernetes version here aligned with the Vultr regional CAPI templates under `infra/k8s/clusters/vultr/`.

## Workflow

Use `build.sh` to build a Cluster API-compatible Vultr snapshot with upstream Kubernetes image-builder. After the build, commit the new `snapshotID` in `infra/k8s/clusters/vultr/images.yaml`.
