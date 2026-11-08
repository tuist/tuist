---
{
  "title": "缓存",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "通过 Tuist Cache 优化 Xcode、Gradle、Bazel、Elixir、Rust 和 Once 的构建时间。"
}
---
# 缓存 {#cache}

构建产物无法在不同环境间共享，导致你不得不反复重新构建相同的代码。Tuist 的缓存功能可以远程共享这些产物，让你的团队和 CI 能够更快地完成构建，而无需重复构建已经构建过的内容。

了解适合你的项目或部署模型的缓存工作流：

<.home_cards>
  <.home_card
    title="模块缓存"
    details="为使用 Tuist 生成项目的工程将单个模块以二进制形式进行缓存。需要 Tuist 项目生成功能。"
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcode 缓存"
    details="在不同环境间共享 Xcode 编译产物。适用于任何 Xcode 项目，无需项目生成。"
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Gradle 缓存"
    details="远程共享 Gradle 构建缓存产物。包含用于性能可视化的构建洞察。"
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Bazel 缓存"
    details="将 Bazel 指向 Tuist 的 Remote Execution API 缓存，以便在团队和 CI 之间共享操作输出。"
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Elixir 缓存"
    details="为受支持的 Elixir 依赖启用缓存，并继续使用 Mix。在仪表盘中检查缓存命中和传输情况。"
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Rust 缓存（实验性）"
    details="在本地以及通过 Kura 复用受支持的 Rust 编译输出和构建脚本运行结果。了解如何启用缓存并检查缓存活动。"
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="Once 缓存"
    details="借助 Once 的原生 Tuist 提供程序，在开发者机器和 CI 之间共享缓存的脚本和图操作结果。"
    link="/guides/features/cache/once"
/>
  <.home_card
    title="自托管"
    details="在靠近 CI、办公室或区域计算资源的位置运行缓存节点，并将它们连接到托管版或自托管版的 Tuist。"
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **在 Tuist Runners 上速度最快**
>
> 在 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 上，缓存位于运行器的私有网络中，并与你的开发机器使用的缓存共享，因此 CI 任务开箱即用地获得预热缓存命中，无需单独预热 CI 缓存。


## 限制仅允许 CI 上传 {#restrict-uploads-to-ci}

账户管理员可以将开发者设为只读，同时允许 CI 上传缓存产物。在 Tuist 中打开账户的 **缓存** 设置，并将 **缓存上传访问权限** 设置为 **仅限 CI 和账户令牌**。此后，通过登录会话认证的成员仍然可以从缓存下载，但上传需要 CI OIDC 认证或具有缓存写入作用域（例如 `project:cache:write` 或 `ci`）的账户令牌。

当 CI 是可信的缓存生产者且本地机器应仅消费缓存时，请使用此设置。该设置仅影响缓存上传授权。
