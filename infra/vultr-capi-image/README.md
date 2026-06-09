# Vultr CAPI Image

This directory owns the build recipe for the Vultr snapshot used by
CAPVULTR regional Kura clusters.

The pattern mirrors the macOS runner images:

- credentials live in 1Password
- the image recipe lives in Git
- the selected deployable artifact reference lives in Git

For Vultr, the deployable artifact reference is the snapshot ID in
[`../k8s/clusters/vultr/images.yaml`](../k8s/clusters/vultr/images.yaml).

## Build

```bash
export VULTR_API_KEY="$(op item get vultr-tuist-workloads --vault Founders --fields password --reveal)"
infra/vultr-capi-image/build.sh
```

The script uses upstream Kubernetes image-builder's Vultr target:

```bash
make deps-vultr
make build-vultr-ubuntu-2204
```

It prints recent Vultr snapshots matching the configured Kubernetes
version and Ubuntu version. Pick the new snapshot ID and commit it to
`infra/k8s/clusters/vultr/images.yaml`.

CI:

```bash
gh workflow run vultr-capi-image.yml
```

The workflow reads the Vultr API token from the `vultr-tuist-workloads`
1Password item in the `Founders` vault and prints the matching snapshots.
It does not commit the snapshot ID automatically.

## Rollout

1. Build a new snapshot.
2. Update `snapshotID` in `infra/k8s/clusters/vultr/images.yaml`.
3. Commit with `feat(kura): ...` or `fix(kura): ...`.
4. Merge. The mgmt-cluster apply workflow renders Vultr regional CAPI
   templates from the committed snapshot ID.

Do not store the snapshot ID in 1Password. It is not a secret.
