# Runner payload

The scripts and binaries macOS runner VMs install at boot instead of carrying
them in the runner image, so changing them releases a small OCI artifact
rather than rebuilding every Xcode image.

## Contents

`build.sh` assembles `runner-payload.tar.gz`. Archive paths are guest paths:

- `opt/tuist/`: `dispatch-poll.sh`, `metrics-poll.sh`, `runner-shell-agent`,
  `tuist-gitlab-runner`, `tuist-cas-proxy`, `buildkite-agent`,
  `buildkite-hooks/`
- `usr/local/bin/tuist-cache-volume`
- `VERSION` and `REQUIRES_IMAGE_INTERFACE`

Sources stay where they are (`infra/runner-image`, `infra/linux-runner-image`,
`cas-plugin`); binaries come from `.github/actions/build-runner-image-binaries`.
The buildkite agent version and checksum live in `buildkite-agent.env`.

## Release and rollout

- Component `runner-payload@<semver>` (`mise/tasks/release/components.json`).
  `cas-plugin` is not an include path, so a CAS change ships with the next
  payload release.
- `server-production-deployment.yml` builds it on a Tuist macOS runner and
  pushes `ghcr.io/tuist/tuist-runner-payload:<semver>` with layer media type
  `application/vnd.tuist.runner-payload.v1.tar+gzip`.
- `server-deployment.yml` resolves the version to a digest with an anonymous
  token (`.github/scripts/ghcr-manifest-digest.sh`) and sets
  `runnersFleet.runnerPayload`. The package must be public: hosts pull it
  without credentials, and a version that cannot be resolved fails the deploy.
- The chart stamps `tuist.dev/runner-payload` on macOS RunnerPools; the
  runners-controller copies it onto Pods and recycles idle Pods whose payload
  differs, and the server drains them like a stale image.

## Boot

tart-kubelet fetches the pinned digest, verifies the manifest and layer
digests, unpacks it under `/var/lib/tart-userdata/.runner-payloads/<digest>`
and shares it read-only as `payload`. A Pod that pins a payload never boots
without it. In the guest, `install-payload.sh` copies it over the image's
files before `inject-env.sh` runs, and halts the VM if the install fails.

## Image interface

A payload ships hours before the image built from the same commit. The image
bakes `infra/runner-image/payload-interface` as `/opt/tuist/payload-interface`
and the payload records the same file as `REQUIRES_IMAGE_INTERFACE`. An image
whose interface is lower than the payload's keeps its own copies. A change that
touches payload sources and image-owned runner-image files must bump it;
`check-interface.sh` enforces that on pull requests. Payloads must keep working
on newer images.

## Rollback

Dispatch `server-deployment.yml` with `runner_payload_version` set to an
earlier release. This builds nothing, so it works when the payload itself
breaks macOS runners.
