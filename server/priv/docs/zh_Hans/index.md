---
{
  "title": "什么是 Tuist？",
  "description": "Tuist 是面向工程团队及其 AI 编程助手的构建平台。它支持 Xcode、Gradle、Bazel、Elixir 和 Rust 的构建与测试工作流；Once 支持目前处于 Canary 阶段。功能因工具链而异，Rust 编译缓存仍处于实验阶段。"
}
---

# 面向团队及其编码智能体的构建平台

**Tuist 是面向工程团队及其编码智能体的构建平台。** 它支持 Xcode、Gradle、Bazel、Elixir 和 Rust 的构建与测试工作流；Once 的支持处于 Canary 阶段。它与你在用的构建系统协同工作，而不是取代它们。可用功能取决于你的工具链：Rust 项目可获得 Cargo 构建与测试洞察，包括文档测试、不稳定测试检测以及实验性编译缓存。Once 通过原生集成提供共享缓存、构建与测试洞察、分片以及受支持的应用预览。

根据你的构建系统，选择一条<.localized_link href="/guides/get-started">入门路径</.localized_link>。Once 无需 Tuist CLI 即可直接连接；其他路径会说明需要安装哪些 Tuist 工具。

<br/>

<.home_cards>
  <.home_card
    title="缓存"
    details="在团队与 CI 之间共享构建产物。兼容 Xcode 的编译缓存、Tuist 的模块缓存、Gradle 的构建缓存、Bazel 的远程缓存、Elixir 的依赖缓存、Rust 的实验性编译缓存，以及 Once 的共享操作缓存。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/cache"
/>
  <.home_card
    title="构建与测试洞察"
    details="追踪 Xcode、Gradle、Bazel、Elixir、Rust 和 Once 项目的构建与测试耗时、失败、不稳定性以及回归情况。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="选择性测试"
    details="在生成的 Xcode 项目中跳过未变更的测试目标，并提供用于单独选择 XCTest/XCUITest 的早期访问覆盖策略。"
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="运行器"
    details="在托管的 macOS 和 Linux 运行器上运行 CI，靠近开发者机器使用的同一缓存。"
    link="/guides/features/runners"
/>
  <.home_card
    title="预览"
    details="通过 URL 分享受支持的移动应用、macOS 应用以及 macOS/Linux 命令行工具。需满足构建、签名以及接收方兼容性要求。"
    link="/guides/features/previews"
/>
  <.home_card
    title="生成的项目"
    details="用 Swift 描述 Xcode 项目并一致地生成它们。减少项目文件冲突并启用模块缓存。"
    link="/guides/features/projects"
/>
  <.home_card
    title="包注册表"
    details="通过注册表协议获取受支持的 Swift 包，而无需克隆其 Git 仓库。"
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="包体积"
    details="随时间追踪受支持的 Apple 和 Android 包体积，并调查体积回归。"
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## 深受大规模交付软件的团队信赖

阅读[客户案例](https://tuist.dev/customers)，了解团队采用的工作流以及他们报告的结果。
