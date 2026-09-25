# Shared cache activation gateway

This package is a stateless HTTP/gRPC streaming proxy for the wildcard DNS fallback.

- Never store artifacts, spool bodies to disk, replay requests, follow control-plane redirects, or forward credentials to caller-provided URLs.
- Host parsing selects only configured production/canary/staging control planes. The control plane authenticates cache access, checks billing and starts provisioning; the regional backend retains full request authorization.
- Only HTTPS `*.kura.tuist.dev` regional targets are permitted. Stable URLs would loop; custom URLs would relay credentials outside managed infrastructure.
- Keep activation waits, admitted requests, HTTP/2 buffers and network deadlines bounded. Do not read upload bodies while waiting. Cancellation releases admission; overload/timeout use retryable HTTP/gRPC responses.
- Use distinct ingress upstream ports for HTTP and gRPC; one pooled nginx address/port cannot safely mix `proxy_pass` and `grpc_pass`.
- Tests use local control planes and HTTP/2 upstreams. Run `GOWORK=off go test -race ./internal/activation ./cmd/cache-activation` from the controller module.
- Deployment and DNS opt-ins remain off until the rollout in [activation.md](../../activation.md) is validated. No per-account pod or PVC belongs to this gateway.
