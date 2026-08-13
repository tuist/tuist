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

## Tailnet join is on the critical path of every boot

The launchd unit chains `inject-env.sh && source /etc/tuist.env &&
tailscale-up.sh && exec tuist start`. That `&&` is load-bearing: the
release dials the Postgres pooler over the tailnet, so a VM that hasn't
joined has nothing to start against. It also means **anything that
breaks the join takes the `:process_xcresult` queue offline**, and does
so invisibly, because tart-kubelet implements no container probes and marks the
Pod `Ready` as soon as the VM has an IP, so a guest with no BEAM in it
still reads `1/1 Running`.

The distinction from the Mac mini hosts matters. A host joins once and
keeps its tailnet identity; these VMs are ephemeral, so **every Pod roll
performs a fresh join**. A credential that is merely stale is harmless
for the fleet and fatal here.

That is why `TAILSCALE_AUTH_KEY` holds an **OAuth client secret** rather
than a pre-auth key. Tailscale caps pre-auth keys at 90 days and offers
no way to extend one, so joining with a pre-auth key puts a scheduled
outage on the calendar with nothing but a human remembering the date in
the way. On 2026-08-12 that key lapsed and the queue had zero consumers
for ~13h. OAuth clients don't expire; `tailscale up` accepts the client
secret wherever an auth key goes and mints a fresh key per join.

`tailscale-up.sh` pins two properties on the minted key, because
inheriting either default would reintroduce the same silent wedge:

- `preauthorized=true`, because the default is `false` and a device parked
  awaiting manual approval fails the join exactly like an expired
  credential.
- `ephemeral=true`, because `TAILSCALE_HOSTNAME` is the Pod name, so every roll
  registers a new device; non-ephemeral would leak one per roll.

Keys minted through an OAuth client are always tagged and carry no
default tag, so `TAILSCALE_TAGS` must name one (the chart sources it
from the fleet's `macosFleet.tailscale.tags`). The script refuses to
start when the credential is an OAuth secret and the tag is missing,
rather than letting `tailscale up` fail 60s later with a message that
reads like a network fault. A legacy pre-auth key is detected by prefix
and passed through untouched, so the image boots against either
credential while envs migrate.

Two things this does **not** fix, worth knowing before diagnosing a
stall: ESO reports `SecretSynced` / `Ready=True` whatever the value's
validity, and `tailscale-up.sh` still reports a server-side credential
rejection and an unreachable control plane through the same "did not
reach Running within timeout" path. Detection for the whole failure
class lives in `infra/helm/k8s-monitoring/alerts.md`, keyed on queue age
rather than on any particular cause.

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
