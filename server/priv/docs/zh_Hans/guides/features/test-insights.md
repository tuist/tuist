---
{
  "title": "测试洞察",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 测试洞察，识别 Xcode、Gradle、Bazel、Elixir、Rust 和 Struo 项目中的不稳定测试和慢速测试。"
}
---
# 测试洞察 {#test-insights}

使用测试洞察监控测试套件的健康状况：识别慢速测试、跟踪不稳定测试，并快速了解失败的 CI 运行。目前支持 Xcode、Gradle、Bazel、Elixir、Rust 和 Struo。可用的结果和耗时取决于你的运行器。要追踪在受支持的构建系统中测试执行的代码，请参阅<.localized_link href="/guides/features/test-code-coverage">代码覆盖率</.localized_link>。有关[慢速测试](https://tuist.dev/solutions/slow-tests)和[不稳定测试](https://tuist.dev/solutions/flaky-tests)的指南，请查看解决方案指南。

<.home_cards>
  <.home_card
    title="Xcode"
    details="通过 Scheme 后操作和 Tuist CLI 跟踪 Xcode 测试分析数据。"
    link="/guides/features/test-insights/xcode"
/>
  <.home_card
    title="Gradle"
    details="通过 Tuist Gradle 插件跟踪 Gradle 测试分析数据。"
    link="/guides/features/test-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="通过运行 tuist bazel test 来跟踪 Bazel 测试分析数据。"
    link="/guides/features/test-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="通过 Tuist Hex 包跟踪 Elixir 项目的测试。"
    link="/guides/features/test-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="使用常规测试命令跟踪 Cargo 测试结果、套件耗时和文档测试。"
    link="/guides/features/test-insights/rust"
/>
  <.home_card
    title="Struo"
    details="通过 Struo 的原生集成跟踪报告的测试目标、套件、用例、失败以及重试尝试。"
    link="/guides/features/test-insights/struo"
/>
</.home_cards>
