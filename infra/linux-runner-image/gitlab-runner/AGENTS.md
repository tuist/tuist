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

- `cache.go` registers the `tuist` cache adapter so `cache:` survives the machine. It asks the Tuist report endpoint for presigned URLs with the job-scoped report token; storage credentials never enter the machine. When the endpoint refuses, return empty URLs so GitLab Runner skips the remote cache and the job continues. Upstream strips query strings before logging cache URLs, so signatures stay out of traces. `TestCacheCrossesMachines` restores an archive in a separate builds directory; keep that property covered.
