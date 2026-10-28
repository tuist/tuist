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
unchanged. Pin explicit pool images by digest as well; readiness checks require
immutable references.

After Helm preflight and KVM preparation, `linux-runner-image-prepare.sh` reads
the same rendered pools that Helm will install. That render is the desired-image
announcement, including explicit pools, fleets, and runtime classes. This avoids
another writer sharing the macOS `tuist-upcoming-runner-images` ConfigMap, and
also covers manual pins and rollback releases without relying on a prior release
announcement. Pulling starts during deployment, rather than immediately on
publication; normal jobs continue using the existing pools during preparation.

One temporary DaemonSet per unique namespace/fleet/preparation-runtime/image starts only
`/bin/sleep`, with no dispatch token, host mounts, or job registration. Managed
`kata-qemu` pools use a native preparation pod: Kata and the default runtime
share containerd's default overlayfs snapshotter, so the native pull populates
the same image store without reserving the RuntimeClass's 2560 MiB VM overhead.
Unknown runtime classes retain their own handler because their snapshotter may
differ. Keep this mapping in sync if the managed Kata snapshotter changes.
It selects Linux amd64 nodes in that fleet and tolerates the runner-tier and
temporary pool-reservation taints. It uses the default priority, with no priority
elevation over runner jobs. A completely full host can still wait for its small
CPU and memory request to fit.

The gate checks readiness once, without waiting or polling. It requires a
running container for the exact image, runtime and DaemonSet UID on every Ready,
schedulable host. Pools whose target is still preparing retain their own current
image through a deployment-only `runnersFleetLinux.imageHolds` values overlay.
Other pool settings and the rest of the deployment proceed normally. A later
deployment recomputes the holds and promotes ready targets; the background
DaemonSet never patches pools itself. First installations and fleets with no
Ready, schedulable hosts proceed without a hold. Returning or newly added nodes
can still require a pull.

Like macOS, a target staged for an hour proceeds even if preparation is incomplete.
The allowance starts at the helper DaemonSet's creation timestamp; repeated
deployments do not reset it. Kubernetes read/write errors produce a warning and
proceed with the requested images. These fallbacks can cause cold pulls, but
image preparation cannot delay the deployment with its own waiting loop. The
existing 125-minute job and 70-minute Helm-step ceilings remain unchanged.

Helpers survive deployment completion and cancellation so pulls continue in
the background. They are scoped by a hash of the Helm release namespace/name
in `tuist.dev/linux-image-staging-owner`. A subsequent deployment removes that
release's obsolete helpers once pools have moved or a target is superseded.
Keeping the active helper through Helm completion also preserves the staging
timestamp and readiness evidence if Helm fails or rolls back. Cleanup failures
warn without discarding the readiness decision. Uninstalling the release does
not delete these out-of-Helm helpers: inspect the owner label and remove only
that release's `tuist-linux-prepull-*` DaemonSets. After cleanup the images remain
in kubelet's ordinary cache and are eligible for normal image garbage collection.

Rollback uses the same digest resolution and readiness policy and generally
reuses the old cached image. To revert the feature, remove the preparation call
and image-hold overlay and clean up its scoped helpers; digest pinning and the
registry cache can remain. No schema or stored-data migration is involved.

## Validation

The normal production cascade deploys canary, then requires Runners Acceptance
to pass before promotion. Each Linux target runs a native job and an actual
Docker job container. Native coverage includes non-root/KVM access, executable
clients and hooks, Android SDK contents and write access, Docker, Go compilation,
setup-beam, Kura's authenticated round trip, and process file limits.
The container probe checks workspace/actions/externals mounts,
checkout, the forwarded cache endpoint, and environment-file round trips.
The gate rejects missing, skipped, or failed Linux probes, and the dispatch
watchdog bounds pickup for both jobs. The hourly production run uses the same
coverage. The existing hotfix path bypasses this normal acceptance gate.
Acceptance exercises the image actually selected for the pool; if staging holds
the previous image, that run does not validate the pending image. Validate it
after a later deployment promotes it or use the candidate staging smoke workflow.

`bash .github/scripts/linux-runner-image-prepare.test.sh` exercises readiness,
immediate holds, later promotion, one-hour expiry, failure, release-scoped cleanup,
duplicate pools, runtime selection, and first installation using a fake kubectl.
`bash infra/mise/tasks/helm/linux-image-staging.sh` verifies independent image
holds for explicit and shape pools in all managed environments, preserving every
other pool field and macOS images. Helm CI also tests the adjacent KVM gate.

Linux image PR and manual validation builds export a baseline OCI image and `mode=max` cache. Then
`verify-layer-reuse.sh` changes only `dispatch-poll.sh`, creates a fresh BuildKit
builder, imports that exported cache, and builds again. `compare-layers.mjs`
compares compressed layer digests and sizes, requiring a nonempty delta of at
most 10 MiB. This checks reuse across builders, not merely a warm daemon or
unchanged file contents. Its comparator tests include a rebuilt 1.4 GB SDK blob
with unchanged size. Run it locally after equivalent exports:

```sh
bash infra/linux-runner-image/verify-layer-reuse.sh /tmp/baseline.tar /tmp/build-cache
```

Before production promotion, exercise the gate in staging with a real image:
confirm an immediate hold, a retained background helper, promotion on a later
check, and scoped cleanup after pools no longer need that target.
The first release changes layer boundaries
and base pins and can be a large pull. Measure subsequent script-only releases;
the optimization does not promise small pulls for deliberate toolchain updates.

## Release benchmark

The Linux Runner Image workflow's manual `benchmark` mode compares a supplied
`benchmark_base` commit with the dispatched revision. It builds the base twice
using fresh builders without imported caches (the previous production release
configuration), then builds the candidate twice, exporting/importing an isolated
GHCR `mode=max` cache. The second build in each arm appends the same comment to
`dispatch-poll.sh`. Image and cache tags include the workflow run ID and attempt;
the benchmark never writes `latest`, semver tags, or the production build cache.

It records build/export wall time, compressed layer sizes and reuse, then runs
three pull samples per arm. Each sample gets its own disposable Docker daemon
and storage volume, pulls the seed image, and times the update including
unpacking. Arm order alternates between samples. This measures update pulls
with the prior release cached, without pruning or changing the host's image
store. Docker pull timings are an isolated registry/unpack measurement, not a
measurement of production kubelet, Kata boot, or job queue latency.

The artifact retains source revisions, Docker/Buildx versions, manifests,
per-build/pull logs, raw timings, and `results.json`. It uploads partial evidence
on failure too. Build timings include image push and (for the candidate) cache
export; they exclude builder bootstrap. Cold seed costs and update costs are
reported separately. Keep the PR draft while running either manual mode.
