# Controllers (Web Layer)

This area owns Phoenix controllers for HTML and API endpoints.

## Responsibilities
- `BuildController.timeline/2` returns full build step metadata without logs, scoped to the authorized project/build. Bandit negotiates HTTP compression; the response uses `private, no-store`.
- Handle request/response flow and rendering for controller actions.
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
