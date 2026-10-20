# TuistServer (Server Integration)

This module handles CLI integration with the Tuist Server APIs.

## Responsibilities
- Resolve server environment (base URL, OAuth client ID) with env var overrides.
- `ExchangeOIDCTokenService` forwards optional `TUIST_OIDC_ACCOUNT` as `account_handle`. Custom workload providers require this account selector; built-in CI providers keep it optional. It chooses the destination account, never substitutes for verified workload identity and project trust. Keep the request additive for existing CI providers and regenerate OpenAPI types from the controller schema.
- Provide cache storage factories and API clients for server-backed features.
- Map CLI actions to server operations (projects, previews, analytics, registry).
- `CreateShardPlanService` can declare concurrent module-level units (nextest binaries) via `concurrentModules`. Keep this distinct from `parallelizableModules`, which declares suite-level parallelism within a module for Xcode. Other callers omit the declaration and retain their existing planning behavior. Regenerate the shared API from controller schemas when extending this contract.
- Preserve optional preview tracks and plain-text release notes in `ServerPreview`; `ListPreviewsService` applies exact track filtering through the generated query contract and offers a separate `searchPreviews` entry point for literal, case-insensitive search across display names and full release notes; existing CLI listing calls omit search and retain exact `display_name` semantics, and preview upload services forward optional release notes from `tuist share`. `ListPreviewTracksService` returns a `ServerPreviewTrackSummary` with the full project's preview total (including untracked previews) and case-insensitively grouped named-track counts, independently of pagination, search, and active track selection; only HTTP 404 indicates an older server without discovery, while authorization, throttling, and transport failures remain errors.
- Apply the shared [Hypertext Transfer Protocol (HTTP)](https://developer.mozilla.org/en-US/docs/Web/HTTP) retry policy to retryable server operations.

## Related Context
- Server codebase: `server/AGENTS.md`

## Invariants
- `ServerClientActorHeadersMiddleware` sends `x-tuist-actor-id` only on report creation, requiring explicit `TUIST_ACTOR_ID` or a supplied request header. Never infer operating-system usernames; empty/invalid environment values omit the claim. Identifiers are opaque, unverified, 1–128 bytes of printable non-space ASCII and never replace authentication. Actor API fields are optional and evolving provenance values remain open strings for older-server compatibility. Never attach the claim to cache/read/admin/artifact requests.
- `Client.reporting` enables absent-credential publication only for structured build/test creates with `TUIST_NETWORK_TRUSTED_PUBLISHING=true` and a validated self-hosted destination. Preserve corrupt/rejected credentials, including refresh rejection outside this mode, so a later opted-in command cannot silently downgrade. Existing credentials and errors must never become anonymous retries; optional cache auth must not suppress report credential errors. Rejected-refresh markers intentionally apply to ordinary authentication too: deleting them outside opt-in mode would allow a later opted-in command to downgrade silently. Blank-token validation is strict only in opted-in report publication; do not broaden it to ordinary authentication. File credentials normalize hostname case/trailing dots, retain legacy aliases on reads, and explicit logout removes every matching alias. Directory inspection errors fail closed; fresh login replaces the rejected canonical entry.
- Refresh timeouts do not establish credential rejection. Preserve credentials and keep timeout messages free of login/logout advice, including when optional cache authentication reports them as warnings.
- `TUIST_URL` overrides config URL and must be a valid URL.
- OAuth client ID defaults to a built-in value if not provided. OAuth app credentials may carry an issuing `oauthClientID`; refresh uses that server-scoped value and preserves it when rotating tokens. Legacy/API-auth credentials remain compatible without this field.
- Browser authentication reports OSC 7501 `blocked` with `kind=auth` while waiting for tokens, then restores `working`. This uses the CLI-scoped reporter and is a no-op in other consumers.
- Cache request metadata carries SDK build fingerprints separately from the existing exact content hash; preserve it through target-to-item storage conversions.

- Persistent Gradle task, generated Xcode module, Once action, Mix file and Mix module inventory/detail/history endpoints are generated from native server resource schemas. Exact-key Xcode/Bazel action resources are deliberately excluded. The server requires per-project enrollment and returns 404 while these new resources are disabled; existing run APIs remain available. They use project-scoped stable IDs independent of runs, retain nullable measurements and keyset cursor metadata, and keep extensible outcomes as open strings. The additive `duration_samples` metric is optional in generated responses so earlier responses still decode; it counts recorded durations, including zero, rather than all observations. Existing ingestion and per-run read contracts remain unchanged.

- Mix's optional dependency-cache observations are generated from the server build-report schema; keep nullable avoided-compilation estimates, local/remote hits, I/O source provenance, paired measurements and supported reason values aligned. Never derive remote CAS outputs from these client observations; Kura's shared signed REAPI telemetry is authoritative.
- Gradle and Bazel recorded-step endpoints and the optional Gradle report start timestamp are generated from server controller schemas. Regenerate through `server/mise/tasks/generate-api-cli-code.sh`; preserve opaque step IDs and nullable per-step logs.
- The generated Xcode build list supports `from`/`to` Unix-second creation-time bounds, `is_ci`, `after`/`before` cursors, and pages up to 1,000 builds. Requests without a cursor preserve first-page offset metadata and return cursors for subsequent `after`/`before` requests; explicit `page` retains offset pagination. List/detail `started_at` is optional and nullable for historical or unavailable activity-log timing.

- Command event serialization sends effective destinations and all individual subhashes, including embedded products, foreign builds, and UI-test device/runtime inputs. Do not substitute declared graph destinations for missing inputs.

- Runner volume operations each have a dedicated service and mockable protocol.
  Keep generated request/response mapping here, preserve pagination envelopes and
  nullable measurements, and map rate limits to AuthorizationThrottledError with
  Retry-After. Noora presentation and project/account resolution belong to the
  runner command module.

- Preserve the deprecated `/api/cache/endpoints` API for older clients. Self-hosted clients use `/api/cache/endpoint` to retrieve one main server-configured URL, without demand or provisioning. Hosted URL derivation in TuistCAS never calls discovery.
