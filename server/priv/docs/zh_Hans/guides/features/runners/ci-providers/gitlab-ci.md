---
{
  "title": "GitLab CI",
  "titleTemplate": ":title · CI 提供商 · Runner · 功能 · 指南 · Tuist",
  "description": "通过流水线标签选择机器，在 Tuist Runner 上运行 GitLab CI 作业。"
}
---
# GitLab CI {#gitlab-ci}

> [!IMPORTANT]
> **仅限邀请**
>
> Tuist Runners 目前仅限邀请使用。[联系我们](mailto:contact@tuist.dev)以请求为你的账户开通访问权限。

你的流水线保留在 GitLab 中。Tuist 为每个作业提供一台隔离的 Linux 或 macOS 机器，并将日志和结果报告给 GitLab 和 Tuist 仪表板。需要 GitLab 19.3 或更高版本。支持 GitLab.com 以及可通过公共 HTTPS 访问的自托管实例。

1. **创建 GitLab Runner。** 在项目的**Settings → CI/CD → Runners**中，创建一个项目级 Runner。你也可以使用组级 Runner。将所有要使用的 Tuist 配置文件标签添加为 Runner 标签，例如`tuist-linux`和`tuist-macos`，并禁用**Run untagged jobs**。保留 GitLab 显示的身份验证令牌，该令牌以`glrt-`开头。你无需在自己的机器上安装 Runner。
2. **在 Tuist 中连接一次。** 在**Settings → Integrations**中，选择 GitLab CI 卡片上的**Connect**。输入你的 GitLab URL 和 Runner 身份验证令牌。该连接可以为使用不同配置文件的作业提供服务。令牌以加密方式存储，且不会再显示。可选地，添加一个 API 访问令牌，以便合并请求流水线可以保存缓存卷；请参阅[合并请求流水线](#merge-request-pipelines)。
3. **在每个作业中选择机器。** 在作业的`tags`中设置恰好一个<.localized_link href="/guides/features/runners/profiles">Tuist 配置文件标签</.localized_link>。允许其他标签，前提是注册的 GitLab Runner 也具有这些标签：

   ```yaml
   # .gitlab-ci.yml
   linux-check:
     tags: [tuist-linux]
     script:
       - uname -a

   test:
     tags: [tuist-macos]
     script:
       - tuist test
     retry:
       max: 2
       when: runner_system_failure
   ```

4. **推送并观察。** Tuist 会在一分钟内开始轮询。作业将出现在**Runners**下，并提供指向 GitLab 作业、日志和机器指标的链接。GitLab 在作业运行时接收日志；Tuist 在作业完成时接收脱敏后的日志。

Tuist 从每个分配中读取`CI_JOB_TAGS`，并在已连接的 Tuist 账户内解析配置文件。它不会从`CI_RUNNER_TAGS`推断机器，也不会使用默认配置文件。如果缺少、未知或存在多个 Tuist 配置文件标签，获取的作业将失败，并在其 GitLab 日志中提供说明。不要在你的流水线变量中覆盖`CI_JOB_TAGS`。

## 执行环境 {#execution-environment}

作业在隔离的机器内使用 GitLab 的**shell executor**。检出、CI 变量、`before_script`、`script`、`after_script`、产物和取消操作均由 GitLab Runner 处理。流水线的`image:`和`services:`设置不会配置此 shell 环境；请使用安装在<.localized_link href="/guides/features/runners/profiles">runner 镜像</.localized_link>上的工具，或在脚本中安装它们。

可复用的 Runner 身份验证令牌保留在 Tuist 服务器上。机器仅接收其分配作业所需的凭据。目前，GitLab 作业暂不提供缓存签名授权。自定义 Linux 缓存卷通过 GitLab 的 API 验证作业身份并保存权限；可覆盖的 CI 变量无法建立信任。

一旦 Tuist 获取作业，GitLab 就会将其标记为运行中，并开始计时超时。当 Tuist 已获取的作业用尽你账户的并发限制时，后续作业将在 GitLab 中保持挂起状态。已获取的作业会等待机器，最长不超过其作业超时时间（最多 12 小时）。如果届时仍无可用机器，Tuist 将使该分配失败并返回`runner_system_failure`，上述重试策略会让 GitLab 重试该作业。相同的策略也适用于丢失的 Runner 机器。

## 轮换令牌和断开连接 {#rotating-tokens-and-disconnecting}

更新连接的令牌并选择**Save changes**以轮换它们。将令牌留空可保留现有凭据。

**Disconnect**会停止获取并使等待中的分配失败。正在运行的作业继续使用其自身的凭据。如果无法访问 GitLab，Tuist 会在重试取消等待中的分配的同时保留已禁用的连接。待这些分配处理完毕后，连接将被移除。

## 缓存卷 {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">缓存卷</.localized_link>在作业之间保留 Xcode、模块和 Gradle 缓存以及其他目录。在检出之后、在使用它们的命令之前添加这些卷。

### 合并请求流水线 {#merge-request-pipelines}

项目的推送、调度和 Web 流水线会将其更改保存到缓存卷。合并请求流水线会使用缓存，但仅在连接具有 API 访问令牌时才会保存其更改：

1. 在 GitLab 中，创建一个具有**Reporter**角色和`read_api`范围的项目或组访问令牌。组令牌涵盖组内在 Tuist Runners 上运行的所有项目。
2. 在**Settings → Integrations**中，将其粘贴到 GitLab CI 卡片上的**API access token**中，并选择**Save changes**。

随后，Tuist 会读取每个合并请求流水线对应的合并请求。从项目自身分支发起的合并请求流水线会将其更改保存在该合并请求的源分支下，因此 Runner 配置文件的<.localized_link href="/guides/features/runners/cache-volumes#choose-which-branches-save">分支设置</.localized_link>将应用于该分支。来自分叉的合并请求永远不会保存。如果 Tuist 无法读取合并请求，作业仍会运行并使用缓存，但其更改将被丢弃。
