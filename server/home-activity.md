# Companion Home activity

Home complements recent previews with three small, independently loaded sections. Each endpoint returns at most three items, newest first, from a rolling seven-day window on the server's clock:

- `GET /api/projects/:account_handle/:project_handle/home/build-failures`
- `GET /api/projects/:account_handle/:project_handle/home/test-failures`
- `GET /api/projects/:account_handle/:project_handle/home/flaky-tests`

## Meaning and support

Build failures use the existing native sources' run timestamps and terminal failure outcomes. Known Gradle start times determine both the window and ordering; legacy Gradle reports without a start time retain the source's report-time fallback. Xcode, Gradle, Bazel, and Once are supported; Bazel and Once are restricted to build commands/runs rather than test invocations. Cargo and Mix build feeds are not yet supported.

Test failures are failed runs from the shared Tests domain, ordered by `ran_at`. Once uses a separate run domain and is not yet supported by this section.

New flaky tests are **currently flaky** test cases whose latest flaky-state event is `marked_flaky` within the window. A later `unmarked_flaky` excludes the test. A new flaky episode after an unmark qualifies again. Last-run timestamps and flaky-run statistics do not establish when a test became flaky. The query reads project-scoped state events within the window, not an unbounded event history; any later unmark that resolves a recent mark is necessarily within the same window. Once's separate test domain is not yet supported.

These are historical outcomes, not a claim that failures are unresolved or that telemetry is complete. Empty means no matching reports, not proof of project health. The endpoints do not expose totals or pagination. Full details and existing authorized controls remain on the web dashboard; native clients only open and share links, with no CI retry integration.

## Response and authorization

A successful response is `{"items": [...]}`. Every item has string `id`, `title`, and `subtitle`, integer `occurred_at` in Unix seconds (int64), and a `url` dashboard path. The path is **relative to the deployment**, such as `/owner/project/tests/test-runs/id`, regardless of the endpoint's configured mount path. Clients append it to the complete session server URL, including its port and base path, rather than resolving it against the host root. They reject absolute/foreign URLs, other-project paths, traversal, query strings, and fragments. Links contain no credentials.

The existing resource loader and build-read or test-read authorization run before querying. Public/private project policy remains unchanged. Successful and unsupported responses use `Cache-Control: private, no-store`. Unsupported build systems return `422`, not an empty success; forbidden access remains `403` with the existing authorization rate limit.

## Compatibility and state

Old servers may return `404`, HTML, or another error. Native clients show activity as unavailable, keep project switching and recent previews usable, and do not infer support from `/.well-known/tuist` release strings. A failed section must not block successful siblings or discard previously loaded rows. Refresh and explicit retry recover errors without background polling or retry loops. Project changes hide mismatched content immediately and reject late responses and errors, including stale authentication errors.

The API reads existing data only. It adds no collection, database columns, object storage, or retention policy. Apple clients share `TuistHome` state/UI; Android uses the generated `HomeApi` through its normal authenticated Retrofit client. Regenerate the shared OpenAPI specification and Swift client with `mise run generate-api-cli-code` from `server/`; do not edit generated files by hand.
