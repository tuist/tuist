# Tuist pricing

Hosted Tuist is priced by feature usage, not seats by default. This guide explains the plan structure and how to estimate cost; the live [pricing table](/pricing) is the only source for current allowances and rates.

## Plans

- **Air**: free within the plan's tier limits, with all features and no credit card. Community support through the forum.
- **Pro**: usage-based pricing per feature above free allowances, so usage below them costs nothing. Standard support through Slack and email.
- **Enterprise**: a custom agreement, for example tailored legal terms, seat-based or custom pricing, priority support, self-hosting the Tuist server, or self-hosted cache nodes.

Seat-based plans, annual billing discounts, and discounts for non-profits and open-source projects are available on request through [contact@tuist.dev](mailto:contact@tuist.dev).

## What is metered and what is included

Tuist is rolling out a new billing model, so accounts can be on different models and the pricing page can show different tables. This guide deliberately does not duplicate numeric rates or allowances.

- **Newer usage-based model**: meters cache egress and cache requests (downloads across the module, Xcode, Gradle, and Bazel caches; uploads and storage are free) and passing test cases reported to Test Insights. Usage from Tuist Runners is counted differently. Selective testing is listed as unlimited.
- **Older model**: meters module cache and selective testing by CLI interactions with the server.
- **Listed as included without metering**: generated projects, previews, the Swift package registry, build insights, and bundle insights.

## How to estimate cost

1. List the features and toolchains you will use.
2. Estimate their metered usage, such as cache downloads per CI build and passing test cases per run.
3. Compare against the allowances and rates in the live [pricing table](/pricing) and the account's billing settings.
4. If unsure, use the free tier for a few days and read the recorded usage, as the pricing FAQ suggests.

According to the pricing FAQ, Tuist warns before plan limits are reached and then caps usage rather than charging unexpectedly. Plans can be changed or cancelled at any time, with no minimum contract length.

## Compute availability

Tuist Runners are invite-only and runner pricing is not public yet. Hosted plan pricing does not include or imply compute rates. [Contact the team](mailto:contact@tuist.dev) for access.

## Limitations

Free allowances are not unlimited usage. Actual charges depend on the account's plan, billing model, recorded usage, and any signed agreement. A rate copied from elsewhere is not a quote. For procurement, self-hosting, or custom terms, [book a conversation](https://cal.tuist.dev/team/tuist/tuist).

- [Live pricing and comparison table](/pricing)
- [Product overview](/marketing-markdown)
- [Cache](/marketing-markdown/cache), [Tests](/marketing-markdown/tests), [Compute](/marketing-markdown/compute)
