# Bazel on GitHub Actions: caching, remote execution, and setup

Tuist makes Bazel on GitHub Actions fast by giving every ephemeral runner a shared remote cache and recording each invocation, so jobs reuse actions that developers and earlier jobs already ran. Improve the project first, then its execution environment: connect the workspace with `tuist bazel setup`, authenticate with GitHub's OIDC token instead of a stored secret, and use the recorded invocations to find what still runs on every job.

Tuist is build infrastructure for engineering teams and coding agents. It works with the GitHub-hosted or self-hosted runners you already use and does not replace GitHub Actions.

## Why Bazel is slow on GitHub Actions

Bazel avoids work by remembering it: an in-memory server keeps the analyzed build graph, the output base and disk cache keep action results, and the repository cache keeps downloaded dependencies. A [GitHub-hosted runner is a new virtual machine](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) for every job, so all of that starts empty. Bazel's own [remote caching guide](https://bazel.build/remote/caching) notes that in CI the server's in-memory state is lost and must be rebuilt every time.

Teams usually try one of three fixes:

- **Save Bazel's directories in the Actions cache.** [setup-bazel](https://github.com/bazel-contrib/setup-bazel) can store the disk cache, repository cache, and external repositories with the GitHub Actions cache. That cache is [10 GB per repository by default](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching), evicts entries unused for seven days, and is scoped by branch: a pull request can restore caches from its base and the default branch, but not from sibling branches. A Bazel disk cache also [grows until a garbage-collection limit is set](https://bazel.build/remote/caching), and restoring a large archive costs time on every job.
- **Use a bigger runner.** [Larger runners](https://docs.github.com/en/actions/reference/runners/larger-runners) add cores, which helps parallel actions. A cold graph on a bigger machine still re-executes every action, and the standard private-repository runner has 2 CPUs.
- **Use a remote cache.** Bazel looks up each action by its inputs in a shared cache over the [Remote Execution API](https://github.com/bazelbuild/remote-apis) and downloads results instead of running them. Hits work across branches, runners, and developer machines, and with Bazel 7+ [Build without the Bytes](https://blog.bazel.build/2023/12/11/bazel-7-release.html) downloads only the outputs a job needs.

The directory cache and a remote cache are different mechanisms. Saving directories moves a whole cache in and out of each job. A remote cache transfers only the results of matching actions.

## How Tuist addresses it

- **Shared remote cache for every runner.** The [Tuist Bazel cache](/en/docs-markdown/guides/features/cache/bazel-cache) serves Bazel's remote cache protocol. Runners, developers, and coding agents read and write the same action results, outside the Actions cache's size limit and branch scoping.
- **Secretless authentication.** On GitHub Actions, the Tuist CLI exchanges the job's [OIDC token](/en/docs-markdown/guides/server/authentication) for short-lived Tuist credentials once the repository is connected to the project and the job grants `id-token: write`. Nothing long-lived is stored in repository secrets.
- **Build and test insights.** [Bazel build insights](/en/docs-markdown/guides/features/build-insights/bazel) records each invocation's actions, critical path, and cache behavior through Bazel's Build Event Service, and [Bazel test insights](/en/docs-markdown/guides/features/test-insights/bazel) tracks test cases across runs, so a slow job shows which targets and actions dominated it.
- **Remote execution.** `tuist bazel setup --remote-execution` sends Bazel actions to Tuist's Linux executors, so a 2-CPU runner can keep many actions in flight instead of compiling everything itself. Setup raises `--jobs` to match the remote capacity.

## Set up Bazel on GitHub Actions with Tuist

Connect the workspace once from a developer machine with `tuist init` or `tuist bazel setup`, commit `tuist.toml` and the `try-import %workspace%/.bazelrc.tuist` line in `.bazelrc`, and ignore `.bazelrc.tuist`. Connect the GitHub repository to the Tuist project as the [GitHub integration guide](/en/docs-markdown/guides/integrations/gitforge/github) describes. Then run setup in each job, so the generated file matches the runner:

```yaml
name: Bazel
on:
  pull_request:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: jdx/mise-action@v2 # pin tuist in mise.toml
      - run: tuist bazel setup
      - run: bazel test //...
```

GitHub's Ubuntu images [include Bazelisk](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md), which reads `.bazelversion`. The Tuist CLI runs on Linux [through mise](/en/docs-markdown/guides/install-tuist). Tuist 4.218.0 and later exchange the OIDC token on the first request; earlier versions need `tuist auth login` before setup. The [CI guide](/en/docs-markdown/guides/integrations/continuous-integration) covers other providers and token-based authentication.

You can keep setup-bazel's repository cache for dependency downloads alongside the Tuist remote cache. When the remote cache serves action results, a large saved disk cache mostly adds restore and upload time; measure both before keeping it.

## Diagnose

Compare the same commit and job on a cold and a repeat run. Separate queue time, Bazel startup and analysis, dependency fetching, action execution, and cache transfers.

| Symptom | First investigation | Reference |
| --- | --- | --- |
| Every job rebuilds unchanged targets | Action-cache hit rate per invocation and the inputs that differ between runs, such as embedded timestamps, absolute paths, or environment variables. | [Bazel cache](/en/docs-markdown/guides/features/cache/bazel-cache) |
| Jobs spend minutes before the first action | Analysis and dependency fetching; check the repository cache and external downloads. | [Bazel build insights](/en/docs-markdown/guides/features/build-insights/bazel) |
| Cache hits are high but jobs stay slow | Download volume, critical path, and actions that are never cacheable, such as tests tagged `no-cache` or `external`. | [Bazel build insights](/en/docs-markdown/guides/features/build-insights/bazel) |
| Pull requests are slower than `main` | Whether pull-request jobs reach the same cache and configuration as `main`, and flags that change between jobs. | [Bazel cache](/en/docs-markdown/guides/features/cache/bazel-cache) |
| Some tests fail intermittently | Cross-run history before adding retries. | [Bazel test insights](/en/docs-markdown/guides/features/test-insights/bazel) |

A different `--config`, compilation mode, or toolchain changes action keys, so jobs that build the same code with different flags do not share results.

## Investigate with an agent

Connect the [Tuist MCP server](/en/docs-markdown/guides/features/agentic-coding/mcp) and ask your coding agent to compare a slow job with a fast one. `list_bazel_invocations` filters invocations by branch, commit, and `is_ci`, and `get_bazel_invocation` returns build metrics, the execution timeline, critical-path diagnostics, and remote-cache totals. Ask for the actions that missed the cache, the input that changed, and one proposed fix with a before/after measurement.

The MCP credential does not authenticate Bazel's remote services; the agent should follow `get_bazel_integration_guide` before editing the Bazel integration. Reading evidence does not authorize changes: review proposals before applying them.

## First experiment

1. Run `tuist bazel setup` in one workflow on a branch, keeping the existing job as the baseline.
2. Run the job twice on the same commit, then once on a small change.
3. Compare wall-clock time, action-cache hit rate, download volume, and total runner minutes in [Bazel build insights](/en/docs-markdown/guides/features/build-insights/bazel).
4. Build the same commit on a developer machine and check that it reuses the CI results.

## Further reading

- [Bazel with Tuist](/marketing-markdown/build-systems/bazel) on what Tuist adds to Bazel.
- [Remote caching for Bazel](/blog/2026/09/09/bazel) on how the cache works.
- [BuildBuddy](/marketing-markdown/compare/buildbuddy) and [EngFlow](/marketing-markdown/compare/engflow) comparisons, and the [slow builds](/marketing-markdown/solutions/slow-builds) and [rising CI costs](/marketing-markdown/solutions/ci-costs) guides.

## Frequently asked questions

### How do I cache Bazel on GitHub Actions?

There are two options. setup-bazel saves Bazel's disk and repository caches with the GitHub Actions cache, which is limited to 10 GB per repository by default and scoped by branch. A remote cache, such as Tuist's, lets Bazel fetch individual action results from a shared service that every branch, runner, and developer machine uses. Many teams keep the repository cache in the Actions cache and use a remote cache for action results.

### Do I need to store a Tuist token in GitHub secrets?

No. Connect the repository to your Tuist project and grant the job `id-token: write`. The Tuist CLI exchanges GitHub's OIDC token for short-lived credentials.

### Should pull requests write to the remote cache?

Bazel's [remote caching guide](https://bazel.build/remote/caching) recommends limiting who can write to a shared cache, for example only CI. With `--remote_upload_local_results=false`, a client reads from the cache without uploading. Decide based on who can change the code that pull-request jobs run.

### Is Bazel preinstalled on GitHub-hosted runners?

Yes. The Ubuntu runner images include Bazel and Bazelisk. Bazelisk downloads the version in `.bazelversion`, so pin it in the repository.

### Do I need larger runners for Bazel?

Not to start. Measure cache hits and the critical path first: avoided actions help on any runner. Larger runners or remote execution help with the cache-miss work that remains.

## Sources and review

Sources checked on **2026-11-13**: [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [larger runners](https://docs.github.com/en/actions/reference/runners/larger-runners), [dependency caching](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching), [Ubuntu 24.04 image](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md), [setup-bazel](https://github.com/bazel-contrib/setup-bazel), [Bazel remote caching](https://bazel.build/remote/caching), and the [Bazel 7 release notes](https://blog.bazel.build/2023/12/11/bazel-7-release.html). Written by Tuist.
