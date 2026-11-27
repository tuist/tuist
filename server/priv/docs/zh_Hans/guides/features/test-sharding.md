---
{
  "title": "测试分片",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "通过 Tuist 测试分片，将测试分配到多个 CI 运行器上，以加快测试套件的速度。"
}
---
# 测试分片 {#test-sharding}

现代 CI 主机提供多核环境，支持一定程度的测试并行化。但在某些场景下，单台主机的能力已不足以应对——例如，可同时运行的模拟器数量有限，或者测试套件规模已经超出单台机器的承载能力。

在这些情况下，你需要一个系统，将测试分发到多个 CI 运行器上，并将结果聚合为统一视图。这正是测试分片的作用。

Tuist 利用历史测试耗时数据，通过[装箱算法](https://en.wikipedia.org/wiki/Bin_packing_problem)智能地在各分片之间平衡负载，使每个运行器大致在同一时间完成。所有分片的结果会自动聚合到<.localized_link href="/guides/features/test-insights">测试洞察</.localized_link>中，为你提供跨所有分片的测试套件统一视图。分片可以缩短挂钟时间，但可能增加机器时间；[慢速测试](https://tuist.dev/solutions/slow-tests)和[CI 成本](https://tuist.dev/solutions/ci-costs)说明了如何权衡二者。

<.home_cards>
  <.home_card
    title="Xcode"
    details="在并行 CI 运行器上分片运行 Xcode 测试。"
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="生成的项目"
    details="在并行 CI 运行器上分片运行 Tuist 生成项目中的测试。"
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="在并行 CI 运行器上分片运行 Gradle 测试。"
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="在并行 CI 运行器上分片运行你的 Elixir 项目测试。"
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="在并行 CI 工作节点上分发 Cargo 测试目标。"
    link="/guides/features/test-sharding/rust"
/>
  <.home_card
    title="Struo"
    details="在使用托管方案并合并结果的 CI 工作节点上分发已发现的 Struo 测试批次。"
    link="/guides/features/test-sharding/struo"
/>
</.home_cards>
