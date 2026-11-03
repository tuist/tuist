---
{
  "title": "测试分片",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "通过 Tuist 测试分片，将测试分发到多个 CI 运行器上，以加速你的测试套件。"
}
---
# 测试分片 {#test-sharding}

现代 CI 主机提供多核环境，允许一定程度的测试并行化。然而，在某些场景下，你需要超越单台主机的能力——例如，当你受限于可同时运行的模拟器数量，或者你的测试套件规模已经超出单台机器的处理能力时。

在这些情况下，你需要一个能够将测试分发到多个 CI 运行器并将结果聚合为统一视图的系统。这正是测试分片的作用。

Tuist 利用历史测试耗时数据，通过[装箱算法](https://en.wikipedia.org/wiki/Bin_packing_problem)智能地在各个分片之间平衡负载，使每个运行器大致在同一时间完成。所有分片的结果会自动聚合到<.localized_link href="/guides/features/test-insights">测试洞察</.localized_link>中，为你提供跨所有分片的测试套件统一视图。

<.home_cards>
  <.home_card
    title="Xcode"
    details="在并行 CI 运行器上分片 Xcode 测试。"
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="生成的项目"
    details="在并行 CI 运行器上分片 Tuist 生成项目中的测试。"
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="在并行 CI 运行器上分片 Gradle 测试。"
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="在并行 CI 运行器上分片 Elixir 项目的测试。"
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="在并行 CI 工作节点上分发 Cargo 测试目标。"
    link="/guides/features/test-sharding/rust"
/>
</.home_cards>
