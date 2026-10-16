# GitLab job executor

Executes one job already acquired by the server using GitLab Runner's execution
engine. The input contains job credentials, never the reusable runner token.
Keep the upstream version in `go.mod` aligned with the server's request metadata.

The shell executor runs inside an isolated Linux microVM or macOS VM. GitLab's
engine owns checkout, variables, masking, artifacts, caches and cancellation.
Capture logs at the JobTrace boundary, after upstream masking, and report them
with the existing job-scoped Tuist report endpoints. Never print the input.

Validate with `GOWORK=off go test ./...` and a local fake coordinator execution that covers
checkout, failure, cancellation and masked variables. Do not use real GitLab or
staging credentials for local tests.

- All trace outcome and completion state accesses use the trace mutex, including early cancellation and deferred reporting. Exercise cancellation with the race detector.

- Exit zero after reporting script failure, cancellation, timeout, or invalid pipeline configuration; these are job outcomes, not runner deaths. Preserve non-zero process exits for executor/infrastructure failures. Exercise the CLI process in integration tests and verify both the process status and upstream/Tuist job outcomes.

- Because job outcomes exit zero, `--result-file <path>` writes `succeeded`, `failed` or `canceled` there once the job ends. The macOS image passes it and promotes the account's cache volume only on `succeeded`. The Linux image does not pass it. `TestExecute` asserts the file for every scenario.

- `cache.go` registers the `tuist` cache adapter so `cache:` survives the machine. Downloads use a presigned URL. Uploads return a Go CDK `tuist://` URL instead, which `cache_bucket.go` opens in the archiver process to upload the archive in parts, buffering one part at a time; a single presigned PUT would cap archives at 5 GB. Both ask the Tuist report endpoints with the job-scoped report token, which reaches the archiver through GitLab's cache env file; storage credentials never enter the machine. A failed or cancelled write aborts its upload. When the endpoints refuse, GitLab Runner skips the remote cache and the job continues. Upstream strips query strings before logging cache URLs, so signatures stay out of traces. `TestCacheCrossesMachines` restores an archive larger than one part in a separate builds directory; keep that property covered.

- `cacheVolumeEnvironment` forwards only the three pod-local volume routing
  variables to generated job scripts. The server verifies identity independently.
  Keep them available in before_script and exercise this through TestExecute.

- `waiting_trace` holds the bytes the server may already have written to the GitLab job log while the job waited for a machine. Write them before anything else, then close the `tuist_waiting_for_runner` section on its own line in the same timestamp format. Upstream skips to GitLab's offset on a range mismatch, so any other first bytes would drop the start of the runner's own log. `TestExecuteContinuesAfterServerWaitingTrace` runs against a coordinator that enforces `Content-Range` like GitLab.
