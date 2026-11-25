# Xcode Cloud vs Tuist: pricing model, machine types, and macOS runners

Choose Tuist for macOS runners with published machine sizes, a shared Xcode cache, and test insights in your current CI. How it compares with Xcode Cloud.

Xcode Cloud is Apple's continuous integration and delivery service, built into Xcode and App Store Connect. Tuist is build infrastructure for engineering teams and coding agents: managed macOS and Linux [runners](/marketing-markdown/runners) for GitHub Actions, GitLab CI, Buildkite, and Bitrise, plus a [cache](/marketing-markdown/cache) and [test insights](/marketing-markdown/tests) that work alongside the CI you use. Optimize the project first, then its execution environment.

## What overlaps

[Xcode Cloud](https://developer.apple.com/xcode-cloud/) builds, tests, analyzes, and archives Apple-platform apps from GitHub, GitLab, or Bitbucket, including self-managed instances, as Apple's [setup requirements](https://developer.apple.com/documentation/xcode/setting-up-your-project-to-use-xcode-cloud) list. Results appear in Xcode and App Store Connect, and post-actions deliver builds to TestFlight and App Store Connect. That delivery integration is its strength, and Tuist doesn't replace it: Tuist Runners run the jobs of the CI you already use, and signing and publishing stay in that workflow.

Both reuse earlier work. According to Apple's [workflow reference](https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference), Xcode Cloud stores each build's derived data for reuse, and workflows that distribute to external TestFlight testers need a clean build, which Apple says takes significantly longer. Tuist's [Xcode cache](/en/docs-markdown/guides/features/cache/xcode-cache) shares Xcode 26+ compilation outputs between CI, developer machines, and coding agents, and [cache volumes](/en/docs-markdown/guides/features/runners/cache-volumes) keep directories between jobs on Tuist Runners.

## Machine types

| | Tuist Runners | Xcode Cloud |
| --- | --- | --- |
| macOS hardware | Apple silicon (arm64) virtual machines on macOS 26 Tahoe | Ephemeral virtual machines run by Apple; Apple's documentation doesn't name the chip or list CPU or memory sizes |
| macOS sizes | 8 vCPU / 24 GB (default) or 16 vCPU / 48 GB, chosen per [profile](/en/docs-markdown/guides/features/runners/profiles) | Not selectable in the workflow settings Apple documents |
| Xcode versions | One Xcode per image, chosen per profile; Xcode 26.0.1 through 27.3 beta at review time | Xcode and macOS versions chosen per workflow from Apple's list; Apple retires older versions in its [release notes](https://developer.apple.com/xcode-cloud/release-notes/) |
| Linux | x86_64 shapes from 1 vCPU / 2 GB to 16 vCPU / 64 GB, Ubuntu 24.04 or 22.04, with KVM for Android emulators | Apple's documentation describes macOS build environments for Apple platforms |
| Preinstalled tools | Xcode, simulator runtimes, the Metal toolchain, and more, listed in [Images](/en/docs-markdown/guides/features/runners/images) | Tools that ship with macOS and Xcode, plus Homebrew and CocoaPods; custom scripts can't use `sudo` |

The catalog of Tuist shapes and Xcode versions changes as hardware and Xcode releases arrive; the dashboard and `tuist runner profile catalog` show what's available to an account.

## Pricing model

Xcode Cloud bills compute hours. Apple Developer Program membership includes 25 compute hours a month, and paid [monthly plans](https://developer.apple.com/xcode-cloud/get-started/) raise that to 100, 250, 1,000, or 10,000 hours. Usage counts the time of each task, not the build's wall-clock time: in Apple's example, five 12-minute tests use one compute hour, and because Xcode Cloud runs steps in parallel, [reported usage and build duration differ](https://developer.apple.com/documentation/xcode/reviewing-xcode-cloud-usage-data). Unused hours don't roll over to the next month. Check Apple's page for current prices.

Tuist Runners are billed per minute by machine shape, so a larger shape costs more per minute and can finish CPU-bound jobs sooner. Current rates are on the [pricing page](/marketing-markdown/pricing). Compare total cost on the same jobs, not a unit rate: work the cache avoids costs nothing on either service.

## Choose Tuist when

You want to know and choose the machine a job runs on, need Linux jobs or Android emulators next to iOS builds, or want CI to share build results with developers and coding agents instead of only with the next build of the same workflow. Tuist also fits when your team keeps GitHub Actions, GitLab CI, Buildkite, or Bitrise and wants faster macOS jobs without moving pipelines.

You can also keep Xcode Cloud and run Tuist in it. The [continuous integration guide](/en/docs-markdown/guides/integrations/continuous-integration) shows a post-clone script that installs Tuist, runs commands such as `tuist generate`, and authenticates with an account token. The Xcode cache's setup starts a local cache service on the machine, so try it in one Xcode Cloud build before relying on it. Apple requires a consistent project or workspace that's present in the repository, and warns that tools that generate or edit it during a build can make configuration fail, so check generated projects early.

## First experiment

Pick one Xcode workflow and record its duration, compute hours, and test results on Xcode Cloud. Run the same scheme on a [Tuist Runner](/en/docs-markdown/guides/features/runners) with the default 8 vCPU / 24 GB shape and the same Xcode version, with the [Tuist Xcode cache](/en/docs-markdown/guides/features/cache/xcode-cache) enabled. Run it twice, then try the 16 vCPU shape if the job is CPU-bound, and compare wall-clock time and total cost for the month's runs.

## Frequently asked questions

### How much does Xcode Cloud cost?

Apple Developer Program membership includes 25 compute hours a month. Paid monthly plans raise that to 100, 250, 1,000, or 10,000 hours; Apple's [get started page](https://developer.apple.com/xcode-cloud/get-started/) lists current prices. Hours count the time of each task, so five 12-minute tests use one hour even when they run in parallel, and unused hours don't roll over to the next month.

### What machines does Xcode Cloud use?

Apple describes ephemeral virtual machines with the Xcode and macOS versions you pick per workflow, but its documentation doesn't name the chip or list CPU or memory sizes. Tuist Runners publish theirs: Apple silicon macOS virtual machines with 8 vCPU / 24 GB or 16 vCPU / 48 GB, and Linux shapes up to 16 vCPU / 64 GB.

### Can I use Tuist with Xcode Cloud?

Yes. Install Tuist in a post-clone script, run the commands you need, such as `tuist generate`, and set `TUIST_TOKEN` to an account token in the workflow's environment, as the [continuous integration guide](/en/docs-markdown/guides/integrations/continuous-integration) shows. Tuist Runners themselves run jobs for GitHub Actions, GitLab CI, Buildkite, and Bitrise, not Xcode Cloud workflows.

### Does Xcode Cloud cache builds?

Yes. Xcode Cloud stores each build's derived data for reuse unless a workflow uses a clean build, which external TestFlight distribution requires. That cache serves later Xcode Cloud builds; Tuist's Xcode cache also shares compilation outputs with developer machines and coding agents.

## Sources and review

Sources checked on **2026-11-25**: [Xcode Cloud overview](https://developer.apple.com/xcode-cloud/), [get started and plans](https://developer.apple.com/xcode-cloud/get-started/), [getting started guide](https://developer.apple.com/documentation/xcode/getting-started-with-xcode-cloud), [usage data](https://developer.apple.com/documentation/xcode/reviewing-xcode-cloud-usage-data), [setup requirements](https://developer.apple.com/documentation/xcode/setting-up-your-project-to-use-xcode-cloud), [workflow reference](https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference), [dependencies and preinstalled tools](https://developer.apple.com/documentation/xcode/making-dependencies-available-to-xcode-cloud), [release notes](https://developer.apple.com/xcode-cloud/release-notes/), and Tuist's [runner profiles](/en/docs-markdown/guides/features/runners/profiles) and [images](/en/docs-markdown/guides/features/runners/images). Written by Tuist; it describes the documented mechanisms, not benchmarks or every feature of either service.

Related: [Bitrise](/marketing-markdown/compare/bitrise), [Codemagic](/marketing-markdown/compare/codemagic), [rising CI costs](/marketing-markdown/solutions/ci-costs), and [all comparisons](/marketing-markdown/compare).
