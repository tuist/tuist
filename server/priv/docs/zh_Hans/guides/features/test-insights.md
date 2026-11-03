---
{
  "title": "测试洞察",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "通过 Tuist 测试洞察，识别 Xcode、Gradle、Bazel、Elixir 和 Rust 项目中的不稳定测试和缓慢测试。"
}
---
# 测试洞察 {#test-insights}

使用测试洞察来监控你的测试套件健康状况：识别慢速测试、追踪不稳定测试，并快速了解失败的 CI 运行。目前支持 Xcode、Gradle、Bazel、Elixir 和 Rust。

<.home_cards>
  <.home_card
    title="Xcode"
    details="通过 Scheme 的 post-actions 和 Tuist CLI 追踪 Xcode 测试分析数据。"
    link="/guides/features/test-insights/xcode"
/>
  <.home_card
    title="Gradle"
    details="通过 Tuist Gradle 插件追踪 Gradle 测试分析数据。"
    link="/guides/features/test-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="通过运行 tuist bazel test 来追踪 Bazel 测试分析数据。"
    link="/guides/features/test-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="通过 Tuist Hex 包追踪你的 Elixir 项目中的测试。"
    link="/guides/features/test-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="使用你常用的测试命令追踪 Cargo 测试结果、套件耗时以及文档测试。"
    link="/guides/features/test-insights/rust"
/>
</.home_cards>
