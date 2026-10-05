---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize build times with Tuist Cache, including module cache, Xcode cache, Gradle cache, and Bazel cache."
}
---
# 缓存 {#cache}

构建产物无法在不同环境之间共享，导致你不得不反复重新构建相同的代码。Tuist 的缓存功能通过远程共享构建产物，让你的团队和 CI 能够更快地完成构建，无需重复构建已构建过的内容。

了解适合你的项目或部署模型的缓存工作流：

\<.home\_cards\>
\<.home\_card
title="模块缓存"
details="将各个模块缓存为二进制文件，适用于使用 Tuist 生成项目的项目。需要 Tuist 项目生成功能。"
link="/guides/features/cache/module-cache"
/\>
\<.home\_card
title="Xcode 缓存"
details="在不同环境之间共享 Xcode 编译产物。适用于任何 Xcode 项目，无需项目生成。"
link="/guides/features/cache/xcode-cache"
/\>
\<.home\_card
title="Gradle 缓存"
details="远程共享 Gradle 构建缓存产物。包括用于性能可见性的构建洞察。"
link="/guides/features/cache/gradle-cache"
/\>
\<.home\_card
title="Bazel 缓存"
details="将 Bazel 指向 Tuist 的远程执行 API 缓存，以在你的团队和 CI 之间共享操作输出。"
link="/guides/features/cache/bazel-cache"
/\>
\<.home\_card
title="自托管"
details="在靠近 CI、办公室或区域计算资源的地方运行缓存节点，并将它们连接到托管或自托管的 Tuist。"
link="/guides/features/cache/self-hosting"
/\>
\</.home\_cards\>

> \[\!TIP\]
> **在 Tuist Runners 上速度最快**
> 
> 在 \<.localized\_link href="/guides/features/runners"\>Tuist Runners\</.localized\_link\> 上，缓存位于运行器的私有网络中，并与你的开发者机器使用的相同缓存共享，因此 CI 作业开箱即用即可获得预热命中，无需单独预热 CI 缓存。

## 限制仅允许 CI 上传 {#restrict-uploads-to-ci}

账户管理员可以将开发者设置为只读权限，同时允许 CI 上传缓存产物。在 Tuist 中打开账户的 **缓存** 设置，并将 **缓存上传访问权限** 设置为 **仅限 CI 和账户令牌**。此后，通过登录会话认证的成员仍然可以从缓存下载，但上传需要 CI OIDC 认证或具有缓存写入范围（如 `project:cache:write` 或 `ci`）的账户令牌。

当 CI 是受信任的缓存生产者，而本地机器仅应消费缓存时，请使用此设置。该设置仅影响缓存上传授权。