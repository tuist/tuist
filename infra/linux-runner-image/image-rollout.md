# Linux runner image releases

The production release job in `server-production-deployment.yml` imports and
exports `ghcr.io/tuist/tuist-linux-runner:buildcache` with BuildKit's `mode=max`.
This retains the Android SDK and Go builder stages across ephemeral builders.
Only the serialized main release writes this tag. PR and manual builds can read
it, but export their cache to their existing GHA scope. The first release seeds
the registry cache; it cannot reuse layers that previous releases never saved.

The release job previously had no cache at all. GHA caching was configured only
in the PR/manual workflow. On 2026-10-27 the GitHub cache usage API reported
107,835,444,278 bytes for this repository, and Linux build-cache indexes belonged
to PR and branch refs. This establishes the missing release cache; it does not
establish historical eviction or a 10 GB repository limit.

Ubuntu and Temurin are digest-pinned. Renovate routes their updates through the
Linux image release component. apt, Docker/CLI tools, and the Android SDK precede
the runner tarball, compiled clients, and scripts. `RUNNER_VERSION` is declared
immediately before its download, so bumping it does not invalidate earlier RUN
instructions. The SDK uses `COPY --link` to preserve its blob when unrelated
tooling changes. Script modes are set by COPY rather than a later chmod that
would copy binaries into a changed layer.

SDK discovery still installs every stable platform/build-tools version above
the configured floor, without NDKs. Discovery happens when its builder stage
is invalidated, including a Temurin digest update; a script-only release now
intentionally reuses the SDK. To force a toolchain refresh without changing
inputs, rebuild with `--no-cache-filter android-sdk,runner`.
Prefer a reviewed base digest update so normal releases also
invalidate the cache consistently.

## Pool promotion

The deploy resolves the selected semver or explicit `linux_runner_image_tag`
through `ghcr-manifest-digest.sh`, and passes the digest reference to
`runnersFleetLinux.shapeRunnerImage`. Explicit pools inherit it unless they have
their own image pin. Re-tagging the identical manifest leaves the pool image
unchanged. Pin explicit pool images by digest as well; the preparation gate
rejects mutable references.

After Helm preflight and KVM preparation, `linux-runner-image-prepare.sh` reads
the same rendered pools that Helm will install. That render is the desired-image
announcement, including explicit pools, fleets, and runtime classes. This avoids
another writer sharing the macOS `tuist-upcoming-runner-images` ConfigMap, and
also covers manual pins and rollback releases without relying on a prior release
announcement. Pulling starts during deployment, rather than immediately on
publication; normal jobs continue using the existing pools during preparation.

One temporary DaemonSet per unique namespace/fleet/runtime/image starts only
`/bin/sleep`, with no dispatch token, host mounts, or job registration. It uses
the pool's runtime class to exercise the same image store and unpacking path.
It selects Linux amd64 nodes in that fleet and tolerates the runner-tier and
temporary pool-reservation taints. It uses the default priority, with no priority
elevation over runner jobs. Kata pods
incur the configured VM overhead; a completely full host may wait for a slot.

The gate re-reads nodes and pods until every Ready, schedulable host has a
running container for the exact image, runtime and DaemonSet UID. New hosts
appearing during the wait join the gate. An existing fleet with no usable hosts
fails; a fleet with no nodes yet follows the normal first-install path. Unready
and cordoned nodes do not hold a deployment indefinitely. They, and nodes added
after the gate, can still need a pull when they return to service.

The default deadline is ten minutes across all targets. A timeout or Kubernetes
read/write error fails before Helm switches pools. KVM preparation may already
have applied additive prerequisites. DaemonSets are deleted on success, failure,
and ordinary cancellation; no idle VM remains per host. A hard kill can leave a
`tuist-linux-prepull-*` DaemonSet behind: inspect its image and owner before
deleting that specific object. The images remain in kubelet's ordinary cache;
this is a preparation barrier, not a permanent pin against future image GC.

Retry after correcting registry, runtime or capacity problems. Rollback uses
the same digest resolution and gate and generally reuses the old cached image.
There is no fail-open timeout that silently switches pools onto a cold image.
To revert the feature, revert the deployment gate and digest wiring together;
no schema or stored-data migration is involved. The registry cache can remain.

## Validation

`bash .github/scripts/linux-runner-image-prepare.test.sh` exercises readiness,
failure, cleanup, duplicate pools, runtime selection, and first installation
using a fake kubectl. The Helm CI suite also renders all managed environments
and tests the adjacent KVM gate.

Linux image PR builds export a baseline OCI image and `mode=max` cache. Then
`verify-layer-reuse.sh` changes only `dispatch-poll.sh`, creates a fresh BuildKit
builder, imports that exported cache, and builds again. `compare-layers.mjs`
compares compressed layer digests and sizes, requiring a nonempty delta of at
most 10 MiB. This checks reuse across builders, not merely a warm daemon or
unchanged file contents. Its comparator tests include a rebuilt 1.4 GB SDK blob
with unchanged size. Run it locally after equivalent exports:

```sh
bash infra/linux-runner-image/verify-layer-reuse.sh /tmp/baseline.tar /tmp/build-cache
```

Before production promotion, exercise the gate in staging with a real image and
confirm temporary pods disappear. The first release changes layer boundaries
and base pins and can be a large pull. Measure subsequent script-only releases;
the optimization does not promise small pulls for deliberate toolchain updates.
