---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI 提供商 · 运行器 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 运行器上运行你的首个 GitHub Actions 作业：连接 GitHub，将 runs-on 指向 Tuist 配置文件，然后在仪表盘中监控其执行情况。"
}
---
# GitHub Actions {#github-actions}

<!-- @snippet: ./_invite-only -->

在集群上运行作业需要进行三项更改：连接 GitHub、将 `runs-on` 指向 Tuist <.localized_link href="/guides/features/runners/profiles">配置文件</.localized_link>，然后推送代码。

1. **连接 GitHub。** 确保你的项目已<.localized_link href="/guides/integrations/gitforge/github">连接到你的 GitHub 组织</.localized_link>。Tuist 会接收该组织的 `workflow_job` 事件，并将匹配的作业分派到集群。如果没有此连接，作业将无法到达你的 Runner。
2. **将 `runs-on` 指向 Tuist 配置文件。** 每个启用的账户都预置了两个可直接使用的<.localized_link href="/guides/features/runners/profiles">配置文件</.localized_link>：`linux` 和 `macos`。使用 `tuist-` 前缀来引用它们：

   ```yaml
   jobs:
     build:
       runs-on: tuist-macos # or tuist-linux
       steps:
         - uses: actions/checkout@v4
         - run: tuist test
   ```

   > [!IMPORTANT]
   > **通过 Runner 配置文件选择 Xcode**
   >
   > macOS Runner 镜像包含单个 Xcode 版本，Tuist 会在作业开始前根据配置文件进行选择。如果你正在从 GitHub 托管的 Runner 迁移，请移除使用 `xcode-select --switch`（或 `xcode-select -s`）或其他工具和 Action 来切换 Xcode 版本的步骤。这些步骤通常引用特定于 GitHub 托管镜像的 Xcode 安装路径，在 Tuist Runner 上可能会失败。
   >
   > 要使用其他 Xcode 版本，请<.localized_link href="/guides/features/runners/profiles#creating-a-profile">创建或选择一个包含该版本的配置文件</.localized_link>并更新 `runs-on`，例如 `runs-on: tuist-xcode-26-4`。`xcodebuild`、`xcrun` 和 `swift` 随后将使用配置文件所选的 Xcode，无需在工作流中进行额外设置。

3. **推送并观察。** 作业会被加入队列，由 Runner 领取，并将其日志流式传输回 Tuist 仪表板的**Runners**部分，你可以在此跟踪其日志、步骤和机器指标。

## 缓存卷 {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">缓存卷</.localized_link>在作业之间保留 Xcode、模块和 Gradle 缓存以及其他目录。在检出代码之后、在使用它们的命令之前添加这些配置。

为作业授予 `id-token: write` 权限，以便其缓存卷和缓存的检出内容在作业启动时立即挂载。如果没有此权限，Runner 会等待 GitHub 报告其正在运行的作业，而 GitHub 延迟报告的作业将以空缓存启动。使用 OpenID Connect 登录 Tuist 的工作流已自动授予此权限。

```yaml
permissions:
  contents: read
  id-token: write
```
