---
{
  "title": "入门指南",
  "titleTemplate": ":title · 入门指南 · 指南 · Tuist",
  "description": "选择与你的应用当前构建方式相匹配的 Tuist 路径：Xcode、生成的 Xcode 项目、Gradle、Elixir、Rust、Bazel 或 Once。"
}
---
# 开始使用 {#get-started}

选择与当前应用构建方式匹配的路径。每种路径都会引导你完成安装内容、如何启用缓存、洞察和测试功能，以及如何端到端验证设置。你可以独立采用这些路径，如果在多个平台上交付软件，也可以组合使用。

大多数路径使用 <.localized_link href="/guides/install-tuist">Tuist 命令行界面</.localized_link>。Elixir 使用 Hex 包，Once 通过其原生 Tuist 提供程序连接；两者在集成时都不需要 Tuist CLI。

## Xcode 项目 {#existing-xcode-project}

保留现有的 Xcode 项目或工作区，并逐个添加 Tuist 功能。无需生成项目。

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## 生成的 Xcode 项目 {#generated-xcode-project}

让 Tuist 从 Swift 清单定义并生成你的 Xcode 项目。生成的项目将模块化 Xcode 项目的复杂性压缩为简洁的声明式图描述，并且是 <.localized_link href="/guides/features/cache/module-cache">模块缓存</.localized_link> 和 <.localized_link href="/guides/features/selective-testing/generated-xcode-project">选择性测试</.localized_link> 的严格要求。

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

## Once 项目 {#once-project}

将 Once 的可缓存脚本和构建图连接到 Tuist，以实现共享缓存、实时构建和测试洞察、托管测试分片以及应用预览。

<.localized_link href="/guides/get-started/once-project">Start with a Once project →</.localized_link>
