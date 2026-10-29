---
{
  "title": "Get started",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Pick the Tuist path that matches how your app is built today: Xcode, generated Xcode projects, Gradle, Elixir, Rust, or Bazel."
}
---
# 开始使用 {#get-started}

选择与当前应用构建方式匹配的路径。每种路径都会逐步介绍需要安装的内容、如何启用缓存、洞察和测试功能，以及如何端到端地验证设置。你可以单独采用它们，或者在多个平台上发布时组合使用。

## Xcode 项目 {#existing-xcode-project}

保留现有的 Xcode 项目或工作区，并逐一添加 Tuist 功能。无需生成项目。

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## 生成的 Xcode 项目 {#generated-xcode-project}

让 Tuist 根据 Swift 清单定义并生成你的 Xcode 项目。生成的项目将模块化 Xcode 项目的复杂性压缩为对依赖图的简洁声明式描述，并且是 <.localized_link href="/guides/features/cache/module-cache">模块缓存</.localized_link> 和 <.localized_link href="/guides/features/selective-testing/generated-xcode-project">选择性测试</.localized_link> 的严格要求。

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Gradle 项目 {#gradle-project}

通过 `dev.tuist` Gradle 插件将 Gradle 项目连接到 Tuist 的远程缓存、构建洞察和测试洞察。

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Elixir 项目 {#elixir-project}

通过 `tuist_ex` Hex 包将 Elixir 项目连接到 Tuist 的构建洞察、测试洞察、不稳定测试检测和测试分片。

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Rust 项目 {#rust-project}

通过 Tuist CLI 运行 Cargo 以报告构建和单个测试结果（包括文档测试），并调查不稳定测试。

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Bazel 项目 {#bazel-project}

将 Bazel 工作区指向 Tuist 的远程执行 API 缓存和构建事件服务，以便在团队和 CI 之间共享缓存命中和洞察。

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

在进行上述任何操作之前，请先 <.localized_link href="/guides/install-tuist">安装 Tuist 命令行界面</.localized_link>。Elixir 项目是例外：它们只需要 Hex 包。
