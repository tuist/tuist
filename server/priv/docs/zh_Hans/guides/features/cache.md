---
{
  "title": "缓存",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "通过 Tuist Cache 优化 Xcode、Gradle、Bazel、Elixir、Rust 和 Once 的构建时间。"
}
---
# 缓存 {#cache}

构建产物不会在不同环境之间共享，导致你不得不反复重新构建相同的代码。Tuist 的缓存功能可远程共享产物，让团队和 CI 在不重复构建已有内容的前提下获得更快的构建速度。在选择缓存方案之前，如需排查构建缓慢的原因，请参阅 [Slow builds](https://tuist.dev/solutions/slow-builds)。

了解与你的项目或部署模型匹配的缓存工作流：

<.home_cards>
  <.home_card
    title="模块缓存"
    details="将各个模块以二进制形式缓存，适用于使用 Tuist 生成项目的工程。需要启用 Tuist 项目生成功能。"
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcode 缓存"
    details="在不同环境之间共享 Xcode 编译产物。适用于任何 Xcode 项目，无需项目生成。"
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Gradle 缓存"
    details="远程共享 Gradle 构建缓存产物。包含构建洞察，帮助你了解性能表现。"
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Bazel 缓存"
    details="将 Bazel 指向 Tuist 的 Remote Execution API 缓存，以便在团队和 CI 之间共享动作输出。"
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Elixir 缓存"
    details="为受支持的 Elixir 依赖启用缓存，并继续使用 Mix。在仪表盘中查看缓存命中和传输情况。"
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Rust 缓存（实验性）"
    details="在本地并通过 Kura 复用受支持的 Rust 编译输出和构建脚本运行结果。了解如何启用缓存并检查缓存活动。"
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="Once 缓存"
    details="通过 Once 的原生 Tuist 提供程序，在开发者机器和 CI 之间共享已缓存的脚本和图动作结果。"
    link="/guides/features/cache/once"
/>
  <.home_card
    title="自托管"
    details="在靠近 CI、办公室或区域计算资源的位置运行缓存节点，并将它们连接到托管版或自托管版 Tuist。"
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **在 Tuist Runners 上速度最快**
>
> 在 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 上，缓存位于 Runner 的私有网络中，并与你的开发者机器使用的同一缓存共享，因此 CI 任务开箱即用即可获得热缓存命中，无需单独预热 CI 缓存。


## 限制仅允许 CI 上传 {#restrict-uploads-to-ci}

账户管理员可以将开发者设置为只读，同时允许 CI 上传缓存产物。在 Tuist 中打开账户的 **Cache** 设置，并将 **Cache upload access** 设置为 **CI and account tokens only**。此后，通过登录会话认证的成员仍可从缓存下载，但上传需要 CI OIDC 认证或具备缓存写入权限范围的账户令牌，例如 `project:cache:write` 或 `ci`。

当 CI 是可信的缓存生产者且本地机器仅应消费缓存时使用此设置。该设置仅影响缓存上传授权。
