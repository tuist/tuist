# Staging cache DNS probes

This standalone Go module keeps repeatable staging validation separate from the
production controller build. Run `GOWORK=off go test -race ./...` and `GOWORK=off go vet ./...`.

`cmd/staging-probe` verifies public TLS and authenticated HTTP/REAPI round trips;
it invokes grpcurl with credentials in its environment, never arguments.
`cmd/staging-soak` is restricted to the spec95 staging fixture and holds HTTP/1.1
and HTTP/2 connections across a bounded outage. Its unauthenticated latency mode
uses paired `/up` requests, ordinary and authoritative DNS, and verified TLS.
Never generalize the probe to production or commit tokens or run-specific logs.

Keep usage and safety prerequisites in the parent `README.md`. Preserve completed
run evidence in PR attachments or immutable links, separate from the runbook.
