---
{
  "title": "Buildkite",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "Run your first Buildkite job on Tuist Runners: connect your cluster, name a queue after a Tuist profile, and target it from a step."
}
---
# Buildkite {#buildkite}

> [!IMPORTANT]
> **仅限邀请**
>
> Tuist Runners 目前仅限邀请使用。[联系我们](mailto:contact@tuist.dev)或在[社区 Slack](https://slack.tuist.dev)中与我们联系，以请求为您的账户开通访问权限。

Tuist 会监控您 Buildkite 集群中的自托管队列，并在计算资源池中运行找到的作业。您的流水线继续在 Buildkite 上运行；只有计算资源发生变化。在计算资源池上运行作业需要进行三项更改：连接您的集群、将队列命名为与 Tuist <.localized_link href="/guides/features/runners/profiles">配置文件</.localized_link>匹配的名称，并从步骤中指向该队列。

1. **请求访问权限。** 在测试期间，Runners 仅限邀请使用。[联系我们](mailto:contact@tuist.dev)并提供您希望启用的账户。
2. **连接您的集群。** 在 Buildkite 中，打开您的集群，进入**Agent Tokens**并创建一个令牌；它以`bkct_`开头。在您的 Tuist 仪表板中，进入**设置 → 集成**，在 Buildkite 卡片上选择**连接**，然后输入您的组织 slug 和令牌。令牌以加密方式存储，之后不再显示。如果稍后要更改组织或轮换令牌，请编辑卡片上的字段并选择**保存更改**。Tuist 将在一分钟内开始监控该集群。
3. **将队列命名为与 Tuist 配置文件匹配的名称。** 每个已启用的账户都附带两个开箱即用的<.localized_link href="/guides/features/runners/profiles">配置文件</.localized_link>：`linux`和`macos`。当作业的队列键与配置文件的标签匹配时，该作业将被接收。在您的集群中创建键为`tuist-linux`和`tuist-macos`的自托管队列，然后从步骤中指向其中一个：

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

4. **推送并观察。** 作业进入队列后，由 runner 领取，并流式传输回 Tuist 仪表板的**Runners**部分，您可以在那里跟踪其日志、步骤和机器指标。runner 会使用仅针对该作业的作用域凭据从作业内部发送日志，因此不需要 Buildkite API 令牌。

## 暂停和断开连接{#pausing-and-disconnecting}

暂停 Buildkite 队列的分发会阻止 Tuist 从中获取新作业。已在运行的作业不受影响。

在**设置 → 集成**下的 Buildkite 卡片上断开集群连接会使 Tuist 完全停止监控该集群。

## 缓存卷{#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">缓存卷</.localized_link>在作业之间保留 Xcode、模块和 Gradle 缓存以及其他目录。在检出之后、在使用它们的命令之前添加它们。
