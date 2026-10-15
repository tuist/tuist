# TuistServer (Server Integration)

This module handles CLI integration with the Tuist Server APIs.

## Responsibilities
- Resolve server environment (base URL, OAuth client ID) with env var overrides.
- Provide cache storage factories and API clients for server-backed features.
- Map CLI actions to server operations (projects, previews, analytics, registry).
- Apply the shared [Hypertext Transfer Protocol (HTTP)](https://developer.mozilla.org/en-US/docs/Web/HTTP) retry policy to retryable server operations.

## Related Context
- Server codebase: `server/AGENTS.md`

## Invariants
- `ServerClientActorHeadersMiddleware` adds optional `x-tuist-actor-id` only to authenticated report creates. Claims require explicit `TUIST_ACTOR_ID` or a supplied request header; never infer operating-system usernames. Empty/invalid environment values omit the automatic header. Identifiers are opaque, unverified, 1–128 bytes of printable non-space ASCII. Keep authentication, endpoints, JSON bodies and generated contracts unchanged so older servers can ignore the header. Never attach it to cache/read/admin/artifact requests.
- `TUIST_URL` overrides config URL and must be a valid URL.
- OAuth client ID defaults to a built-in value if not provided. OAuth app credentials may carry an issuing `oauthClientID`; refresh uses that server-scoped value and preserves it when rotating tokens. Legacy/API-auth credentials remain compatible without this field.
- Browser authentication reports OSC 7501 `blocked` with `kind=auth` while waiting for tokens, then restores `working`. This uses the CLI-scoped reporter and is a no-op in other consumers.
- Cache request metadata carries SDK build fingerprints separately from the existing exact content hash; preserve it through target-to-item storage conversions.

- Persistent task/action/module/file inventory, detail and history endpoints are generated from native server resource schemas. They use project-scoped stable IDs independent of runs, retain nullable measurements and keyset cursor metadata, and keep extensible outcomes as open strings. The additive `duration_samples` metric is optional in generated responses so earlier responses still decode; it counts recorded durations, including zero, rather than all observations. Existing ingestion and per-run read contracts remain unchanged.

- Mix's optional dependency-cache observations are generated from the server build-report schema; keep nullable avoided-compilation estimates, local/remote hits, I/O source provenance, paired measurements and supported reason values aligned. Never derive remote CAS outputs from these client observations; Kura's shared signed REAPI telemetry is authoritative.
- Gradle and Bazel recorded-step endpoints and the optional Gradle report start timestamp are generated from server controller schemas. Regenerate through `server/mise/tasks/generate-api-cli-code.sh`; preserve opaque step IDs and nullable per-step logs.

- Command event serialization sends effective destinations and all individual subhashes, including embedded products, foreign builds, and UI-test device/runtime inputs. Do not substitute declared graph destinations for missing inputs.

- Runner volume operations each have a dedicated service and mockable protocol.
  Keep generated request/response mapping here, preserve pagination envelopes and
  nullable measurements, and map rate limits to AuthorizationThrottledError with
  Retry-After. Noora presentation and project/account resolution belong to the
  runner command module.

- Preserve the deprecated `/api/cache/endpoints` API for older clients. Self-hosted clients use `/api/cache/endpoint` to retrieve one main server-configured URL, without demand or provisioning. Hosted URL derivation in TuistCAS never calls discovery.
