---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "Run your first GitHub Actions job on Tuist Runners: connect GitHub, point runs-on at a Tuist profile, and watch it in the dashboard."
}
---
# GitHub Actions {#github-actions}

> [!IMPORTANT]
> **仅限邀请**
>
> Tuist Runners 目前仅限邀请使用。[联系我们](mailto:contact@tuist.dev)或在[社区 Slack](https://slack.tuist.dev)中与我们取得联系，以请求为您的账户开通访问权限。

在集群上运行作业需要进行三项更改：连接 GitHub，将`runs-on`指向 Tuist <.localized_link href="/guides/features/runners/profiles">配置文件</.localized_link>，然后推送代码。

1. **请求访问权限。** 在测试期间，Runners 仅限邀请使用。[联系我们](mailto:contact@tuist.dev)并提供您希望启用的账户。
2. **连接 GitHub。** 确保您的项目已<.localized_link href="/guides/integrations/gitforge/github">连接到您的 GitHub 组织</.localized_link>。Tuist 会接收该组织的`workflow_job`事件，并将匹配的作业分派到集群。如果没有此连接，作业将无法到达您的 runners。
3. **将`runs-on`指向 Tuist 配置文件。** 每个已启用的账户都自带两个开箱即用的<.localized_link href="/guides/features/runners/profiles">配置文件</.localized_link>：`linux`和`macos`。使用`tuist-`前缀来引用它们：

   ```yaml
   jobs:
     build:
       runs-on: tuist-macos # or tuist-linux
       steps:
         - uses: actions/checkout@v4
         - run: tuist test
   ```

   > [!IMPORTANT]
   > **通过 runner 配置文件选择 Xcode**
   >
   > macOS runner 镜像包含单个 Xcode 版本，Tuist 会根据配置文件在作业开始前进行选择。如果您从 GitHub 托管的 runners 迁移过来，请移除使用`xcode-select --switch`（或`xcode-select -s`）或其他工具和动作来切换 Xcode 版本的步骤。这些步骤通常引用特定于 GitHub 托管镜像的 Xcode 安装，可能在 Tuist Runners 上失败。
   >
   > 要使用其他 Xcode 版本，请<.localized_link href="/guides/features/runners/profiles#creating-a-profile">创建或选择一个包含该版本的配置文件</.localized_link>并更新`runs-on`，例如`runs-on: tuist-xcode-26-4`。`xcodebuild`、`xcrun`和`swift`随后将使用配置文件所选的 Xcode，无需在工作流中进行任何其他设置。

4. **推送并观察。** 作业会被排队，由 runner 领取，并流式传输回 Tuist 仪表板的**Runners**部分，您可以在那里跟踪其日志、步骤和机器指标。

## 缓存卷{#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">缓存卷</.localized_link>在作业之间保留 Xcode、模块和 Gradle 缓存以及其他目录。在检出之后和使用它们的命令之前添加它们。
