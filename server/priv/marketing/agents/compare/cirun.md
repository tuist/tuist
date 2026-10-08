# Tuist and Cirun: improve build work or manage runners in your infrastructure?

Choose Tuist for supported build-output reuse, toolchain evidence, and agent investigation across existing environments. Add a [supported Tuist integration](/en/docs-markdown/guides/get-started) to the current runner fleet and improve the build and test loop without handing runner lifecycle to a new service.

## What overlaps

[Cirun's documentation](https://docs.cirun.io/) covers cloud connections, runner configuration, custom images, and on-premises execution. Its [on-premises guide](https://docs.cirun.io/on-prem) explains connecting customer infrastructure instead of moving all execution to a hosted fleet.

Cirun also documents [cache acceleration](https://docs.cirun.io/caching/). Its automatic Actions-cache backend currently supports Linux runners on AWS; an explicit S3-compatible cache action supports any OS, cloud, or runner with a compatible store. Do not describe Cirun as lacking caching or conflate those two integration scopes.

## Compare the operating model

| Requirement | Tuist | Cirun evidence to evaluate |
| --- | --- | --- |
| Own the execution location | Tuist caching and insights can use supported existing machines; [Tuist Runners](/marketing-markdown/compute) are optional. | Cirun manages GitHub Actions runners on connected clouds and on-premises infrastructure. Evaluate cloud credentials, images, lifecycle, and operations. |
| Own directory-cache storage | Tuist runner cache volumes are distinct from its remote build-output cache. | Cirun's cache guide documents customer-owned S3 in automatic mode and an explicit action for S3-compatible storage. |
| Share toolchain-keyed outputs | [Cache](/marketing-markdown/cache) connects supported compatible local, CI, and agent builds. | The cited cache mechanism implements the Actions archive-cache contract. Evaluate any build-system endpoint separately rather than assuming equivalent granularity. |
| Investigate build/test outcomes | Tuist [Build Insights](/en/docs-markdown/guides/features/build-insights), [Tests](/marketing-markdown/tests), and [MCP](/en/docs-markdown/guides/features/agentic-coding/mcp) expose supported records. | Runner management solves provisioning and execution control. Evaluate Cirun's available diagnostics for your actual task; missing documentation is not proof of absent analytics. |

## Choose Tuist when

Your existing runner configuration already works, but compilation, task execution, cache misses, or test behavior needs improvement. You want developers and agents to use the same supported evidence and compatible build outputs as CI. Tuist's [public source](https://github.com/tuist/tuist) allows engineers to inspect and contribute to those integrations.

## First experiment

Keep the existing runner configuration and pilot a [supported Tuist integration](/en/docs-markdown/guides/get-started). Confirm that sending build/test records or artifacts to a hosted endpoint is permitted, or review [Tuist self-hosting](/en/docs-markdown/guides/server/self-host/server) if policy requires private deployment. Compare build-output reuse and execution against the current baseline, measuring restoration, compilation, and tests separately. Use Tuist MCP to investigate one recorded cache miss or failing test.

## Sources and review

Sources checked on **2026-10-08**: [Cirun documentation](https://docs.cirun.io/), [on-premises runners](https://docs.cirun.io/on-prem), [automatic and S3-compatible caching](https://docs.cirun.io/caching/), and [Tuist Cache](/marketing-markdown/cache). This comparison is written by Tuist and distinguishes runner lifecycle from artifact reuse.

## Limitations

You still need to own cloud permissions, machine configuration, network policy, and operational cost. Cache integration support and lifecycle behavior can change. Tuist capabilities vary by toolchain; selective testing requires generated Xcode projects. Licenses and supported server self-hosting are separate questions. Tuist Runners are invite-only with no public pricing, and no guaranteed saving is claimed.

Related: [RunsOn](/marketing-markdown/compare/runs-on), [Buildkite](/marketing-markdown/compare/buildkite), and [all comparisons](/marketing-markdown/compare).
