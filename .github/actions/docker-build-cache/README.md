# Docker build cache

Use a private Tuist cache volume for BuildKit's exported OCI layer cache. A warm
build imports local blobs instead of downloading the registry cache. A cold build
imports the existing registry cache. Both local and registry caches are exported
with `mode=max`, so the registry fallback stays current.

This is a layer-cache read-path optimization, not a persistent Docker daemon:

- It does not share the runner's test `_build` with the production Docker build.
- It does not preserve `RUN --mount=type=cache` contents or a live BuildKit database.
- Existing registry writes and image pushes still happen. Local export and volume
  publication add work, so a net wall-time improvement must be measured, not assumed.
- The volume client owns cold fallback, private clones, writer authorization and
  publication after a successful job. Concurrent jobs do not write the same directory.
- The action is for the `docker-container` Buildx driver used by deployments. It
  does not change the CI smoke build's `docker` driver or its registry mirror.

## Usage

```yaml
- id: image-cache
  uses: ./.github/actions/docker-build-cache
  with:
    key: server-image-buildkit-prod-v1
    registry-cache: ghcr.io/tuist/tuist-buildcache:server
- uses: docker/setup-buildx-action@v3
- uses: docker/build-push-action@v6
  with:
    context: .
    file: server/Dockerfile
    cache-from: ${{ steps.image-cache.outputs.cache-from }}
    cache-to: ${{ steps.image-cache.outputs.cache-to }}
- name: Retain the latest layer cache
  env:
    TUIST_DOCKER_CACHE_DIRECTORY: ${{ steps.image-cache.outputs.directory }}
  run: bash .github/actions/docker-build-cache/commit.sh
```

Call `commit.sh` only after a successful build. The exporter writes into `next`,
then the script rotates it into `current`, without replacing the mounted root.
This removes old unreferenced blobs rather than letting an in-place OCI cache grow
indefinitely. If the optional local export fails without producing an index, the
script retains the previous cache. A failed job cannot publish its private clone.

Use the same stable key for the same image/configuration across workflows. Use a
separate key for a different hosted mode, platform or image. Never retain Docker
login credentials in this directory.

## Validation

```sh
bash .github/actions/docker-build-cache/test.sh
```

The shell tests cover source selection, output formatting, paths containing
spaces, incomplete export cleanup, cache rotation and symlink/input rejection.
They do not test a Docker build or prove cache-volume persistence.

The `Docker Build Cache` workflow also runs `integration_test.sh` on a Linux
runner. Four independent BuildKit workers exercise cold export, warm local
import, changed-input invalidation and registry fallback against a temporary
private registry. The fixture checks both cached layers and resulting files.
It does not deploy anything, use registry credentials or establish cross-job
snapshot publication.

For deployed validation, first let an eligible successful job export and publish
the volume. On a later fresh runner, verify that preparation selects the local
source, BuildKit reports expected layers as cached, the build and smoke checks
pass, and the updated volume publishes. Compare equivalent builds with registry
and local imports, excluding runner queue time and including local export and
volume publication overhead. Keep the per-commit runtime package refresh enabled.
