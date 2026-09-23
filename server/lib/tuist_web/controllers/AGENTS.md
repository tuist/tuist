# Controllers (Web Layer)

This area owns Phoenix controllers for HTML and API endpoints.

## Responsibilities
- `RunnerShadowController` exposes a bounded read-only demand snapshot only to
  the configured runners-controller principal via `RunnerControllerAuth`.
  It contains cross-account identifiers and must use `private, no-store`.
- `BuildController.timeline/2` returns full build step metadata without logs, scoped to the authorized project/build. Bandit negotiates HTTP compression; the response uses `private, no-store`.
- Handle request/response flow and rendering for controller actions.
- Google One Tap uses a same-origin start request and a CSRF-protected completion request in `AuthController`. Marketing HTML is shared-cached, so the start request cannot present the page's session-bound CSRF token; the router routes it through the `:same_origin_csrf_exemption` pipeline (`TuistWeb.Plugs.SameOriginCSRFExemptionPlug`), which accepts it when the browser-set `Sec-Fetch-Site` or `Origin` header proves same-origin, and its JSON returns a fresh `csrf_token` for the credential form alongside the nonce. Up to ten pending one-hour challenges support independent browser tabs. The submitted nonce selects and consumes only its matching session challenge before handling the verified identity through the existing sign-in flow. Preserve the Google Workspace hosted-domain claim when building the authentication result.
- Delegate business logic to `server/lib/tuist` contexts.
- Keep the machine-readable auth.md document, discovery metadata, and agent-auth response envelopes synchronized when the protocol surface changes.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`

- Gradle build and Bazel invocation step list/detail routes authorize build-read access and scope the parent to the selected project before querying recorded operations. Their contracts expose timestamp origin and Bazel profile coverage; published Bazel action logs are fetched only for details.

- Command event schemas accept effective destinations and individual subhashes, including embedded products, foreign builds, and UI-test device/runtime inputs. Module-cache responses expose null for unavailable typed inputs and omit unavailable subhashes to preserve the existing string-valued map contract.
- Runner report endpoints accept job-scoped Buildkite and GitLab credentials; billing times are server-observed and log uploads remain bounded.

- Both runner log and finish endpoints select the provider from the verified report-token identity, retaining legacy Buildkite token compatibility.


- Dashboard timeline JSON routes cover Xcode/Gradle build runs and Bazel invocations. Dispatch by the authorized project build system, scope the parent before reading metadata, omit machine samples and logs, and disable caching for every source.

- Gradle timeline metadata requests disable sample-row loading at the source; dropping sample fields only after loading them does not avoid the query cost. Scalar bounds keep metadata aligned with bootstrap.

- `RunnerCacheVolumesController` authenticates the storage agent service account
  through Kubernetes TokenReview. Allocation binds the actual executed Linux job
  to GitHub App run/repository metadata; reports are node-bound. Never accept a
  workflow credential as an agent or user-supplied scope/branch identity.
- Missing cache-volume metadata returns `delete` until the authenticated agent
  reports state `deleted`, then `forget` to release its durable local journal.

- `API.RunnerVolumesController` exposes dashboard volume data and clearing via
  `Runners.CacheVolumes.Query`. Reads require runners-read; clearing requires
  account-update. Keep the runners feature flag and no-store responses. This
  public controller must not expose privileged agent allocation/report methods.

- The internal cache-volume image endpoint shares agent authentication and
  node-bound allocation lookup. It serves download/upload/retain/publication
  decisions using the macOS master protocol; never expose signed URLs publicly.
