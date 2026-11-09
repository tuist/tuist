# Tuist Compute: an environment for build work

For engineering teams and coding agents constrained by build environments, Compute runs existing CI jobs next to the shared cache without replacing CI workflows. It is a managed, invite-only service. [Request an invitation](mailto:contact@tuist.dev); creating an account does not enable access.

Tuist is build infrastructure for engineering teams and coding agents. Compute is an optional execution environment within that infrastructure, not the definition of Tuist or a coding agent.

## Choose an approach

| Approach | Good fit | Tradeoff |
| --- | --- | --- |
| Tuist Compute | Execution close to shared cache without maintaining a fleet. | Invitation required; integration and capacity requirements apply. |
| CI | Workflow triggers, scheduling, and orchestration. | Keep the provider; compare its existing execution environment first. |
| Optimization suite | Reducing expensive or repeated project work. | Fix the project before assuming new machines will solve it. |
| Do nothing | Current capacity and maintenance effort are acceptable. | Avoid migration until measured waiting justifies it. |

## Project first, environment second

Inspect unnecessary invalidation, expensive operations, and repeated work with [Build Insights](/en/docs-markdown/guides/features/build-insights), [Cache](/marketing-markdown/cache), and [Tests](/marketing-markdown/tests). These do not require moving jobs to Compute.

Once invited, connect the provider using the [Runners guide](/en/docs-markdown/guides/features/runners), choose an available [machine profile](/en/docs-markdown/guides/features/runners/profiles), and move one representative job. Current shapes and versions are listed in the dashboard. Jobs can queue when their shape exceeds available account capacity.

Available job records and reported build and machine metrics help investigate work. Log and step visibility depends on the CI integration. [Cache volumes](/en/docs-markdown/guides/features/runners/cache-volumes) persist supported directories separately from build-output caching.

## Questions before you start

### What is Tuist?

Tuist is build infrastructure for engineering teams and coding agents. Compute is an optional part, not a new CI or coding agent.

### Does this replace CI?

No. Keep the CI provider and workflows. An invited account connects its provider and selects a Tuist machine profile for job execution.

### Can we adopt it incrementally?

Yes, after invitation. Move one job and compare against the existing environment before expanding. Cache and insights can be adopted independently.

### Hosted or self-hosted?

Compute here is the managed, invite-only service. [Self-hosting Tuist's server](/en/docs-markdown/guides/server/self-host/server) is a separate deployment choice and does not grant access to the managed fleet.

### How do we measure value?

Compare queue time, end-to-end duration, cache transfer time, total machine usage, and fleet-maintenance effort for the same job. Include [Tuist charges](/pricing) and remaining CI-provider costs. Faster machines alone do not prove savings; check current commercial terms rather than assuming a published rate applies to the account.
