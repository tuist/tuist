---
{
  "title": "什么是 Tuist？",
  "description": "Tuist 是面向工程团队及其编码代理的构建平台。它支持跨 Xcode、Gradle、Bazel、Elixir 和 Rust 的构建与测试工作流；Once 的支持处于 Canary 阶段。功能因工具链而异，Rust 编译缓存为实验性功能。"
}
---

# 面向团队及其编码智能体的构建平台

**Tuist 是面向工程团队及其编码智能体的构建平台。** 它支持 Xcode、Gradle、Bazel、Elixir 和 Rust 的构建与测试工作流；Once 的支持处于 Canary 阶段。它与你在用的构建系统协同工作，而不是将其替换。可用功能取决于你的工具链：Rust 项目可获得 Cargo 构建和测试洞察，包括文档测试、不稳定测试检测以及实验性编译缓存。Once 原生连接以共享缓存、构建和测试洞察、分片以及受支持的应用预览。

按照适用于你构建系统的<.localized_link href="/guides/get-started">入门路径</.localized_link>操作。Once 无需 Tuist CLI 即可直接连接；其他路径会说明需要安装哪些 Tuist 工具。

<br/>

<.home_cards>
  <.home_card
    title="缓存"
    details="在团队和 CI 之间共享构建产物。支持与 Xcode 的编译缓存、Tuist 的模块缓存、Gradle 的构建缓存、Bazel 的远程缓存、Elixir 的依赖缓存、Rust 的实验性编译缓存，以及 Once 的共享动作缓存协同工作。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/cache"
/>
  <.home_card
    title="构建与测试洞察"
    details="跟踪 Xcode、Gradle、Bazel、Elixir、Rust 和 Once 项目的构建与测试耗时、失败、不稳定性以及回归情况。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="选择性测试"
    details="仅运行受生成式 Xcode 项目变更影响的测试，让反馈在数秒内到位。"
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="运行器"
    details="在托管的 macOS 和 Linux 运行器上运行 CI，靠近开发者机器使用的同一缓存。"
    link="/guides/features/runners"
/>
  <.home_card
    title="预览"
    details="通过一个 URL 即时分享你的应用。无需等待应用商店审核，也无需复杂配置。"
    link="/guides/features/previews"
/>
  <.home_card
    title="生成式项目"
    details="用 Swift 描述 Xcode 项目并一致地生成它们。消除合并冲突并解锁模块缓存。"
    link="/guides/features/projects"
/>
  <.home_card
    title="包注册表"
    details="借助由 Tuist 缓存网络支持的注册表，在数秒而非数分钟内解析 Swift 包。"
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="包体积"
    details="分析并保持应用精简，让用户获得更快的下载速度，同时满足应用商店规范。"
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## 受到大规模交付团队的信赖

**[Trendyol](https://www.trendyol.com/)、[Etsy](https://www.etsy.com/)、[Bumble](https://bumble.com/)、[Monzo](https://monzo.com/)、[Bending Spoons](https://bendingspoons.com/) 以及 100 多家其他公司**的团队在其 iOS 和 Android 代码库中借助 Tuist 更快交付。
