# Tuist Runners for Buildkite: macOS and Linux agents

Tuist Runners are managed M5 Pro Mac mini and Linux machines for Buildkite queues. Keep your pipelines, drop the agent fleet, and build next to a shared cache.

Tuist watches self-hosted queues in your Buildkite cluster and runs their jobs on its fleet of Apple silicon Mac minis and x86-64 Linux machines, billed per minute, next to the same build cache your developers and coding agents use.

## Target a queue named after a profile

Create a cluster agent token in Buildkite, connect it in Tuist, create self-hosted queues keyed after Tuist profiles, and target one from a step:

```diff
 steps:
   - label: "Test"
     command: tuist test
     agents:
-      queue: macos
+      queue: tuist-macos
```

No Buildkite agent to install and no API token needed: logs ship with a job-scoped credential. See the [Buildkite guide](/en/docs-markdown/guides/features/runners/ci-providers/buildkite).

## How it differs from your current agents

- **No fleet to operate.** Tuist provides the machines; pick a [profile](/en/docs-markdown/guides/features/runners/profiles) by CPU, memory, and Xcode or Ubuntu version.
- **A build cache shared beyond CI.** Runners share the [Tuist cache](/marketing-markdown/cache) with developer machines and coding agents.
- **Directories that survive between jobs.** [Cache volumes](/en/docs-markdown/guides/features/runners/cache-volumes) keep build caches between jobs.

## Sources and review

Sources checked on **2026-11-13**. Written by Tuist from its own documentation and the provider's public documentation; not an independent benchmark. Primary sources: [Buildkite hosted agents](https://buildkite.com/docs/pipelines/hosted-agents) and the Tuist [Buildkite setup guide](/en/docs-markdown/guides/features/runners/ci-providers/buildkite).

## Further reading

- [Self-hosted macOS runners](/marketing-markdown/solutions/self-hosted-mac-runners) on running your own Mac minis compared with managed runners.
- [Tuist Runners](/marketing-markdown/runners) for all supported CI providers, machine profiles, and how runners fit with the rest of Tuist.
- Tuist Runners for [GitHub Actions](/marketing-markdown/runners/github-actions) and [GitLab CI](/marketing-markdown/runners/gitlab-ci).
- [Rising CI costs](/marketing-markdown/solutions/ci-costs) on measuring total cost before and after moving jobs.

## Frequently asked questions

### Do we have to leave Buildkite?

No. Pipelines, scheduling, and the Buildkite UI stay as they are. Only the machines for Tuist queues change.

### Can we mix Tuist queues with our own agents?

Yes. Tuist only serves queues keyed after its profiles; other queues keep using your agents.

### Which machines are available?

macOS on Apple silicon and Linux, in the shapes your account's profiles allow. The dashboard and `tuist runner profile catalog` show the current catalog.

### Why not run our own Mac agents?

Buildkite pipelines run on [Buildkite hosted agents or agents you operate](https://buildkite.com/docs/pipelines/hosted-agents). Running your own Mac agents means maintaining machines, images, and Xcode upgrades. Tuist Runners keep Buildkite as the orchestrator and take over the machines. The guide to [self-hosted macOS runners](/marketing-markdown/solutions/self-hosted-mac-runners) compares the two in detail.

### Can we pause a queue?

Yes. Pausing dispatch on a queue stops Tuist taking new jobs from it; running jobs are unaffected.

### How is it priced?

Runners are billed per minute by machine shape. See the [pricing page](/pricing) for current rates.
