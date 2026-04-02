---
{
  "title": "Test Sharding",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Distribute tests across multiple CI runners to speed up your test suite with Tuist Test Sharding."
}
---
# Test Sharding {#test-sharding}

Modern CI hosts offer multi-core environments that allow some degree of test parallelization. However, there are scenarios where you need to go beyond what a single host can offer — for example, when you're limited by the number of simulators you can run simultaneously, or when your test suite simply outgrows a single machine.

In those cases, you need a system that distributes tests across multiple CI runners and aggregates the results back into a unified view. That's what test sharding does.

Tuist uses historical test timing data to intelligently balance the load across shards using a [bin-packing algorithm](https://en.wikipedia.org/wiki/Bin_packing_problem), so each runner finishes at roughly the same time. Results from all shards are automatically aggregated in <TuistWeb.Docs.MarkdownComponents.localized_link href="/guides/features/test-insights">Test Insights</TuistWeb.Docs.MarkdownComponents.localized_link>, giving you a single unified view of your test suite across all shards.

<HomeCards>
    <HomeCard
        icon="<img src='/images/guides/features/xcode-icon.png' alt='Xcode' width='32' height='32' />"
        title="Xcode"
        details="Shard Xcode tests across parallel CI runners."
        linkText="Xcode test sharding"
        link="/guides/features/test-sharding/xcode"/>
    <HomeCard
        icon="<img src='/images/guides/features/xcode-icon.png' alt='Xcode' width='32' height='32' />"
        title="Generated projects"
        details="Shard tests in Tuist generated projects across parallel CI runners."
        linkText="Generated projects test sharding"
        link="/guides/features/test-sharding/generated-projects"/>
    <HomeCard
        icon="<img src='/images/guides/features/gradle-icon.svg' alt='Gradle' width='32' height='32' />"
        title="Gradle"
        details="Shard Gradle tests across parallel CI runners."
        linkText="Gradle test sharding"
        link="/guides/features/test-sharding/gradle"/>
</HomeCards>

> [!WARNING]
> **Requirements**
>
> - A <TuistWeb.Docs.MarkdownComponents.localized_link href="/guides/server/accounts-and-projects">Tuist account and project</TuistWeb.Docs.MarkdownComponents.localized_link>
> - <TuistWeb.Docs.MarkdownComponents.localized_link href="/guides/features/test-insights">Test Insights</TuistWeb.Docs.MarkdownComponents.localized_link> configured (for optimal shard balancing based on historical timing data)

