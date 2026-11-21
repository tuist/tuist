---
{
  "title": "缓存",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "通过 Tuist Cache 优化 Xcode、Gradle、Bazel、Elixir、Rust 和 Struo 的构建时间。"
}
---
# 缓存 {#cache}

构建产物无法在不同环境之间共享，导致你不得不反复重新构建相同的代码。Tuist 的缓存功能通过远程共享构建产物，让团队和 CI 无需重复构建已构建过的内容，从而获得更快的构建速度。要了解本地和远程构建缓存在不同构建系统中的工作原理，以及 Xcode 自身的缓存是什么，请参阅 <.localized_link href="/references/concepts/build-cache">什么是构建缓存？</.localized_link>。若要在选择缓存之前分析构建缓慢的原因，请参阅 [构建缓慢](https://tuist.dev/solutions/slow-builds)。

了解与你的项目或部署模型相匹配的缓存工作流：

<.home_cards>
  <.home_card
    title="模块缓存"
    details="为使用 Tuist 生成项目的工程将各个模块以二进制形式缓存。需要 Tuist 项目生成。"
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcode 缓存"
    details="在不同环境之间共享 Xcode 编译产物。适用于任何 Xcode 项目，无需项目生成。"
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Gradle 缓存"
    details="远程共享 Gradle 构建缓存产物。包含构建洞察，便于掌握性能情况。"
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Bazel 缓存"
    details="将 Bazel 指向 Tuist 的远程执行 API 缓存，以便在团队和 CI 之间共享动作输出。"
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Elixir 缓存"
    details="为受支持的 Elixir 依赖启用缓存并继续使用 Mix。在仪表盘中查看缓存命中和传输情况。"
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Rust 缓存（实验性）"
    details="在本地并通过 Kura 复用受支持的 Rust 编译输出和构建脚本运行结果。了解如何启用缓存并检查缓存活动。"
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="Struo 缓存"
    details="借助 Struo 的原生 Tuist 提供程序，在开发者机器和 CI 之间共享缓存的脚本和图动作结果。"
    link="/guides/features/cache/struo"
/>
  <.home_card
    title="自托管"
    details="在靠近 CI、办公室或区域计算资源的位置运行缓存节点，并将它们连接到托管版或自托管版 Tuist。"
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **在 Tuist Runners 上最快**
>
> 在 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 上，缓存位于运行器的私有网络中，并与开发者机器使用的同一缓存共享，因此 CI 任务开箱即可获得预热命中，无需单独预热 CI 缓存。


## 限制仅允许 CI 上传 {#restrict-uploads-to-ci}

账户管理员可以将开发者设为只读，同时允许 CI 上传缓存产物。在 Tuist 中打开账户的 **缓存** 设置，并将 **缓存上传访问权限** 设置为 **仅限 CI 和账户令牌**。此后，通过登录会话进行身份验证的成员仍可从缓存下载，但上传需要 CI OIDC 身份验证或具有缓存写入作用域（如 `project:cache:write` 或 `ci`）的账户令牌。

当 CI 是可信的缓存生产者且本地机器应仅消费缓存时使用此设置。该设置仅影响缓存上传授权。
