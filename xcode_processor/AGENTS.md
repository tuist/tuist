# Xcresult Processor

Deploy infrastructure for the macOS hosts (Scaleway Mac minis) that run the
Tuist server release as the dedicated `:process_xcresult` Oban consumer.

## What lives here

- `platform/` — nix-darwin configuration that provisions the Mac mini and
  declares a launchd job which boots `tuist start` with
  `TUIST_XCRESULT_PROCESSOR_MODE=1`. Same flake/sops layout as before;
  the launchd unit name kept its historical `xcode-processor` slug so
  existing state on the live machines rolls forward without surgery.
- `mise/tasks/` — build (`build-nif`, `build-release`) and deploy
  (`deploy`) helpers. They drive a build of the server's Elixir release
  on macOS plus the macOS-only xcresult Swift NIF, package it, ship to
  the host, and swap the launchd symlink atomically with rollback.

## Architecture

The xcresult parse path leans on `xcresulttool` from Xcode, which has no
Linux equivalent. The in-cluster Linux server pods drop `:process_xcresult`
from their Oban queue list (via `TUIST_DELEGATE_PROCESS_XCRESULT=1`, set
by the Helm chart whenever `xcresultProcessor.enabled` is true), so jobs
land exclusively on the macOS fleet — this directory's hosts.

The Elixir code (`Tuist.Processor.XCResultProcessor`,
`Tuist.Processor.XCResultNIF`, `Tuist.Tests.Workers.ProcessXcresultWorker`)
lives in `server/` alongside everything else; the macOS host runs the
*same* compiled release as the in-cluster pods. Worker / schema lockstep
is bit-for-bit by construction.

## Development

There's no standalone Mix app to develop here anymore. To iterate on the
worker locally, work in `server/` against a macOS dev environment:

```bash
cd server
mise run dev
```

The Swift NIF builds via `server/native/xcresult_nif/build.sh` (or `cd
xcode_processor && mise run build-nif` as a thin wrapper).

## Deploy

Deploys are driven from CI (`.github/workflows/xcode-processor-deploy.yml`)
on `workflow_dispatch`. Locally:

```bash
cd xcode_processor
mise run deploy <host> <staging|canary|production>
```

The script builds the server release with the xcresult NIF, packages it,
SCPs to the host, swaps `~/xcode_processor/current` symlink, and bounces
launchd. Health verification waits for the launchd job to stay up rather
than probing an HTTP port (the release runs with `TUIST_WEB=0`).

## Dashboards

The Grafana dashboard is at
[`infra/grafana-dashboards/xcode-processor-service.json`](../infra/grafana-dashboards/xcode-processor-service.json)
and kept in sync with Grafana Cloud via Git Sync. See `infra/AGENTS.md`
for the editing workflow.
