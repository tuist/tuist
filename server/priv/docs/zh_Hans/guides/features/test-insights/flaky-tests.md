---
{
  "title": "不稳定测试",
  "titleTemplate": ":title · 测试洞察 · 功能 · 指南 · Tuist",
  "description": "在 CI 流水线中自动检测并跟踪不稳定测试。"
}
---
# 不稳定测试 {#flaky-tests}

不稳定测试是指在代码不变的情况下多次运行却产生不同结果（通过或失败）的测试。它们会削弱你对测试套件的信任，并浪费开发人员排查误报失败的时间。Tuist 会自动检测不稳定测试，并帮助你持续跟踪。要了解如何以团队方式调查和控制这些测试，请参阅[不稳定测试](https://tuist.dev/solutions/flaky-tests)。

<.home_cards>
  <.home_card
    title="Xcode"
    details="通过 tuist xcodebuild test 检测、管理并隔离 Xcode 项目中的不稳定测试。"
    link="/guides/features/test-insights/flaky-tests/xcode"
/>
  <.home_card
    title="生成的项目"
    details="通过 tuist test 检测、管理并隔离 Tuist 生成项目中的不稳定测试。"
    link="/guides/features/test-insights/flaky-tests/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="检测并管理 Gradle 项目中的不稳定测试。"
    link="/guides/features/test-insights/flaky-tests/gradle"
/>
  <.home_card
    title="Bazel"
    details="通过 tuist bazel test 检测、静音并跳过不稳定的 Bazel 测试用例。"
    link="/guides/features/test-insights/flaky-tests/bazel"
/>
  <.home_card
    title="Elixir"
    details="借助测试重试功能，检测并管理 Elixir 项目中的不稳定测试。"
    link="/guides/features/test-insights/flaky-tests/elixir"
/>
  <.home_card
    title="Rust"
    details="利用跨 CI 运行的结果，检测并调查不稳定的 Cargo 测试。"
    link="/guides/features/test-insights/flaky-tests/rust"
/>
  <.home_card
    title="Once"
    details="通过报告的重试尝试和 CI 历史记录，调查不一致的测试结果。"
    link="/guides/features/test-insights/flaky-tests/once"
/>
</.home_cards>
