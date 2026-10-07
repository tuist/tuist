# Controllers (Web Layer)

This area owns Phoenix controllers for HTML and API endpoints.

## Responsibilities
- `MarketingMarkdownController` serves landing-page guides and original legal documents at `/marketing-markdown[/<page>]`, plus full original static statements at `/marketing-markdown/source/<page>`, without sessions or language redirects. Unknown paths return uncacheable 404s; preserve on-premise forwarding and public marketing classification.
- `ProjectSitemapController` serves a sitemap index and bounded public-project root pages. Select only public handles and disable caching to reflect visibility changes; never enumerate private records, settings, or unbounded build histories.
- Standalone documentation and error documents use `LayoutComponents.head_analytics_scripts`, like the shared page layouts.
- Stripe customer updates acknowledge customers without a matching account, as subscription updates do. Keep failures updating an existing account visible so Stripe can retry delivery.
- Cache endpoint discovery resolves retained account handles through `Kura.Identity` and still authorizes the caller against the owning account before using its current name. Mesh responses carry current handles, retained aliases and activated endpoint redirect targets; do not treat a historical handle as authorization.
- Deployment-credential mesh registration and peer discovery require the permanent Kura tenant. After credential verification, a retained/current handle that differs from that tenant yields 409 `tenant_mismatch` with `expected_tenant_id`, never a successful registration under another storage namespace. Invalid credentials and unknown tenants remain generic 401 responses. Keep the self-host guide and regression coverage aligned with this distinction.
- `BuildController.timeline/2` returns full build step metadata without logs, scoped to the authorized project/build. Bandit negotiates HTTP compression; the response uses `private, no-store`.
- Handle request/response flow and rendering for controller actions.
- Open Graph project images recheck project identity and public visibility before storage reads or 304 responses. Use `no-cache` even for transient project cards; marketing/docs images remain immutable. Store project cards in their own retention prefix.
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


- Dashboard timeline JSON routes cover Xcode/Gradle/Mix build runs and Bazel invocations. Dispatch by the authorized project build system, scope the parent before reading metadata, omit machine samples and logs, and disable caching for every source.

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

- `RunnerCacheMastersController.report_usage` accepts only the per-machine
  `tuist-runner-host` audience, derives the node from its ServiceAccount, and
  delegates session/job binding to `CacheVolumes.Builtin`. Workflow tokens and
  body-supplied account/node/repository fields cannot authorize these reports.
