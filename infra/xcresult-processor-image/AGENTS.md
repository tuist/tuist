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
Builds on the bare-metal `vm-image-builder` Mac mini (Tart needs a live
GUI session for Virtualization.framework — hosted runners can't do this).

Locally:

```bash
mise run xcresult-processor:build-image
```

The local build:
1. Compiles the xcresult Swift NIF (macOS host needs Xcode + Erlang).
2. Builds the server release with `MIX_ENV=prod mix release tuist`.
3. Packages the release as a tarball.
4. Calls Packer with the tarball as a `release_tarball` var.
5. Bakes the result into a Tart image named `tuist-xcresult-processor`.

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
| `TUIST_DATABASE_POOLED` | Pod env (chart) | `1` — Supavisor transaction-mode pooler compatibility |
| `TUIST_PROCESS_XCRESULT_QUEUE_CONCURRENCY` | Pod env (chart) | per-pod Oban concurrency |

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
