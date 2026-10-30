---
{
  "title": "什么是 Tuist？",
  "description": "开发者的虚拟平台团队。为 Xcode、Gradle、Bazel、Elixir 和 Rust 构建基础设施，并提供针对各工具链定制的功能。"
}
---

# 为交付软件的开发者打造的虚拟平台团队

**Tuist 帮助团队扩展应用开发并加速交付**，将大型代码库的复杂性转化为随团队成长的高效体验。它与你已使用的构建系统集成，支持 Xcode、Gradle、Bazel、Elixir 和 Rust 项目。可用功能取决于你的工具链：Rust 项目可获得 Cargo 构建与测试洞察，包括文档测试、不稳定测试检测以及实验性编译缓存。

首先<.localized_link href="/guides/install-tuist">安装 Tuist 命令行界面</.localized_link>，然后按照适用于你构建系统的<.localized_link href="/guides/get-started">入门指南</.localized_link>操作。

<br/>

<.home_cards>
  <.home_card
    title="缓存"
    details="在团队和 CI 之间共享编译输出。支持 Xcode 编译缓存、Tuist 模块缓存、Gradle 构建缓存、Bazel 远程缓存，以及 Rust 的实验性编译缓存。"
    supported_for="apple,gradle,bazel,rust"
    link="/guides/features/cache"
/>
  <.home_card
    title="构建与测试洞察"
    details="跟踪 Xcode、Gradle、Bazel、Elixir 和 Rust 项目的构建与测试时长、失败、不稳定性及回归问题。"
    supported_for="apple,gradle,bazel,elixir,rust"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="选择性测试"
    details="仅在 Xcode 和生成的项目中运行受变更影响的测试，让反馈在数秒内到位。"
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
    title="生成的项目"
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
    details="分析并保持应用精简，让用户下载更快，同时满足应用商店规范。"
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## 受到大规模交付团队的信赖

**[Trendyol](https://www.trendyol.com/)、[Etsy](https://www.etsy.com/)、[Bumble](https://bumble.com/)、[Monzo](https://monzo.com/)、[Bending Spoons](https://bendingspoons.com/) 等 100 多家公司的团队**在其 iOS 和 Android 代码库中使用 Tuist 加速交付。
