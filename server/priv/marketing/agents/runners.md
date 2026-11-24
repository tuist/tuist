# Tuist Runners: managed macOS and Linux CI runners

Tuist Runners are managed macOS and Linux CI runners for GitHub Actions, GitLab CI, Buildkite, and Bitrise. You keep your CI provider and pipelines and change one line to run a job on Tuist's fleet, next to the same build cache your team's machines and coding agents already share. Runners are available to every Tuist account.

## Why teams move CI jobs to Tuist Runners

- **One-line adoption.** Swap `runs-on: macos-latest` for `runs-on: tuist-macos` in GitHub Actions, a tag in GitLab CI, or a queue in Buildkite. There is no runner agent to install.
- **A cache on the same network.** Runners sit next to the [Tuist cache](/marketing-markdown/cache), which developer machines, coding agents, and CI share, so outputs built elsewhere are hits on the runner. [Cache volumes](/en/docs-markdown/guides/features/runners/cache-volumes) also keep directories such as DerivedData and Gradle caches between jobs.
- **No fleet to maintain.** Tuist manages machines, images, and Xcode and macOS updates. Jobs run within account concurrency limits and queue only when they would exceed them.
- **Machines sized for the job.** Choose a macOS or Linux [machine profile](/en/docs-markdown/guides/features/runners/profiles) by CPU, memory, and Xcode version. Linux runners include KVM for x86_64 Android emulators.
- **Job evidence in one place.** Job records sit next to reported build performance, cache activity, and machine metrics. Log and step visibility depends on the CI integration.

## Runners for your CI provider

- [GitHub Actions](/marketing-markdown/runners/github-actions): change `runs-on` to a Tuist profile.
- [GitLab CI](/marketing-markdown/runners/gitlab-ci): tag jobs with a Tuist profile, on GitLab.com or self-managed GitLab.
- [Buildkite](/marketing-markdown/runners/buildkite): target a queue named after a Tuist profile.
- Bitrise: pair a self-hosted runner pool with a Tuist profile; see the [Bitrise guide](/en/docs-markdown/guides/features/runners/ci-providers/bitrise).

## Choose an approach

| Approach | Good fit | Tradeoff |
| --- | --- | --- |
| Tuist Runners | Managed macOS and Linux CI machines next to a shared cache, without maintaining a fleet. | Account concurrency limits apply. |
| CI provider's hosted runners | Simple setup with the runners your provider already offers. | No colocated cache shared with developer machines and agents. |
| Self-hosted runners | Full control over hardware and network. | You maintain machines, images, toolchains, and capacity. |
| Optimize the project first | Expensive or repeated work dominates job time. | Fix the project before assuming new machines will solve it. |

## Project first, runners second

Faster machines do not remove unnecessary work, so improve the project before changing its execution environment. Inspect invalidation, expensive operations, and repeated work with [Build Insights](/en/docs-markdown/guides/features/build-insights), [Cache](/marketing-markdown/cache), and [Tests](/marketing-markdown/tests). These do not require moving jobs to Tuist Runners.

Connect the provider using the [Runners guide](/en/docs-markdown/guides/features/runners), choose a profile, and move one representative job. Current shapes and versions are listed in the dashboard.

## Questions before you start

### Does this replace our CI?

No. Keep the CI provider, pipelines, and triggers. Tuist Runners only execute the jobs you point at a Tuist profile.

### Which CI providers are supported?

GitHub Actions, GitLab CI, Buildkite, and Bitrise, plus an API for other forges and orchestrators. See the [Runners guide](/en/docs-markdown/guides/features/runners).

### Can we adopt it incrementally?

Yes. Move one job and compare it against the existing runner before expanding. Cache and insights can be adopted independently.

### Hosted or self-hosted?

Tuist Runners are a managed service. [Self-hosting Tuist's server](/en/docs-markdown/guides/server/self-host/server) is a separate deployment choice and does not grant access to the managed fleet.

### How do we measure value?

Compare queue time, end-to-end duration, cache transfer time, total machine usage, and fleet-maintenance effort for the same job. Include [Tuist charges](/pricing) and remaining CI-provider costs. Faster machines alone do not prove savings; check current commercial terms rather than assuming a published rate applies to the account.
