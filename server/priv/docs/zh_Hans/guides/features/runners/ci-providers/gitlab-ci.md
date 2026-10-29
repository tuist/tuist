---
{
  "title": "GitLab CI",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "Run GitLab CI jobs on Tuist Runners with machine selection through pipeline tags."
}
---
# GitLab CI {#gitlab-ci}

> [!IMPORTANT]
> **仅限邀请**
>
> Tuist Runners 目前仅限邀请使用。[联系我们](mailto:contact@tuist.dev)以请求为您的账户开通访问权限。

您的流水线保留在 GitLab 中。Tuist 为每个作业提供一台隔离的 Linux 或 macOS 机器，并将其日志和结果报告给 GitLab 和 Tuist 仪表板。需要 GitLab 19.3 或更高版本。支持 GitLab.com 以及可通过公共 HTTPS 访问的自托管实例。

1. **创建 GitLab Runner。** 在项目的**设置 → CI/CD → Runners**中，创建一个项目 Runner。您也可以使用组 Runner。添加您希望用作 Runner 标签的所有 Tuist 配置文件标签，例如`tuist-linux`和`tuist-macos`，并禁用**运行未标记的作业**。保留 GitLab 显示的身份验证令牌，该令牌以`glrt-`开头。您无需在自己的机器上安装 Runner。
2. **在 Tuist 中连接一次。** 在**设置 → 集成**中，选择 GitLab CI 卡片上的**连接**。输入您的 GitLab URL 和 Runner 身份验证令牌。该连接可以为使用不同配置文件的作业提供服务。令牌以加密方式存储，且不会再显示。您可以选择添加 API 访问令牌，以便合并请求流水线可以保存缓存卷；请参阅[合并请求流水线](#merge-request-pipelines)。
3. **在每个作业中选择机器。** 在作业的`tags`中设置恰好一个<.localized_link href="/guides/features/runners/profiles">Tuist 配置文件标签</.localized_link>。允许使用其他标签，前提是注册的 GitLab Runner 也具有这些标签：

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

4. **推送并观察。** Tuist 会在一分钟内开始轮询。作业将显示在**Runners**下，并提供指向 GitLab 作业、日志和机器指标的链接。GitLab 在作业运行时接收日志；Tuist 在作业完成时接收脱敏后的日志。

Tuist 从每个分配中读取`CI_JOB_TAGS`，并在连接的 Tuist 账户内解析配置文件。它不会从`CI_RUNNER_TAGS`推断机器或使用默认配置文件。如果缺少、未知或存在多个 Tuist 配置文件标签，已获取的作业将失败，并在其 GitLab 日志中提供说明。不要在流水线变量中覆盖`CI_JOB_TAGS`。

## 执行环境 {#execution-environment}

作业在隔离的机器内使用 GitLab 的**shell 执行器**。检出、CI 变量、`before_script`、`script`、`after_script`、构件和取消操作均由 GitLab Runner 处理。流水线的`image:`和`services:`设置不会配置此 shell 环境；请使用安装在<.localized_link href="/guides/features/runners/profiles">Runner 镜像</.localized_link>上的工具，或在脚本中安装它们。

可复用的 Runner 身份验证令牌保留在 Tuist 服务器上。机器仅接收其分配作业所需的凭据。目前，GitLab 作业暂不提供缓存签名授权。自定义 Linux 缓存卷通过 GitLab 的 API 验证作业身份和保存权限；可覆盖的 CI 变量无法建立信任。

一旦 Tuist 获取作业，GitLab 就会将其标记为运行中，并开始其超时计时。当 Tuist 已获取的作业占用了您账户的并发限制时，后续作业将在 GitLab 中保持挂起状态。已获取的作业等待机器的时间最多为其作业超时时间，最长为 12 小时。如果届时仍无可用机器，Tuist 将使分配失败并返回`runner_system_failure`，上述重试策略将允许 GitLab 重试该作业。相同的策略也适用于丢失的 Runner 机器。

## 轮换令牌和断开连接 {#rotating-tokens-and-disconnecting}

更新连接的令牌并选择**保存更改**以轮换它们。将令牌留空可保留现有凭据。

**断开连接**将停止获取并使等待中的分配失败。正在运行的作业将继续使用其自身的凭据。如果无法访问 GitLab，Tuist 将保留已禁用的连接，同时重试取消等待中的分配。一旦这些分配已解决，连接将被移除。

## 缓存卷 {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">缓存卷</.localized_link>在作业之间保留 Xcode、模块和 Gradle 缓存以及其他目录。在检出之后和使用它们的命令之前添加它们。

### 合并请求流水线 {#merge-request-pipelines}

项目的推送、计划和 Web 流水线将其更改保存到缓存卷。合并请求流水线使用缓存，并且仅在连接具有 API 访问令牌时才保存其更改：

1. 在 GitLab 中，创建一个具有**Reporter**角色和`read_api`范围的项目或组访问令牌。组令牌涵盖在 Tuist Runners 上运行的组中的每个项目。
2. 在**设置 → 集成**中，将其粘贴到 GitLab CI 卡片上的**API 访问令牌**中，然后选择**保存更改**。

随后，Tuist 会读取每个合并请求流水线的合并请求。从项目本身的分支打开的合并请求的流水线会将其更改保存在合并请求的源分支下，因此 Runner 配置文件的<.localized_link href="/guides/features/runners/cache-volumes#choose-which-branches-save">分支设置</.localized_link>适用于该分支。来自 fork 的合并请求永远不会保存。如果 Tuist 无法读取合并请求，作业仍会运行并使用缓存，但其更改将被丢弃。
