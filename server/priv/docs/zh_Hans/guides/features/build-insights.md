---
{
  "title": "构建洞察",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 构建洞察跟踪 Xcode、Gradle、Bazel、Elixir 和 Rust 项目的构建性能。"
}
---
# 构建洞察 {#build-insights}

使用构建洞察跟踪本地和 CI 构建性能。目前支持 Xcode、Gradle、Bazel、Elixir 和 Rust。

<.home_cards>
  <.home_card
    title="Xcode"
    details="在 Tuist 仪表板中跟踪 Xcode Scheme 的后置操作耗时、构建设置和构建元数据。"
    link="/guides/features/build-insights/xcode"
/>
  <.home_card
    title="生成的项目"
    details="在带有自定义 Scheme 的 Tuist 生成项目中跟踪构建洞察。"
    link="/guides/features/build-insights/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="通过 Tuist Gradle 插件跟踪 Gradle 任务耗时和缓存效率。"
    link="/guides/features/build-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="通过 Build Event Protocol 跟踪 Bazel 命令持续时间、缓存总量和关键路径诊断。"
    link="/guides/features/build-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="跟踪 Elixir 项目的编译耗时、警告以及拖慢构建的文件。"
    link="/guides/features/build-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="通过 Tuist CLI 跟踪 Cargo 命令持续时间、观察到的 rustc 调用以及编译器诊断。"
    link="/guides/features/build-insights/rust"
/>
</.home_cards>
