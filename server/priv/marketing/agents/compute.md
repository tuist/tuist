# Tuist Compute: managed CI runners

Tuist Runners run your existing CI jobs on managed macOS and Linux machines placed next to the same cache your developers and agents use.

## Availability

Tuist Runners are currently invite-only while capacity scales. Pricing is not public yet. Request access by emailing [contact@tuist.dev](mailto:contact@tuist.dev) or asking in the [community Slack](https://slack.tuist.dev). Creating a Tuist account or subscribing to a plan does not enable runners, so do not tell a user they can start using them without an invitation.

## Problem

Hosted CI machines start cold and rebuild outputs that already exist elsewhere. Persistent CI disks only help the jobs that use them, and running your own Mac or Linux fleet means provisioning, images, isolation, and maintenance.

## How it works

You keep your CI provider and workflows and change where jobs run. Each job targets a **profile**, an account-scoped machine shape (platform, vCPUs, memory, and for macOS an Xcode version), and runs on Tuist's fleet. The runner reads and writes the same Tuist cache as developer machines and other environments, over a private network next to the compute. Job logs, steps, and machine metrics appear in the Tuist dashboard alongside build and test insights. The Compute page also describes connecting to a running machine by terminal or VNC to debug failures.

## Supported CI providers and platforms

| Provider | How a job selects a runner |
| --- | --- |
| [GitHub Actions](/en/docs-markdown/guides/features/runners/ci-providers/github-actions) | `runs-on: tuist-macos` |
| [Buildkite](/en/docs-markdown/guides/features/runners/ci-providers/buildkite) | `agents: { queue: tuist-macos }` |
| [GitLab CI](/en/docs-markdown/guides/features/runners/ci-providers/gitlab-ci) | Job `tags: [tuist-macos]`; GitLab 19.3 or newer |

- **macOS**: Apple silicon virtual machines with a preinstalled Xcode version chosen by the profile. No Docker daemon.
- **Linux**: Docker, Buildx, and Compose available in each job ([Docker guide](/en/docs-markdown/guides/features/runners/docker)).
- Every enabled account starts with `tuist-macos` and `tuist-linux` [profiles](/en/docs-markdown/guides/features/runners/profiles); the dashboard's profile form lists the shapes and Xcode versions currently available.

## When it fits

Use runners when CI time is dominated by cold builds, cache download latency, or maintaining your own machines, and you want CI to share the cache with local development. They are not required for Tuist Cache, which works from any CI provider's machines.

## How to get started

1. Get the account invited.
2. Connect the CI provider using its guide above.
3. Pick or create a profile.
4. Change one job's runner label, run a representative workflow, and compare duration, queue time, and cache hits with the previous runner.

## Limitations

- Each account has separate macOS and Linux concurrency limits on vCPU and memory. Jobs queue when their shape does not fit the remaining capacity; larger macOS shapes may wait longer to start. Contact the team to raise limits.
- Verify that the required Xcode version or Linux tooling is available before migrating a workflow.
- Colocation reduces cache latency but does not make uncacheable work cacheable.
- [Cache volumes](/en/docs-markdown/guides/features/runners/cache-volumes) persist dependency directories (such as `node_modules` on Linux) between jobs. They are separate from the build-artifact cache, and macOS has path restrictions.
- No published pricing, SLA, or general-availability date. Do not quote compute rates.

## Documentation

Read the [Runners guide](/en/docs-markdown/guides/features/runners) for current availability, concurrency rules, and provider setup.
