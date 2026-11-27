# Self-hosted macOS runners: Mac minis for GitHub Actions or managed runners

Tuist runs the Mac mini fleet for you: [Tuist Runners](/marketing-markdown/runners) are managed M5 Pro Mac minis for GitHub Actions and other CI providers, with a fresh virtual machine per job and the build cache in the same rack.

Before buying Mac minis for CI, measure how much of each job repeats work another machine already did. Improve the project first, then its execution environment, whether that environment is your own Macs or Tuist's. Teams usually start self-hosting macOS runners because GitHub's standard macOS runner is small and its minutes are expensive, and a Mac mini under a desk is fast and cheap per minute. The cost that grows later is the fleet: images, Xcode updates, disk cleanup, capacity, and security.

## What self-hosting Mac runners involves

Registering a Mac as a [self-hosted runner](https://docs.github.com/en/actions/concepts/runners/self-hosted-runners) takes minutes. Keeping a fleet fast and safe is ongoing work:

- **Clean environments.** A long-lived runner accumulates DerivedData, simulators, caches, and old toolchains until jobs slow down or fail. GitHub [recommends ephemeral runners](https://docs.github.com/en/actions/reference/runners/self-hosted-runners) that take one job each, which on a Mac means a fresh virtual machine per job and automation to create and destroy it.
- **Virtualization limits.** Apple's [macOS license](https://www.apple.com/legal/sla/docs/macOS27.pdf) (section 2B(iii)) allows up to two additional virtualized copies of macOS per Mac for software development and testing, so a Mac mini runs at most two isolated jobs at a time.
- **Images and Xcode.** Every Xcode release, beta, and simulator runtime has to be built into an image, tested, and rolled out to every machine before a project can move to it.
- **Capacity.** Jobs queue when every Mac is busy and machines sit idle at night. Cloud Macs have their own terms: [EC2 Mac](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-mac-instances.html) runs on Dedicated Hosts with a 24-hour minimum allocation.
- **Caches between ephemeral jobs.** A clean VM per job starts cold unless DerivedData, package caches, and build outputs live outside it.
- **Security.** Runner tokens, signing certificates, and network access sit on machines your team operates; a persistent runner can carry one job's state into the next.

## How Tuist addresses it

- **Project first.** The [Tuist cache](/marketing-markdown/cache) lets CI reuse Xcode compilation outputs that developers, coding agents, and earlier jobs already produced, whichever runners you use, including your own Mac minis. [Build insights](/en/docs-markdown/guides/features/build-insights) show which targets and steps dominate a job before you buy capacity.
- **Managed Mac minis.** Tuist Runners run on M5 Pro Mac minis that Tuist owns and operates. Every job starts in a [fresh virtual machine](/en/docs-markdown/guides/features/runners/images) that is discarded afterwards, so state never leaks between jobs.
- **One Xcode per image.** A [profile](/en/docs-markdown/guides/features/runners/profiles) pins the Xcode version; its image already includes the simulator runtimes and the Metal toolchain, and beta profiles move to new betas without changes on your side.
- **Warm starts without persistent machines.** [Cache volumes](/en/docs-markdown/guides/features/runners/cache-volumes) keep directories such as DerivedData between jobs, and the cache sits on the same private network as the runners.
- **One-line adoption.** Change `runs-on: self-hosted` or `macos-latest` to `runs-on: tuist-macos` in [GitHub Actions](/marketing-markdown/runners/github-actions), or use a tag in [GitLab CI](/marketing-markdown/runners/gitlab-ci) or a queue in [Buildkite](/marketing-markdown/runners/buildkite). There is no runner agent to install.

Runners are billed per minute of job time by machine shape, within account [concurrency limits](/en/docs-markdown/guides/features/runners#concurrency-limits); the current rates are on the [pricing page](/pricing).

## Diagnose

Measure your current setup before deciding to buy, keep, or replace Macs:

| Question | Measure | What it tells you |
| --- | --- | --- |
| Is the job repeating work? | Compilation and cache results per build in [build insights](/en/docs-markdown/guides/features/build-insights) | Whether a shared cache removes minutes on any hardware |
| Are jobs waiting for a Mac? | Queue time between job creation and start | Whether you need more capacity or a better schedule |
| Do jobs slow down over time? | Duration of the same job on a freshly provisioned machine versus a long-lived one | Whether state builds up between jobs |
| What does the fleet cost? | Hardware or rental, hosting, and the hours spent on images, Xcode updates, and incidents each month | The full cost per job minute, not only the hardware |
| How often do Xcode updates block work? | Days between an Xcode release and your fleet running it | The cost of owning images |

## Investigate with an agent

Use the authorized [Tuist MCP server](/en/docs-markdown/guides/features/agentic-coding/mcp) to compare jobs before and after a change. `list_xcode_builds` and `list_xcode_build_targets` show where build time goes; on Tuist Runners, `list_runner_jobs`, `list_runner_job_steps`, and `list_runner_job_metrics` add queue, step, and machine evidence, and `list_runner_profiles` shows the available machines and Xcode versions. Ask for the slowest repeated step and the evidence for one change; reading these records does not authorize changing profiles or workflows.

## First experiment

1. Pick one macOS workflow on your self-hosted runners and record its duration, queue time, and cache results for a week.
2. Connect the project to the [Tuist cache](/marketing-markdown/cache) and rerun the same workflow on the same machines.
3. Point a copy of the job at `tuist-macos` and compare duration, queue time, and cost per job with your fleet's full cost.

## Further reading

- [Tuist Runners](/marketing-markdown/runners) for all supported CI providers and machine profiles.
- [Tuist Runners for GitHub Actions](/marketing-markdown/runners/github-actions), including macOS runner rates compared with GitHub-hosted runners.
- [Rising CI costs](/marketing-markdown/solutions/ci-costs) and [slow builds](/marketing-markdown/solutions/slow-builds).
- [Tuist Runners: going down to the bare metal](/blog/2026/11/04/runners) on why Tuist runs its own Mac and Linux hardware.

## Frequently asked questions

### Can a Mac mini be a GitHub Actions self-hosted runner?

Yes. Install the runner application on the Mac and register it with your repository or organization. For isolated jobs, run each job in a fresh macOS virtual machine; Apple's license allows up to two virtualized copies of macOS per Mac for development and testing.

### Why do self-hosted Mac runners get slower over time?

A long-lived runner keeps DerivedData, simulator data, caches, and toolchains from earlier jobs, so disks fill and builds pick up stale state. Ephemeral virtual machines avoid that; caches then need to live outside the machine so jobs still start warm.

### Is self-hosting Macs cheaper than managed runners?

Per minute of hardware, often yes. The full cost also includes hosting, idle capacity, image and Xcode maintenance, and the engineering time to run the fleet. Compare the full monthly cost per job with managed rates on the [pricing page](/pricing).

### Can we keep our own Macs and still use Tuist?

Yes. The Tuist cache, build insights, and test insights work on any runner, including self-hosted Mac minis. Tuist Runners are optional and can take individual jobs while others stay on your fleet.

### Which Xcode versions do Tuist Runners have?

Each macOS profile pins one Xcode version, and its image includes that Xcode's simulator runtimes and Metal toolchain. The [images guide](/en/docs-markdown/guides/features/runners/images) lists the available versions.

## Sources and review

Sources checked on **2026-11-26**: [GitHub self-hosted runners](https://docs.github.com/en/actions/concepts/runners/self-hosted-runners), [self-hosted runners reference](https://docs.github.com/en/actions/reference/runners/self-hosted-runners), [Apple macOS software license agreement](https://www.apple.com/legal/sla/docs/macOS27.pdf), [Amazon EC2 Mac instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-mac-instances.html), and the Tuist [runner images](/en/docs-markdown/guides/features/runners/images) and [profiles](/en/docs-markdown/guides/features/runners/profiles) guides. Written by Tuist; not an independent benchmark.
