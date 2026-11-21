---
{
  "title": "构建洞察",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 构建洞察跟踪 Xcode、Gradle、Bazel、Elixir、Rust 和 Struo 项目的构建性能。"
}
---
# 构建洞察 {#build-insights}

使用构建洞察追踪本地和 CI 构建性能。目前支持 Xcode、Gradle、Bazel、Elixir、Rust 和 Struo。如需逐步排查构建缓慢和 CI 成本上升的问题，请参阅[构建缓慢](https://tuist.dev/solutions/slow-builds)和[CI 成本](https://tuist.dev/solutions/ci-costs)。

<.home_cards>
  <.home_card
    title="Xcode"
    details="在 Tuist 仪表板中追踪 Xcode Scheme 的后置操作耗时、构建设置和构建元数据。"
    link="/guides/features/build-insights/xcode"
/>
  <.home_card
    title="生成的项目"
    details="在带有自定义 Scheme 的 Tuist 生成项目中追踪构建洞察。"
    link="/guides/features/build-insights/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="通过 Tuist Gradle 插件追踪 Gradle 任务耗时和缓存效果。"
    link="/guides/features/build-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="通过 Build Event Protocol 追踪 Bazel 命令持续时间、缓存总量和关键路径诊断。"
    link="/guides/features/build-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="追踪 Elixir 项目的编译时长、警告以及拖慢构建的文件。"
    link="/guides/features/build-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="通过 Tuist CLI 追踪 Cargo 命令持续时间、观察到的 rustc 调用以及编译器诊断。"
    link="/guides/features/build-insights/rust"
/>
  <.home_card
    title="Struo"
    details="实时跟踪运行并检查图操作、持续时间、失败和缓存决策。"
    link="/guides/features/build-insights/struo"
/>
</.home_cards>
