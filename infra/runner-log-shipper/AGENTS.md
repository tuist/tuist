# Runner Log Shipper

A tiny, stdlib-only Go binary baked into both runner images
(`infra/runner-image/` macOS Tart VM, `infra/linux-runner-image/`
Linux container). It streams a runner job's stdout to the Tuist
server's log ingest endpoint so the job detail page can show logs
live and per step — the Namespace-style "Logs" tab.

## How it's wired

Both images' `dispatch-poll.sh` pipe the runner through it once a job
is dispatched:

```bash
./run.sh --jitconfig "$jit" --disableupdate 2>&1 \
  | tuist-log-shipper --url "$logs_url" --token "$log_token"
```

- `--token` is the per-job `log_token` from the dispatch response
  (`TuistWeb.RunnerLogToken`), scoping uploads to one workflow_job.
- `--url` is the dispatch URL with `/dispatch` swapped for `/logs`.
- Every line is echoed to stdout (so the VM/Pod log still captures it)
  and batched + POSTed to `POST /api/internal/runners/logs`.

Server side: `TuistWeb.RunnerLogsController` → `Tuist.Runners.JobLogs`
(ClickHouse `runner_job_logs`).

## Behaviour contract

1. **Never blocks the build.** Passthrough first; if the in-flight
   buffer fills (server slow/unreachable), lines are dropped from
   shipping rather than stalling `run.sh`.
2. **Bounded teardown.** On macOS the EXIT trap halts the VM the moment
   the pipe returns, so POSTs are short-timeout + small-retry; the
   closing flush can't wedge the halt.
3. **Best-effort.** The server dedups on `(workflow_job_id,
   line_number)`, so retried batches are harmless and dropped batches
   just leave gaps. The closing batch (`done: true`, `partial` on
   teardown) finalizes the job's `log_state` + line count.

Degrades to a plain stdin→stdout copy when `--url`/`--token` are empty
(image paired with a server that predates log tokens).

## Build

The module is built per-image, standalone (no `go.work`):

- **Linux**: a `shipper-builder` stage in
  `infra/linux-runner-image/Dockerfile` (`GOOS=linux`). The image's
  Docker build context is `infra/` so the stage can reach this dir.
- **macOS**: a `shell-local` provisioner in
  `infra/runner-image/runner.pkr.hcl` cross-compiles `GOOS=darwin
  GOARCH=arm64` on the build host (needs Go on PATH) and installs it to
  `/opt/tuist/tuist-log-shipper`.

Local check:

```bash
cd infra/runner-log-shipper
GOWORK=off go vet ./... && GOWORK=off go build ./...
```
