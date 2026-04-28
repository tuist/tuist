# Xcresult Processor Tart Image

The Tart VM image that hosts the Tuist xcresult processor on macOS.

## Architecture

Every Pod the Virtual Kubelet provider (`infra/vk-orchard/`) schedules onto
the macOS fleet boots a copy of this image as a Tart VM via Orchard. The
VM runs the Tuist server release in xcresult-processor mode under launchd,
draining `:process_xcresult` from the same Postgres the Linux server pods
write to.

The image is the *deploy artifact*: `helm upgrade --set
xcresultProcessor.image.tag=<sha>` updates the Pod spec, k8s rolls Pods,
the VK provider creates new VMs from the new image tag and tears down the
old ones.

## Layout (inside the VM)

| Path | Purpose |
|---|---|
| `/opt/tuist/release/` | Erlang release built upstream by CI |
| `/opt/tuist/inject-env.sh` | Reads Orchard custom data into `/etc/tuist.env` at boot |
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

Orchard creates the VM with a JSON custom-data payload:

```json
{
  "env": {
    "MASTER_KEY": "...",
    "DATABASE_URL": "postgres://tuist_processor:...@db.<env>.supabase.co:6543/postgres?sslmode=require",
    "TUIST_DEPLOY_ENV": "prod",
    "TUIST_XCRESULT_PROCESSOR_MODE": "1",
    "TUIST_WEB": "0",
    "TUIST_DATABASE_POOLED": "1",
    "TUIST_PROCESS_XCRESULT_QUEUE_CONCURRENCY": "4"
  }
}
```

`inject-env.sh` materialises that as `/etc/tuist.env` on first boot; the
launchd unit sources it before exec'ing `tuist start`. This means the
image itself ships **no environment-specific state** — staging, canary,
and production all run the same image, distinguished only by the env the
VK provider passes through from the Pod spec.

## Why a single image, not per-env

Same logic as the Tuist server's `priv/secrets/<env>.yml.enc` design:
one artifact, runtime selection. `TUIST_DEPLOY_ENV` picks which encrypted
secrets bundle to decrypt with `MASTER_KEY`; everything else is
configuration the Pod spec injects. A new env requires zero image
changes — only a new Pod with new env vars.
