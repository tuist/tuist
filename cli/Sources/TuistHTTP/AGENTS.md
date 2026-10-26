# TuistHTTP (CLI Module)

This module provides HTTP client helpers used by server and cache integrations.

## Responsibilities
- Provide file upload/download client (`FileClient`) with explicit error modeling.
- Provide middleware and auth helpers for API clients (request IDs, output warnings).

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistServer/AGENTS.md
- cli/Sources/TuistCache/AGENTS.md

## Invariants
- File transfers treat non-2xx responses as fatal errors.
- Default URL session uses explicit request/resource timeouts.
- Every Tuist session closes a connection idle for 10 seconds (Darwin `_connectionCachePurgeTimeout`, set only when the configuration responds to its setter), below the server's 15-second keep-alive idle timeout, so a request is not written on a connection the server is closing. FoundationNetworking (Linux) exposes no idle timeout, so Linux sessions keep libcurl's connection reuse.
- `URLSession.tuistDiscovery` creates an isolated session honoring runtime proxy/private-CA settings, with 10-second request/resource limits, no cookies or credential storage, and no redirects (including with a custom CA).
- `TuistURLSessionTransport` materializes the whole response body before returning, so every body a client middleware receives is re-iterable and a failed transfer is replayed from the start rather than resumed.
- [Hypertext Transfer Protocol (HTTP)](https://developer.mozilla.org/en-US/docs/Web/HTTP) retry behavior uses one shared policy with environment-configurable retry count and base delay, with bounded attempts and per-attempt delay. `RetryMiddleware` defaults to five attempts over about three to four seconds so a server rollout is ridden out; `RetryProvider` wrappers keep their own shorter defaults so the two layers do not multiply into a long wait.
- `RetryMiddleware` replays GET/HEAD and caller-listed idempotent operation IDs after any transport error or 408/429/5xx. Any other request is replayed only when the server never processed it: a connection that could not be established, or 429/503. A `CredentialAcquisitionError` from an authentication middleware is never replayed and its underlying error is rethrown: each refresh path retries itself, so replaying the request would multiply the refreshes sent.
- `HTTPRetryPolicy.isRetryable` is the shared classifier for wrapped retries: errors without a status are retryable except a cancelled `URLError`, and `HTTPStatusCodeError`s follow their own `isRetryable`. `HTTPRetryPolicy.run` applies it to transfers outside the server client, and `FileClient` downloads surface non-2xx responses as status-carrying errors so they classify. Cancellation is never retried.
- Default proxy mode comes from runtime HTTP settings, and the shared session is resolved lazily, reused process-wide, and invalidated when those runtime settings change.
- Cache integrations may opt into replaying re-iterable uploads only after an explicit pre-forwarding activation rejection. Do not retry ordinary upload failures or transport errors through that exception.
