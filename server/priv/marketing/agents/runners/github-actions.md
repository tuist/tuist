# Tuist Runners for GitHub Actions: macOS and Linux

Managed macOS and Linux runners for GitHub Actions. Change `runs-on`, keep your workflows, and build next to a shared cache.

Tuist Runners run GitHub Actions jobs on Tuist's fleet; your workflows and triggers stay on GitHub. Runners only run jobs from repositories owned by a GitHub organization, not a personal account.

## Switch a job with one line

Connect your GitHub organization to Tuist, then point `runs-on` at a Tuist [profile](/en/docs-markdown/guides/features/runners/profiles):

```diff
 jobs:
   build:
-    runs-on: macos-latest
+    runs-on: tuist-macos
     steps:
       - uses: actions/checkout@v4
       - run: tuist test
```

No runner agent to install. Accounts start with `tuist-macos` and `tuist-linux` profiles; see the [GitHub Actions guide](/en/docs-markdown/guides/features/runners/ci-providers/github-actions) for the full setup.

## How it differs from GitHub-hosted runners

- **A build cache shared beyond CI.** Runners share the [Tuist cache](/marketing-markdown/cache) with developer machines and coding agents.
- **Directories that survive between jobs.** [Cache volumes](/en/docs-markdown/guides/features/runners/cache-volumes) keep DerivedData and other caches between jobs.
- **Xcode selected by the profile.** Each profile pins one Xcode version, so workflows drop `xcode-select` steps.

## Sources and review

Sources checked on **2026-11-13**. Written by Tuist from its own documentation and the provider's public documentation; not an independent benchmark. Primary sources: [GitHub-hosted runners](https://docs.github.com/en/actions/concepts/runners/github-hosted-runners), [dependency caching](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching), and the Tuist [GitHub Actions setup guide](/en/docs-markdown/guides/features/runners/ci-providers/github-actions).

## Further reading

- [Tuist Runners](/marketing-markdown/runners) for all supported CI providers, machine profiles, and how runners fit with the rest of Tuist.
- Tuist Runners for [GitLab CI](/marketing-markdown/runners/gitlab-ci) and [Buildkite](/marketing-markdown/runners/buildkite).
- [Rising CI costs](/marketing-markdown/solutions/ci-costs) on measuring total cost before and after moving jobs.

## Frequently asked questions

### Do we have to leave GitHub Actions?

No. Workflows, triggers, secrets, and checks stay in GitHub Actions. Only the machine that runs the job changes.

### Which runner labels can we use?

The `tuist-` prefix plus a profile name, such as `tuist-macos`, `tuist-linux`, or `tuist-xcode-26-4` for a profile you create. Matching is case-insensitive.

### Can we keep some jobs on GitHub-hosted runners?

Yes. Each job chooses its runner through `runs-on`, so you can move one job at a time.

### Do Linux runners support Android emulators?

Yes. Linux runners expose `/dev/kvm`, so x86_64 Android emulators and Gradle Managed Devices run without a special profile. See [Android emulators](/en/docs-markdown/guides/features/runners).

### Why not stay on GitHub-hosted runners?

[GitHub-hosted runners](https://docs.github.com/en/actions/concepts/runners/github-hosted-runners) give each job a fresh VM, and [`actions/cache`](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching) keeps per-repository archives (10 GB by default, evicted after 7 days unused). Tuist Runners add a build cache shared with developer machines and coding agents, cache volumes that keep directories between jobs, and Xcode selected by the profile.

### How is it priced?

Runners are billed per minute by machine shape. See the [pricing page](/pricing) for current rates, and compare them against the total cost of the job, not only the per-minute price.
