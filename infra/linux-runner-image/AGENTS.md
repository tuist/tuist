# Linux Runner Image

OCI image hosted on the **Linux runner fleet** (Hetzner Cloud
nodes selected via `tuist.dev/fleet=<runnersFleetLinuxName>`). One
ephemeral GitHub Actions runner per Pod, one job per runner. The
same image runs in two roles within a Pod (see "Credential split"
below): a `poller` init container and a `runner` main container.

This is the Linux analog of `infra/runner-image/` (the Tart-based
macOS image). Same single-shot lifecycle, much simpler substrate.

## What's in the image

- `/home/runner/actions-runner/` — GitHub Actions runner binary
  (no registration baked in; we register at runtime via the JIT
  config minted by `Tuist.Runners.dispatch_for_sa/2`).
- `/usr/local/bin/dispatch-poll.sh` — the poll loop, run by the
  `poller` container. POSTs to the dispatch endpoint with the
  projected SA token as Bearer; on 204 it sleeps; on a claim it
  writes the minted JIT to the shared `tuist-runner-jit` volume
  (`TUIST_RUNNER_JIT_OUTPUT_PATH`) and exits 0 for the runner
  container to consume. (If that env is unset it `exec`s `./run.sh`
  in place — a rollout bridge for a controller still mid-upgrade;
  see `infra/runners-controller/AGENTS.md`.)
- `/usr/local/bin/run-job.sh` — the `runner` container's
  entrypoint in the split shape. Reads the JIT the poller staged
  (`TUIST_RUNNER_JIT_PATH`) and `exec`s
  `./run.sh --jitconfig <jit> --disableupdate`, or exits 0 if no
  JIT was staged (410 drain / poller abort). Holds no SA token.
- `/usr/local/bin/vitals.sh` — periodic resource-vitals emitter.
  `run-job.sh` backgrounds it just before exec'ing the runner (the
  dispatch-poll rollout-bridge path does too), so it samples for the
  job's lifetime and its last line lands in the Pod logs -> Loki even
  after the microVM is reaped. Tag `RUNNER_VITALS`; fields cover
  guest-wide memory (`/proc/meminfo`), cgroup memory
  (current/peak/max, `oom_kill`), guest CPU-busy% (`/proc/stat`
  deltas), loadavg, and a best-effort `/dev/kmsg` OOM watcher. PSI
  (`/proc/pressure/*`) avg10 fields are appended only when the guest
  exposes them — the runners-controller sets `psi=1` on the kata
  guest cmdline via a pod annotation, since the kata kernel boots
  with PSI off. The forensic trail for a runner that dies mid-job
  (guest OOM vs CPU/memory starvation), which is otherwise invisible
  from outside the guest. Interval via
  `TUIST_RUNNER_VITALS_INTERVAL` (default 3s).
- `/usr/local/bin/metrics-sampler.sh` — machine-metrics sampler for
  the job detail page's Metrics tab. Unlike `vitals.sh` (which logs to
  stdout from the runner container), this POSTs structured
  CPU/memory/network/disk samples to the server, so it runs in the
  dedicated `metrics` native-sidecar container that holds the dispatch
  SA token (the runner container never sees it). It waits for the
  poller to stage the JIT (a claimed job) before sampling — so
  warm-standby Pods don't post — then samples VM-wide `/proc` plus the
  JIT volume's backing filesystem every `TUIST_RUNNER_METRICS_INTERVAL`
  (default 15s) and POSTs to `…/pods/<pod>/metrics`. Best-effort;
  never affects the job. Format byte counters with awk's `%.0f` and
  compute counter deltas in bash: `awk` here is mawk, whose
  `printf "%d"` saturates at INT_MAX and whose bare `print` renders
  integers above 2^31 in `%.6g` scientific notation. Read `MemTotal`
  and `MemAvailable` in the same pass — kata hot-plugs the sandbox up
  to the shape's memory after boot, so a total cached at sidecar
  start goes stale mid-job. `metrics-sampler_test.sh` covers both.
- `/usr/local/bin/runner-shell-agent` — interactive shell bridge.
  Built from the Go source in `cmd/runner-shell-agent/`. The trusted
  `shell` native sidecar waits for the poller to stage a JIT (claimed
  job), polls the server for authorized shell sessions, and owns the
  server WebSocket tunnel with the dispatch token mounted only there.
  The runner container starts the same binary in PTY-server mode on a
  shared Unix socket under the work volume, so the user-facing shell is
  spawned inside the runner container and sees the job filesystem,
  environment, and Docker socket rather than the sidecar environment.
- `docker-ce-cli`, `docker-buildx-plugin`, `docker-compose-plugin`
  from the official Docker apt repo — client side only. The
  daemon runs in the `dind` native sidecar (`docker:dind`)
  attached to the same Pod by the runners-controller. The
  runner's `docker` group is pinned to GID 123 to match the
  socket GID dockerd creates in the sidecar.
- `/usr/local/lib/android/sdk` — Android SDK, with `ANDROID_HOME`
  and `ANDROID_SDK_ROOT` exported. Same path and same
  bake-it-into-the-image posture as GitHub's hosted Ubuntu image,
  because Gradle cannot even configure an Android project without
  a platform + build-tools ("SDK location not found"). Platforms
  and build-tools are selected by a version FLOOR
  (`ANDROID_PLATFORM_MIN_VERSION` / `ANDROID_BUILD_TOOLS_MIN_VERSION`
  build-args), not pinned: this image runs customer workflows, so
  it cannot assume anyone's `compileSdk`. Everything Google
  publishes at or above the floor is installed, which means new
  platforms roll in on the next image rebuild with no version bump
  anywhere — the same approach the hosted image takes with
  `platform_min_version` / `build_tools_min_version`. Do NOT
  re-pin these to whatever `android/` happens to target; that
  breaks any customer on a newer platform.
  No NDK is installed, and that is a standing decision rather than
  a gap to close. It is the bulk of the hosted image's Android
  footprint (three majors, roughly 10GB expanded) and only
  native-code builds need it — a pure Kotlin/Java app never
  touches it. Heavy toolchains that serve a minority of jobs
  belong in per-account cache volumes, not in an image every job
  on the fleet pulls. Note that those are macOS-only today
  (`runnerCacheVolume` provisions APFS volumes on Mac minis via
  tart-kubelet); until the Linux fleet has an equivalent, a
  workflow that needs the NDK installs it per job with
  `$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager ndk;<version>`,
  which works because cmdline-tools ships here and the licenses are
  already accepted.
  `ANDROID_NDK_HOME` and its siblings are deliberately left unset.
  The hosted image sets them, and customer builds do read them, but
  a variable pointing at an NDK that is not installed fails deep
  inside CMake instead of failing fast.
  Resolved in the `android-sdk` builder stage (sdkmanager needs a
  JVM) so no JDK lands in the final image — workflow steps get
  theirs from mise.

No `inject-env.sh`, no launchd plist, no VM-halt trap — kubelet
projects env + SA token natively, container exit IS the
substrate's terminal signal.

## Credential split (token isolation)

A Linux runner Pod runs untrusted workflow code (incl. fork PRs),
so the container that runs it must never see the dispatch SA
token — that token is pool-scoped and could claim other tenants'
queued jobs. The controller's `podtemplate.Build` splits the Pod:

- **`poller` init container** — the only container that mounts the
  token. Runs `dispatch-poll.sh` in poller mode; on a claim it
  writes the minted, job-scoped JIT to a shared `tuist-runner-jit`
  emptyDir and exits 0. Runs as root so it can write that
  root-owned emptyDir (it executes only our poll script, never
  customer code).
- **`runner` main container** — no token. kubelet starts it only
  after the poller init container exits, so by then the JIT (if
  any) is already staged. Runs `run-job.sh`, which reads the JIT
  and `exec`s the runner. A leaked JIT post-claim grants nothing
  the runner isn't already running under.

A warm-standby Pod therefore sits in `Pending` (poller polling in
Init) until a job is claimed, not `Running`. macOS keeps the
single-container shape — the Tart VM is the isolation boundary and
tart-kubelet projects the token into it. See
`infra/runners-controller/AGENTS.md` for the full Pod shape.

## docker

dockerd does NOT run in this image. It runs in a sidecar; the
runner reaches it via `DOCKER_HOST=unix:///var/run/docker.sock`
injected by the controller, with the socket mounted from a
shared emptyDir. See `infra/runners-controller/AGENTS.md` for
the sidecar Pod shape + lifecycle.

`/home/runner/actions-runner/externals/` (the node runtimes the
actions-runner tarball ships) is copied out of this image into a
volume the sidecar mounts at the same path, because the runner
bind-mounts it into `container:` job containers as `/__e` and
dockerd resolves that path on its own side. Moving the runner
root, or trimming externals from the image, breaks job containers
— see "Why stage externals" in the controller doc.

## Build

```bash
cd infra/linux-runner-image
docker build --pull -t ghcr.io/tuist/tuist-linux-runner:dev .
```

`RUNNER_VERSION` is a `--build-arg` (default lives in the
Dockerfile). Renovate keeps it bumped to the latest
`actions/runner` release; the value flows into `helm` via the
release-pipeline digest rewrite, same shape as the macOS image.

## CI

The release pipeline mirrors `release-runner-image` for macOS but
runs on a standard cloud Linux runner (no Tart / GUI session
needed). Steady-state: `feat(linux-runner-image)` /
`fix(linux-runner-image)` conventional commits on `main` trigger
a `release-linux-runner-image` job that builds, pushes
`ghcr.io/tuist/tuist-linux-runner:<semver>` + `:latest`, takes the
digest from the build-push-action's own output, and rewrites
`runnersFleetLinux.pools[*].runnerImage` across managed-env
values files (those whose pin is already non-empty — canary /
production stay empty until the env is flipped on). Ad-hoc
rebuilds for branch validation go through
`.github/workflows/linux-runner-image.yml`: `pull_request` builds
without pushing, `workflow_dispatch` pushes `:sha-<git-sha>` only
(`:latest` and semver tags belong exclusively to the release
flow).

`pull_request` also syntax-checks every shell script and runs
`metrics-sampler_test.sh` inside `ubuntu:22.04` — the image's own
base, so the sampler's byte formatting is exercised against mawk
rather than whichever awk the CI runner happens to ship.

## How it ends up serving traffic

1. `runnersFleetLinux.pools[].runnerImage` (helm value) is
   digest-pinned to a built image.
2. The runners-controller's `RunnerPoolReconciler` creates a Pod
   with this image; kubelet on the Hetzner Cloud node pulls the
   OCI image (cached on subsequent Pods scheduled to the same
   host) and starts the containers.
3. The `poller` init container runs `dispatch-poll.sh`, exchanging
   the projected SA token for a JIT config (200 with the JIT when
   a queue row is claimed, 204 while idle), then stages the JIT
   and exits. The `runner` main container starts, runs the GitHub
   Actions runner single-shot under that JIT (no token), and
   exits. The runner-container exit is what kubelet observes for
   billing + reaping; the rest is identical to the macOS path
   (which keeps the single-container shape — see "Credential
   split" above).

For the customer-facing dispatch label, autoscaling, and capacity
model see `server/lib/tuist/runners.ex` and
`infra/helm/tuist/values.yaml` (`runnersFleetLinux.pools[]`) —
this doc is only about the container image.
