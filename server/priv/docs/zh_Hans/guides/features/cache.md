---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize build times with Tuist Cache, including module cache, Xcode cache, Gradle cache, Bazel cache, Elixir dependency cache, and experimental Rust compilation caching."
}
---
# 缓存 {#cache}

构建产物无法在不同环境之间共享，导致你不得不反复重新构建相同的代码。Tuist 的缓存功能可以远程共享这些产物，让你的团队和 CI 无需重新构建已构建过的内容，从而获得更快的构建速度。

了解与你的项目或部署模型相匹配的缓存工作流：

<.home_cards>
  <.home_card
    title="模块缓存"
    details="将单个模块缓存为二进制文件，适用于使用 Tuist 生成项目的项目。需要 Tuist 项目生成。"
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcode 缓存"
    details="在不同环境之间共享 Xcode 编译产物。适用于任何 Xcode 项目，无需项目生成。"
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Gradle 缓存"
    details="远程共享 Gradle 构建缓存产物。包含用于性能可见性的构建洞察。"
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Bazel 缓存"
    details="将 Bazel 指向 Tuist 的远程执行 API 缓存，以在团队和 CI 之间共享操作输出。"
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Elixir 缓存"
    details="为受支持的 Elixir 依赖项启用缓存并继续使用 Mix。在仪表板中检查缓存命中和传输情况。"
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Rust 缓存（实验性）"
    details="在本地并通过 Kura 重用受支持的注册表叶库输出。了解如何启用缓存并检查缓存活动。"
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="自托管"
    details="在靠近 CI、办公室或区域计算资源的位置运行缓存节点，并将它们连接到托管或自托管的 Tuist。"
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **在 Tuist Runners 上最快**
>
> 在 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 上，缓存位于运行器的私有网络中，并与你的开发人员机器使用的同一缓存共享，因此 CI 作业开箱即用即可获得热命中，无需单独预热 CI 缓存。


## 限制仅允许 CI 上传 {#restrict-uploads-to-ci}

账户管理员可以将开发人员设置为只读，同时允许 CI 上传缓存产物。在 Tuist 中打开账户的 **缓存** 设置，并将 **缓存上传访问权限** 设置为 **仅限 CI 和账户令牌**。此后，通过登录会话认证的成员仍然可以从缓存下载，但上传需要 CI OIDC 认证或具有缓存写入范围（如 `project:cache:write` 或 `ci`）的账户令牌。

当 CI 是可信的缓存生产者且本地机器应仅消费缓存时使用此设置。该设置仅影响缓存上传授权。
