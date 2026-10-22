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
- On Apple platforms, `TLSValidator` filters the shared 12-key SPKI policy from additional anchors and checks every certificate in the verified chain after normal trust/hostname evaluation. Custom anchors must not reintroduce blocked keys even on an OS with updated native distrust. Keep DER SPKI hashes synchronized with `infra/certificate-trust/policy.json` and preserve unrelated private CAs. All Apple factories install the delegate even without additional anchors. Direct Foundation callers use `tuistDefault` to retain native cache/cookie/timeout semantics; custom configurations use `URLSession.tuist(configuration:)`. The portable DER policy also feeds the separate NIOSSL verifier in `TuistREAPI`; that does not qualify Linux FoundationNetworking. Live tests explicitly opt in with `TEST_RUNNER_TUIST_TRUST_LIVE=1` and exercise the actual transport, including its task metrics delegate.
- `URLSession.tuistDiscovery` creates an isolated session honoring runtime proxy/private-CA settings, with 10-second request/resource limits, no cookies or credential storage, and no redirects (including with a custom CA).
- `TuistURLSessionTransport` materializes the whole response body before returning, so every body a client middleware receives is re-iterable and a failed transfer is replayed from the start rather than resumed.
- [Hypertext Transfer Protocol (HTTP)](https://developer.mozilla.org/en-US/docs/Web/HTTP) retry behavior uses one shared policy with environment-configurable retry count and base delay, with bounded attempts and per-attempt delay.
- Default proxy mode comes from runtime HTTP settings, and the shared session is resolved lazily, reused process-wide, and invalidated when those runtime settings change.
- Cache integrations may opt into replaying re-iterable uploads only after an explicit pre-forwarding activation rejection. Do not retry ordinary upload failures or transport errors through that exception.
