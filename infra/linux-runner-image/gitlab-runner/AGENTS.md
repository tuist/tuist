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
