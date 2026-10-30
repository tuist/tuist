---
{
  "title": "不稳定测试",
  "titleTemplate": ":title · 测试洞察 · 功能 · 指南 · Tuist",
  "description": "在 CI 流水线中自动检测并跟踪不稳定测试。"
}
---
# 不稳定测试 {#flaky-tests}

不稳定测试是指在使用相同代码多次运行时产生不同结果（通过或失败）的测试。它们会削弱你对测试套件的信任，并浪费开发人员排查误报失败的时间。Tuist 会自动检测不稳定测试，并帮助你持续跟踪它们。

<.home_cards>
  <.home_card
    title="Xcode"
    details="通过 tuist xcodebuild test 检测、管理和隔离 Xcode 项目中的不稳定测试。"
    link="/guides/features/test-insights/flaky-tests/xcode"
/>
  <.home_card
    title="生成的项目"
    details="通过 tuist test 检测、管理和隔离 Tuist 生成项目中的不稳定测试。"
    link="/guides/features/test-insights/flaky-tests/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="检测和管理 Gradle 项目中的不稳定测试。"
    link="/guides/features/test-insights/flaky-tests/gradle"
/>
  <.home_card
    title="Bazel"
    details="通过 tuist bazel test 检测、静音和跳过不稳定的 Bazel 测试用例。"
    link="/guides/features/test-insights/flaky-tests/bazel"
/>
  <.home_card
    title="Elixir"
    details="通过测试重试检测和管理 Elixir 项目中的不稳定测试。"
    link="/guides/features/test-insights/flaky-tests/elixir"
/>
  <.home_card
    title="Rust"
    details="利用跨 CI 运行的结果检测并排查不稳定的 Cargo 测试。"
    link="/guides/features/test-insights/flaky-tests/rust"
/>
</.home_cards>
