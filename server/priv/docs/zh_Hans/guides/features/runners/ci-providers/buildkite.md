---
{
  "title": "Buildkite",
  "titleTemplate": ":title · CI 提供商 · Runner · 功能 · 指南 · Tuist",
  "description": "在 Tuist Runners 上运行你的第一个 Buildkite 作业：连接集群，以 Tuist profile 命名队列，并在步骤中指向该队列。"
}
---
# Buildkite {#buildkite}

> [!IMPORTANT]
> **仅限邀请**
>
> Tuist Runners 目前仅限邀请使用。[联系我们](mailto:contact@tuist.dev)或在[社区 Slack](https://slack.tuist.dev)中留言，为你的账户申请访问权限。

Tuist 会监控你 Buildkite 集群中的自托管队列，并在运行器集群上执行找到的作业。你的流水线继续在 Buildkite 上运行，只是计算资源发生了变化。要在运行器集群上运行作业，需要进行三项更改：连接你的集群、将队列命名为与 Tuist <.localized_link href="/guides/features/runners/profiles">profile</.localized_link>匹配的名称，并在步骤中指定该队列。

1. **申请访问权限。** 在测试期间，Runners 仅限邀请使用。[联系我们](mailto:contact@tuist.dev)并提供你希望启用的账户。
2. **连接你的集群。** 在 Buildkite 中，打开你的集群，进入**Agent Tokens**并创建一个令牌；该令牌以`bkct_`开头。在 Tuist 仪表板中，进入**Settings → Integrations**，在 Buildkite 卡片上选择**Connect**，然后输入你的组织 slug 和令牌。令牌会以加密方式存储，之后不再显示。如果以后需要更改组织或轮换令牌，请编辑卡片上的字段并选择**Save changes**。Tuist 将在一分钟内开始监控该集群。
3. **将队列命名为与 Tuist profile 匹配的名称。** 每个已启用的账户都附带两个可直接使用的<.localized_link href="/guides/features/runners/profiles">profiles</.localized_link>：`linux`和`macos`。当作业的队列键与某个 profile 的标签匹配时，该作业会被接收。在你的集群中创建键为`tuist-linux`和`tuist-macos`的自托管队列，然后在步骤中指定其中一个：

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

4. **推送并观察。** 作业会被加入队列，由运行器领取，并将日志流式传输回 Tuist 仪表板的**Runners**部分，你可以在此查看其日志、步骤和机器指标。运行器会使用仅对该作业有效的凭证从作业内部发送日志，因此不需要 Buildkite API 令牌。

## 暂停和断开连接 {#pausing-and-disconnecting}

暂停 Buildkite 队列的分发会阻止 Tuist 从该队列获取新作业。已经在运行的作业不受影响。

在**Settings → Integrations**下的 Buildkite 卡片上断开集群连接，会使 Tuist 完全停止监控该集群。

## 缓存卷 {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">cache volumes</.localized_link>在作业之间保留 Xcode、模块和 Gradle 缓存以及其他目录。在检出代码之后、在使用这些目录的命令之前添加它们。
