# Tuist pricing

Hosted Tuist is priced by feature usage, not seats by default. This guide explains the plan structure and how to estimate cost; the live [pricing table](/pricing) is the only source for current allowances and rates.

## Plans

- **Air**: free within the plan's tier limits, with all features and no credit card. That includes the Module, Xcode, Gradle, and Bazel remote caches, so a team can run a [free Bazel remote cache](/marketing-markdown/solutions/bazel-remote-cache) within the cache allowance. Community support through the forum.
- **Pro**: usage-based pricing per feature above free allowances, so usage below them costs nothing. Standard support through Slack and email.
- **Enterprise**: a custom agreement, for example tailored legal terms, seat-based or custom pricing, priority support, self-hosting the Tuist server, or self-hosted cache nodes.

Seat-based plans, annual billing discounts, and discounts for non-profits and open-source projects are available on request through [contact@tuist.dev](mailto:contact@tuist.dev).

## What is metered and what is included

Tuist is rolling out a new billing model, so accounts can be on different models and the pricing page can show different tables. This guide deliberately does not duplicate numeric rates or allowances.

- **Newer usage-based model**: meters cache egress and cache requests (downloads across the module, Xcode, Gradle, and Bazel caches; uploads and storage are free) and passing test cases reported to Test Insights. Usage from Tuist Runners is counted differently. Selective testing is listed as unlimited.
- **Older model**: meters module cache and selective testing by CLI interactions with the server.
- **Compute**: one [compute rate table](/pricing#compute) covers runners and remote execution, with the same Linux rates for equivalent CPU and memory. macOS rates apply to runners only. Runners are billed per minute of CI job time.
- **Remote execution**: uses the shared [Linux compute rates](/pricing#compute) and the same project cache. The account Usage page keeps remote execution and runner usage separate.
- **Listed as included without metering**: generated projects, previews, the Swift package registry, build insights, and bundle insights.

## How to estimate cost

1. List the features and toolchains you will use.
2. Estimate their metered usage, such as cache downloads per CI build and passing test cases per run.
3. Compare against the allowances and rates in the live [pricing table](/pricing) and the account's billing settings.
4. If unsure, use the free tier for a few days and read the recorded usage, as the pricing FAQ suggests.

According to the pricing FAQ, Tuist warns before plan limits are reached and then caps usage rather than charging unexpectedly. Plans can be changed or cancelled at any time, with no minimum contract length.

## Project first, environment second

Tuist recommends improving the project and avoiding repeated build and test work before buying more compute. Minute- or build-metered execution charges can grow with the work you want to eliminate; compare the [documented billing units and total costs](/marketing-markdown/compare#compare-total-costs), not just the price of one minute. The [CI costs guide](/marketing-markdown/solutions/ci-costs) shows where spend usually goes, and the [comparison guides](/marketing-markdown/compare) cover how Tuist relates to other build and CI providers.

Tuist also meters feature usage, including cache downloads and reported passing tests under the newer model, and bills its optional runners per minute. Project optimization is our adoption order, not a claim that our commercial interests are automatically identical to every customer's. Include Tuist's charges in the before/after total, alongside retained compute, storage, and network costs.

## Compute availability

Tuist Runners are available to every account. The shared [Compute section](/pricing#compute) lists Linux rates for runners and remote execution, plus macOS rates for runners only. Runners are billed per minute of CI job time on top of any plan; machine boot and cleanup are not billed. Every plan includes monthly free macOS and Linux runner allowances and a free cache volume storage allowance, with storage beyond it billed per GB-month. [Contact the team](mailto:contact@tuist.dev) for access and for further yearly or volume discounts.

Remote execution runs individual Bazel and Struo build and test actions in single-use Linux microVMs with CPU and memory allocated per action. Reuse cached outputs before executing the remaining work remotely. [Contact the team](mailto:contact@tuist.dev) for higher concurrency limits. Each action is counted to the millisecond from when it starts in its VM until it finishes, including input fetch and output upload, at the Linux rate for its VM size; queueing and VM boot are not counted. The account Usage page shows remote execution separately from runners.

- [Live pricing and comparison table](/pricing)
- [Product overview](/marketing-markdown)
- [Cache](/marketing-markdown/cache), [Tests](/marketing-markdown/tests), [Runners](/marketing-markdown/runners)
