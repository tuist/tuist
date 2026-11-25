# GitLab runners for macOS and Linux, managed by Tuist

Managed GitLab runners for macOS and Linux on GitLab.com and self-managed GitLab. Tag a job to pick the machine, with no runner fleet to operate.

Your pipelines stay in GitLab, and Tuist provides an isolated machine for each tagged job, next to the same build cache your developers and coding agents use.

## Choose the machine with a tag

Create a project or group runner in GitLab with the Tuist profile labels as its tags, connect it once in Tuist with its authentication token, and tag each job:

```yaml
test:
  tags: [tuist-macos]
  script:
    - tuist test
  retry:
    max: 2
    when: runner_system_failure
```

No GitLab Runner to operate. Works with GitLab.com and self-managed GitLab 19.3+ over public HTTPS; see the [GitLab CI guide](/en/docs-markdown/guides/features/runners/ci-providers/gitlab-ci).

## How it differs from GitLab-hosted runners

- **No fleet to operate.** Tuist provides the macOS and Linux machines, images, and Xcode versions.
- **A build cache shared beyond CI.** Runners share the [Tuist cache](/marketing-markdown/cache) with developer machines and coding agents.
- **Directories that survive between jobs.** [Cache volumes](/en/docs-markdown/guides/features/runners/cache-volumes) keep build caches between jobs; forks never save to them.

## Sources and review

Sources checked on **2026-11-25**. Written by Tuist from its own documentation and the provider's public documentation; not an independent benchmark. Primary sources: [GitLab Runner](https://docs.gitlab.com/runner/), [GitLab-hosted runners](https://docs.gitlab.com/ci/runners/hosted_runners/) and the Tuist [GitLab CI setup guide](/en/docs-markdown/guides/features/runners/ci-providers/gitlab-ci).

## Further reading

- [Tuist Runners](/marketing-markdown/runners) for all supported CI providers, machine profiles, and how runners fit with the rest of Tuist.
- Tuist Runners for [GitHub Actions](/marketing-markdown/runners/github-actions) and [Buildkite](/marketing-markdown/runners/buildkite).
- [Rising CI costs](/marketing-markdown/solutions/ci-costs) on measuring total cost before and after moving jobs.

## Frequently asked questions

### What is a GitLab runner?

A [GitLab runner](https://docs.gitlab.com/runner/) is the agent that picks up CI/CD jobs from GitLab and runs them on a machine. GitLab offers hosted runners for GitLab.com and GitLab Dedicated, or you install GitLab Runner on your own machines and choose an executor, such as shell or Docker. Tuist Runners replace that self-managed fleet: GitLab sends jobs tagged with a Tuist profile to an isolated Tuist machine.

### Do we have to leave GitLab CI?

No. Pipelines, variables, artifacts, and logs stay in GitLab. Tuist only provides the machine for jobs tagged with a Tuist profile.

### Does it work with self-managed GitLab?

Yes, for GitLab 19.3 or newer reachable over public HTTPS. [GitLab-hosted runners](https://docs.gitlab.com/ci/runners/hosted_runners/) cover GitLab.com and GitLab Dedicated, with macOS still in beta, so self-managed teams often run their own fleet; Tuist Runners serve both GitLab.com and reachable self-managed instances.

### What happens when we reach our concurrency limit?

Jobs Tuist has already acquired wait for a machine for up to their job timeout, at most 12 hours, and further jobs stay pending in GitLab. A job that never gets a machine fails with `runner_system_failure`, which a retry policy can handle.

### Where are the runner tokens kept?

The reusable runner authentication token stays encrypted on the Tuist server. Machines receive credentials for their assigned job only.

### Can jobs use `image:` and `services:`?

No. Jobs use GitLab's shell executor inside the isolated machine, so `image:` and `services:` do not configure the environment; use the tools on the runner image or install them in your script.

### How is it priced?

Runners are billed per minute by machine shape. See the [pricing page](/pricing) for current rates.
