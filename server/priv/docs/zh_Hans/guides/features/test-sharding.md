---
{
  "title": "测试分片",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "通过 Tuist 测试分片，将测试分发到多个 CI 运行器上，以加速你的测试套件。"
}
---
# 测试分片 {#test-sharding}

现代 CI 主机提供多核环境，支持一定程度的测试并行化。然而，有些场景需要超越单台主机的能力——例如，当你能同时运行的模拟器数量受限，或者你的测试套件规模已经超出单机承载能力时。

在这些情况下，你需要一个能够将测试分发到多个 CI runner 并将结果汇总为统一视图的系统。这正是测试分片的作用。

Tuist 利用历史测试耗时数据，通过[装箱算法](https://en.wikipedia.org/wiki/Bin_packing_problem)智能地在各个分片之间平衡负载，使每个 runner 大致在同一时间完成。所有分片的结果会自动汇总到<.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>中，为你提供跨所有分片的测试套件统一视图。

<.home_cards>
  <.home_card
    title="Xcode"
    details="在并行 CI runner 上分片运行 Xcode 测试。"
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="生成的项目"
    details="在并行 CI runner 上分片运行 Tuist 生成项目中的测试。"
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="在并行 CI runner 上分片运行 Gradle 测试。"
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="在并行 CI runner 上分片运行你的 Elixir 项目测试。"
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="在并行 CI worker 上分发 Cargo 测试目标。"
    link="/guides/features/test-sharding/rust"
/>
</.home_cards>
