# Xcresult Processor Tart Image

The Tart VM image that hosts the Tuist xcresult processor on macOS.

## Architecture

Every Pod the tart-cri runtime (`infra/tart-cri/`) schedules onto the
macOS fleet boots a copy of this image as a Tart VM. The VM runs the
Tuist server release in xcresult-processor mode under launchd, draining
`:process_xcresult` from the same Postgres the Linux server pods write to.

The image is the *deploy artifact*: `helm upgrade --set
xcresultProcessor.image.tag=<sha>` updates the Pod spec, k8s rolls Pods,
tart-kubelet creates new VMs from the new image tag and tears down the
old ones.

## Layout (inside the VM)

| Path | Purpose |
|---|---|
| `/opt/tuist/release/` | Erlang release built upstream by CI |
| `/opt/tuist/inject-env.sh` | Reads the kubelet env mount into `/etc/tuist.env` at boot |
| `/etc/tuist.env` | Sourced env vars (MASTER_KEY, DATABASE_URL, TUIST_DEPLOY_ENV) |
| `/Library/LaunchDaemons/dev.tuist.xcresult-processor.plist` | Boots `tuist start` |
| `/var/log/xcresult-processor/{stdout,stderr}.log` | Captured output |

## Building

CI: `.github/workflows/xcresult-processor-image.yml` runs on every push to
`main` that touches `server/lib/**`, the xcresult NIF, or this directory.
Builds on the bare-metal `vm-image-builder` Mac mini fleet (Tart
needs a live GUI session for Virtualization.framework, so hosted
runners can't do this). Builder fleet operator runbook:
[`../vm-image-builder.md`](../vm-image-builder.md).

Registry publication uses the shared
[`tart-push`](../../.github/actions/tart-push/action.yml)
action. Its bounded concurrency, chunking, retry, and route diagnostics are
part of the builder-fleet reliability contract; keep the on-demand and
production release workflows on that shared path.

Locally:

```bash
mise run xcresult-processor:build-image
```

The local build:
1. Compiles the xcresult Swift NIF (macOS host needs Xcode + Erlang).
2. Builds the server release with `MIX_ENV=prod mix release tuist`.
3. Packages the release as a tarball.
4. Calls Packer with the tarball as `release_tarball`.
5. Bakes the result into a Tart image named `tuist-xcresult-processor`.

## Layer 1 dependency

This is **Layer 2** on top of
`ghcr.io/tuist/macos-tahoe-xcode:<xcode-version-dashes>` (built by
`infra/macos-xcode-image`). Xcode itself lives in Layer 1 because
the NIF shells out to `/usr/bin/xcrun xcresulttool`, which only
ships in full Xcode (not the Command Line Tools).

Unlike `infra/runner-image` (where customers pin a specific runner
profile to a specific Xcode), the xcresult-processor is a
**singleton backend service** that has to parse .xcresult bundles
produced by every customer runner profile. xcresulttool's JSON
schema changes across Xcode majors, so the processor should run on
at least as new an Xcode as any active runner-image profile.

The Xcode version is declared inline in `.github/workflows/release.yml`'s
`release-xcresult-processor-image.Build image` step (current value is
the `XCODE_VERSION` env var on that step). Bump it alongside the
runner-image matrix when promoting a new Xcode to the fleet:

1. Publish a Layer 1 image with the new Xcode — first run
   `mise run xcode-mirror:upload 26.X.Y` on a maintainer Mac to put
   the .xip into `ghcr.io/tuist/xcode-xips:26.X.Y`, then
   `gh workflow run macos-xcode-image.yml -f xcode_version=26.X.Y`.
   See `infra/macos-xcode-image/AGENTS.md` for the runbook.
2. Update the runner-image active matrix and this image's
   `XCODE_VERSION` env var in `release.yml` in the same commit so
   the processor never lags an active runner profile. Merge with
   a `feat(xcresult-processor-image): bump to Xcode 26.X.Y` message;
   check-releases picks it up from `infra/xcresult-processor-image/**`.

To rebuild against a different Xcode without bumping the inline
version (e.g. testing a 26.X.Y release candidate), dispatch
`xcresult-processor-image.yml` with `-f xcode_version=26.X.Y`.

## Env injection at runtime

tart-kubelet stages the Pod's env vars as a `KEY=value` file under
`--dir env:<host-path>:ro`, which the guest sees at
`/Volumes/My Shared Files/env/tuist.env`. The keys the launchd unit
expects:

| Env var | Source | Notes |
|---|---|---|
| `MASTER_KEY` | k8s Secret (`server-master-key`) | Unlocks the encrypted `priv/secrets/<env>.yml.enc` baked into the release |
| `DATABASE_URL` | k8s Secret (`processor-database-url`) | The `tuist_processor` Postgres role URL — same role the in-cluster build processor uses |
| `TUIST_DEPLOY_ENV` | Pod env (chart) | `prod` / `can` / `stag` — picks which encrypted bundle to decrypt |
| `TUIST_XCRESULT_PROCESSOR_MODE` | Pod env (chart) | `1` — narrows Oban to `:process_xcresult` only |
| `TUIST_WEB` | Pod env (chart) | `0` — skips Phoenix endpoint |
| `TUIST_DATABASE_POOLED` | Pod env (chart) | `1` — transaction-mode pooler compatibility |
| `TUIST_PROCESS_XCRESULT_QUEUE_CONCURRENCY` | Pod env (chart) | per-pod Oban concurrency |
| `TAILSCALE_AUTH_KEY` | k8s Secret (macOS-fleet ESO Secret) | Tailnet join credential: an OAuth client secret, see below |
| `TAILSCALE_HOSTNAME` | Pod env (Downward API) | Pod name; the device name this VM registers under |
| `TAILSCALE_TAGS` | Pod env (chart, from `macosFleet.tailscale.tags`) | ACL tag the join applies; required with an OAuth credential |

`inject-env.sh` materialises that as `/etc/tuist.env` on first boot; the
launchd unit sources it before exec'ing `tuist start`. This means the
image itself ships **no environment-specific state** — staging, canary,
and production all run the same image, distinguished only by the env the
Pod spec injects.

## Why a single image, not per-env

Same logic as the Tuist server's `priv/secrets/<env>.yml.enc` design:
one artifact, runtime selection. `TUIST_DEPLOY_ENV` picks which encrypted
secrets bundle to decrypt with `MASTER_KEY`; everything else is
configuration the Pod spec injects. A new env requires zero image
changes — only a new Pod with new env vars.

> **Note:** the env table and the `MASTER_KEY` / encrypted-blob description
> above predate the #11460 secrets migration, which removed the blob and moved
> the processor onto the ESO config Secret. They need a separate accurate
> update — left out of this change to keep it a clean rebuild trigger.

## Boot chain and how it fails silently

The launchd unit hard-ANDs the boot steps:

```
inject-env.sh && source /etc/tuist.env && tailscale-up.sh && exec tuist start
```

Every step is load-bearing, and the last one is the only one Kubernetes
can see. tart-kubelet is not a real kubelet: it implements no container
probes at all, and
`infra/tart-kubelet/internal/podagent/reconciler.go` sets
`PodReady=True` (plus synthesized Ready container statuses) as soon as
the VM has an IP. A VM that boots and then dies at `tailscale-up.sh`
therefore reads `1/1 Running` forever, the Deployment reports
`Available=True`, and `:process_xcresult` simply stops being consumed.

This has happened twice, from unrelated causes with the same outward
shape:

- **2026-06-26.** A clobbered host VM-to-internet NAT left the guest
  unable to complete a TCP handshake to the Tailscale control plane.
  `tailscale up` blocked indefinitely. The `--timeout=60s` flag in
  `tailscale-up.sh` was added in response, so the chain now exits
  non-zero and launchd's `KeepAlive` retries instead of stranding the
  VM.
- **2026-08-12.** The Tailscale pre-auth key expired. `tailscale up`
  now fails fast rather than hanging, but failing fast in a crash loop
  is just as invisible: the release still never starts. The queue had
  zero consumers for roughly thirteen hours, around 4,600 jobs backed
  up, and roughly 4,000 test runs sat at `status='processing'` across
  every account using remote processing. It was reported by a customer.

The credential deserves specific attention. `tailscale up` runs on
**every VM boot**, and a VM is created fresh on every Pod roll, so
unlike the Mac mini hosts (which join once and keep their tailnet
identity across rotations) the processor puts it on the critical path
continuously.

That is why `TAILSCALE_AUTH_KEY` now holds an **OAuth client secret**
rather than a pre-auth key. Tailscale caps pre-auth keys at 90 days and
offers no way to extend one, so the 2026-08-12 failure recurred by
construction unless someone rotated ahead of expiry, which is a control
that fails eventually. OAuth clients don't expire, and `tailscale up`
accepts the client secret wherever an auth key goes and mints a fresh
key per join, so there is no longer a date to miss. ExternalSecrets was
never the safety net here either: it reports `SecretSynced` /
`Ready=True` for an expired value exactly as for a valid one, so its
status is not a signal.

`tailscale-up.sh` pins two properties on the minted key rather than
inheriting their defaults:

- `preauthorized=true`, because the default is `false` and a device
  parked awaiting manual approval fails the join exactly like an
  expired credential, with the same invisible outcome.
- `ephemeral=true`, which is narrower than it looks. `TAILSCALE_HOSTNAME`
  is the Pod name, so every roll registers a new device, but Tailscale
  converts any device online for four hours into a standard tagged one
  and Pods normally outlive that between image releases. It reaps only
  short-lived ones; the rest accumulate, and those stale peers stay
  pinned in every VM's `/etc/hosts`, which `tailscale-up.sh` rewrites
  from `tailscale status` on each boot. Nothing deletes a device today,
  on this path or the Mac mini one; a reaper is the tracked follow-up.

Keys minted through an OAuth client are always tagged and carry no
default tag, so `TAILSCALE_TAGS` must name one (the chart sources it
from the fleet's `macosFleet.tailscale.tags`). The script refuses to
start when the credential is an OAuth secret and the tag is missing,
rather than letting `tailscale up` fail 60s later with a message that
reads like a network fault. A legacy pre-auth key is detected by prefix
and passed through untouched, so the image boots against either
credential while envs migrate.

One diagnostic gap this does not close: `tailscale-up.sh` still reports
a server-side credential rejection and an unreachable control plane
through the same "did not reach Running within timeout" path, which is
what made the two incidents above look alike from the outside.

**Detection.** Since neither the Pod, the Deployment, nor ExternalSecrets
can see this class of failure, it is caught in the metrics pipeline
instead. Four rules in
[`../helm/k8s-monitoring/alerts.md`](../helm/k8s-monitoring/alerts.md)
cover it, and they are cause-independent by design:

| Rule | Catches |
|---|---|
| `Remote processing queue has no consumer` | The queue not draining, whatever the reason. Read from Postgres by the Linux web pods, so it survives total loss of this fleet. |
| `xcresult processor guest metrics unavailable fleet-wide` | No guest PromEx endpoint answering anywhere. This is the readiness probe tart-kubelet cannot provide. |
| `xcresult processor guest metrics unavailable on one host` | Half capacity, including a mini that is powered on but never joined the cluster. |
| `xcresult processor replicas unavailable` | The scheduling half: a replica stuck `Pending` while the Deployment still reports `Available=True`. |

**Reading guest logs.** `kubectl logs` does not work here (the apiserver
cannot resolve the Tailscale-only kubelet hostnames), and neither does
Alloy's pod-log collection. Use
`tailscale ssh admin@<vm-tailnet-ip>` and read
`/var/log/xcresult-processor/{stdout,stderr,diagnostics}.log`. Note the
circularity: if the failure is that the VM never joined the tailnet,
there is no tailnet address to ssh to, and the host's own
`tart` CLI is the only way in.

## Releasing this image & schema drift

This image **bakes a full server release**, so its baked code can drift from the
live DB schema if it isn't rebuilt when the server changes. The release gate
(`mise/tasks/release/components.json` → `xcresult-processor-image`, evaluated by
`git cliff` in `mise/tasks/release/check.sh`) is **scope-gated**: it cuts a new
version only for conventional commits it doesn't skip — it skips `chore`, `ci`,
and other-scoped commits — that touch `server/lib/tuist/**`, the xcresult NIF,
`server/mix.{exs,lock}`, or this directory. That gate is intentionally
conservative: the build runs Packer on a single bare-metal Mac mini and is
expensive, so we deliberately do **not** rebuild on every server change.

The tradeoff: a server change merged under a **skipped scope** (e.g. a
`chore(server)` that also drops a column) won't auto-rebuild this image, so the
baked release keeps running old code against the new schema. That happened once
and took production down — the processor queried a column a migration had just
dropped.

**Runbook — when a schema- or runtime-affecting server change lands under a
skipped scope:** cut a manual release so the image rebuilds against current
`main`. The simplest way is a `fix`/`docs`-scoped commit touching this directory
(this very commit is one), which makes `git cliff` bump the version and the
`release-xcresult-processor-image` job rebuild + retag `:<version>` + `:latest`
and rewrite the chart tag. To smoke-test image contents without cutting a
version, dispatch `xcresult-processor-image.yml` for a throwaway `:<sha>` build.
