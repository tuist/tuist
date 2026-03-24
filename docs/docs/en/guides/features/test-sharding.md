---
{
  "title": "Test Sharding",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Distribute tests across multiple CI runners to speed up your test suite with Tuist Test Sharding."
}
---
# Test Sharding {#test-sharding}

As your test suite grows, running all tests on a single CI runner becomes a bottleneck. Test sharding distributes your tests across multiple CI runners that execute in parallel, dramatically reducing your overall CI time.

Tuist uses historical test timing data to intelligently balance the load across shards using a bin-packing algorithm, so each runner finishes at roughly the same time.

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

::: warning REQUIREMENTS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist account and project</LocalizedLink>
- <LocalizedLink href="/guides/features/test-insights">Test Insights</LocalizedLink> configured (for optimal shard balancing based on historical timing data)
<!-- -->
:::
