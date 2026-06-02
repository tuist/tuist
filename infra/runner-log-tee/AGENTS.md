# Runner Log Tee

A tiny, stdlib-only Go binary baked into both runner images
(`infra/runner-image/` macOS Tart VM, `infra/linux-runner-image/`
Linux container). It streams a runner job's step output to the Tuist
server's log ingest endpoint so the job detail page can show logs
live and per step — the Namespace-style "Logs" tab.

## How it's wired

Both images' `dispatch-poll.sh` tail the Worker diag log through it
once a job is dispatched:

```bash
( wait for _diag/Worker_<utc>.log to appear ) \
  | tail -F -n +1 "$wlog" \
  | tuist-log-tee --url "$logs_url" --token "$log_token"
```

- `--token` is the per-job `log_token` from the dispatch response
  (`TuistWeb.RunnerLogToken`), scoping uploads to one workflow_job.
- `--url` is the dispatch URL with `/dispatch` swapped for `/logs`.
- Every line read from stdin is echoed back to stdout and batched +
  POSTed to `POST /api/internal/runners/logs`.

### Why the Worker diag log, not `run.sh`'s stdout?

`run.sh` is GitHub's `actions/runner` Listener. It only prints
lifecycle markers ("Listening for Jobs", "Running job: X", "Job X
completed") to its own stdout. The actual step output (user `run:`
shell commands) is executed in the Worker child process, which writes
ALL step content to `_diag/Worker_<utc>.log` rather than echoing it
back through the Listener. Piping `run.sh`'s stdout into the tee
yields lifecycle markers and nothing useful — staging smoke confirmed
this empirically. Tailing the diag file is the only stable way to
capture step content without modifying GitHub's runner binary.

The diag log is verbose by design (framework metadata interleaved
with step output). For now we ship it raw; the UI can filter later.

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

- **Linux**: a `tee-builder` stage in
  `infra/linux-runner-image/Dockerfile` (`GOOS=linux`). The image's
  Docker build context is `infra/` so the stage can reach this dir.
- **macOS**: a `shell-local` provisioner in
  `infra/runner-image/runner.pkr.hcl` cross-compiles `GOOS=darwin
  GOARCH=arm64` on the build host (needs Go on PATH) and installs it to
  `/opt/tuist/tuist-log-tee`.

Local check:

```bash
cd infra/runner-log-tee
GOWORK=off go vet ./... && GOWORK=off go build ./...
```
