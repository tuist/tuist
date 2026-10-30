---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git 代码托管平台 | 集成 | 指南 | Tuist",
  "description": "了解如何将 Tuist 与 GitHub 集成，以优化工作流。"
}
---
# GitHub 集成 {#github}

Git 仓库是绝大多数软件项目的核心。我们与 GitHub 集成，以便在你的拉取请求中直接提供 Tuist 洞察，并节省部分配置工作，例如同步默认分支。

## 设置 {#setup}

你需要在组织的 `Integrations` 标签页中安装 Tuist GitHub 应用：![显示集成标签页的图片](/images/guides/integrations/gitforge/github/integrations.png)

你也可以直接从 GitHub 安装该应用。如有需要，请登录 Tuist，授权 GitHub 应用以便 Tuist 验证你对安装的访问权限，然后选择要连接的 Tuist 组织。你必须拥有安装该应用的 GitHub 组织（或个人 GitHub 账户）。仅显示你管理的 Tuist 组织和你的个人 Tuist 账户。如果只有一个可用账户，Tuist 会自动连接，不会显示选择器。当你从 Tuist 开始时，组织已预先选中，此步骤将被跳过。

之后，你可以在 GitHub 仓库与 Tuist 项目之间添加项目连接：

![显示添加项目连接的图片](/images/guides/integrations/gitforge/github/add-project-connection.png)

安装应用后，你也可以在不使用仪表板的情况下链接项目：

- **CLI：**`tuist project repository connect owner/name`，并使用 `tuist project repository disconnect` 移除链接。
- **REST API：** 对 `/api/projects/{account_handle}/{project_handle}/vcs-connection` 执行 `PUT` 和 `DELETE`。
- **Model Context Protocol：**`connect_project_repository` 和 `disconnect_project_repository` 工具。

该仓库必须是 GitHub 应用安装可访问的仓库，且项目采用仓库的默认分支。账户令牌需要 `project:admin:write` 作用域。

> [!TIP]
> **IP 允许列表**
>
> 如果你的 GitHub 组织使用 [IP 允许列表](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization)，或者你的 GitHub 实例位于防火墙后面，请确保将 Tuist 的 <.localized_link href="/guides/server/network#outbound-ip-addresses">出站 IP 地址</.localized_link> 加入允许列表，以便集成能够与你的仓库通信。

### GitHub Enterprise Server {#github-enterprise-server}

Tuist 还与自托管的 GitHub Enterprise Server (GHES) 实例集成。在 GitHub 集成卡片中，切换到 **Enterprise server** 标签页，输入你的 GHES 基础 URL（例如 `https://github.example.com`），然后点击安装。

由于 GitHub 应用限定于单个 GitHub 实例，Tuist 无法在其 github.com 应用上复用于你的 GHES——相反，安装按钮会引导你完成 GitHub 的 [App manifest flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)：GHES 会指导管理员在该实例上注册一个新的 Tuist 应用，然后将新应用的凭据交还给 Tuist。Tuist 会以每安装为单位加密存储这些凭据，并从此将其用于每次 API 调用、webhook 签名以及指向你仓库的链接。

无需额外的 Tuist 服务器配置；manifest 流程会自动生成并提供所有内容。

#### 应用权限和 webhook 事件 {#github-app-permissions}

Tuist 需要以下 **仓库权限** 以支持 PR 评论和包大小检查：

| 权限 | 访问级别 | 用途 |
|---|---|---|
| 元数据 (`metadata`) | 只读 | 基本仓库元数据；GitHub 要求每个应用都具备此权限 |
| 拉取请求 (`pull_requests`) | 读写 | 读取拉取请求（包括其头提交 SHA），以及列出、发布和更新 PR 评论 |
| 检查 (`checks`) | 读写 | 创建和更新检查运行，包括包大小的通过/失败检查 |

Tuist 使用 `check_run` webhook 事件来处理包大小检查操作。manifest 流程会自动配置此订阅。

对于在 github.com 上使用自托管 Tuist 服务器的手动应用设置，请参阅 <.localized_link href="/guides/server/self-host/server#platform-github-registering-the-app">自托管指南</.localized_link>。

#### 独立的浏览器和 API URL {#separate-browser-and-api-urls}

如果工程师通过内部主机名访问 GitHub Enterprise，而第三方服务使用外部代理，请在点击安装前配置这两个地址：

| 字段 | 示例 | 使用者 |
|---|---|---|
| **Server URL** | `https://github.internal.company.com` | 你的浏览器，用于应用注册和安装，以及从 Tuist 指向 GitHub 的链接 |
| **API URL** | `https://github-proxy.company.com/api/v3` | Tuist 的服务器，用于 manifest-code 交换、访问令牌、仓库访问、PR 评论和检查 |

API URL 是完整的 REST API 基础 URL，包括 `/api/v3` 或你的代理公开的等效路径。Tuist 不会向显式的 API URL 追加 `/api/v3`。如果一个主机名同时适用于你的浏览器和 Tuist，请将其留空；现有连接将继续使用 `<Server URL>/api/v3`。

这两个地址都必须路由到 **同一个 GitHub Enterprise 实例**。你的浏览器只需能够访问 Server URL，无需访问 API 代理。Tuist 的服务器只需能够访问 API URL，无需访问内部浏览器主机名。

对于外部代理：

- 使用 HTTPS，并采用 Tuist 服务器信任的证书，且公共 DNS 解析为公共 IP 地址。API URL 覆盖不会绕过 Tuist 的私有 IP/SSRF 保护。覆盖必须指向你的 Enterprise 实例，而不是 `github.com` 或 `*.github.com` 端点。
- 将每个 Tuist <.localized_link href="/guides/server/network#outbound-ip-addresses">出站 IP 地址</.localized_link> 加入允许列表。
- 转发 Tuist 使用的 REST API 端点，包括 `POST /api/v3/app-manifests/{code}/conversions`、`POST /api/v3/app/installations/{installation_id}/access_tokens` 以及用于评论和检查的仓库 API 端点。这些是 GitHub 的上游路径；如果你的代理公开了不同的前缀，请相应转换它们。
- 将请求转发到 GitHub，不要使用 HTTP 重定向或交互式登录页面。Tuist 不会自动跟随 Enterprise API 重定向，因此它们无法绕过公共 IP 检查。在设置期间，在 Tuist 获得应用凭据之前，manifest 转换端点必须是可访问的。GitHub Actions 日志下载是一个例外：Tuist 仅通过 HTTPS 跟随签名的归档重定向，检查并将每个目标固定到公共 IP，且不转发安装令牌。

GitHub 可能会使用其内部主机名返回分页链接。Tuist 会将来自配置的 GitHub 实例的链接重新基于 API URL，保留你代理的路径前缀；指向无关来源的链接将被拒绝。

另外，GitHub 必须能够将 webhook 交付到 `https://tuist.dev/webhooks/github`（或者在你自托管的 Tuist 服务器上为 `/webhooks/github`）。工程师必须能够返回 Tuist 以完成浏览器回调。API URL 不会改变这两个目的地。

组织管理员还可以使用集成卡片中的 **Save API URL** 来更改或清除现有 Enterprise 集成上的 API URL。无需重新安装应用或重新连接项目。清除它将恢复 `<Server URL>/api/v3`。保存操作会验证 URL 格式，而不是代理连通性。由于安装查找会被缓存，webhook 处理可能需要长达一分钟才能使用更改后的地址；已经在途的请求可能仍会使用之前的地址。

> [!NOTE]
> **仅在托管的 Tuist 服务器上提供 Enterprise 计划**
>
> 在托管的 Tuist 服务器 (`https://tuist.dev`) 上，GitHub Enterprise Server 集成仅适用于 **Enterprise** 计划的组织。自托管的 Tuist 部署可以在任何计划上使用它。

## 拉取/合并请求评论 {#pull-merge-request-comments}

GitHub 应用会发布 Tuist 运行报告，其中包括 PR 摘要，以及指向最新 <.localized_link href="/guides/features/previews#pullmerge-request-comments">预览</.localized_link> 或 <.localized_link href="/guides/features/selective-testing#pullmerge-request-comments">测试</.localized_link> 的链接：

Tuist 会在结果到达时更新一条评论。Gradle 构建会为每个根项目和请求的任务集单独显示；重新运行相同的任务会替换该次调用的先前结果。完整的构建历史记录仍然可在 Tuist 上查看。

评论默认启用，以保留现有集成的报告功能。要为项目关闭或重新开启评论，请打开 **Project Settings → Integrations** 并切换 **GitHub → Run report comments**。每个项目都有自己的设置；仓库连接仍在组织设置中管理。

禁用评论不会禁用构建或测试上传、GitHub Actions 作业摘要、仓库连接或其他 GitHub 集成功能。现有评论不会被删除。

![显示拉取请求评论的图片](/images/guides/integrations/gitforge/github/pull-request-comment.png)

> [!NOTE]
> **要求**
>
> 仅当你的 CI 运行已 <.localized_link href="/guides/integrations/continuous-integration#authentication">认证</.localized_link> 时，才会发布评论。

> [!NOTE]
> **Github_ref**
>
> 如果你有一个自定义工作流，它不是由 PR 提交触发，而是例如由 GitHub 评论触发，你可能需要确保 `GITHUB_REF` 变量设置为 `refs/pull/<PR_NUMBER>/merge` 或 `refs/pull/<PR_NUMBER>/head`。
>
> 你可以运行相关命令，例如 `tuist share`，并使用前缀 `GITHUB_REF` 环境变量：<code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist share</code>

## GitHub Actions 作业摘要 {#github-actions-job-summary}

Tuist CLI 和 Gradle 插件将测试和构建结果写入 GitHub Actions 中的 [作业摘要](https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/)。该摘要链接到 Tuist 上的完整报告，其中提供更丰富的见解，例如不稳定测试和包大小差异。

对于 Gradle，每个成功上传的构建或测试报告都会附加其自己的摘要，保留由 `gradle/actions/setup-gradle` 等工具写入的其他内容。这需要包含作业摘要支持的插件版本；较旧的 Gradle 插件版本仅通过 GitHub 应用的 PR 评论进行报告。作业摘要不需要连接 GitHub 应用，禁用 **Run report comments** 也不会影响它们。

当 GitHub Actions 摘要目的地可用时，Gradle 会在退出前等待上传和摘要完成，即使启用了 `uploadInBackground`。GitHub 会在工作流步骤结束时捕获摘要。

![显示 GitHub Actions 作业摘要中 Tuist 运行报告的图片](/images/guides/integrations/gitforge/github/github-actions-job-summary.png)

这在配合 [合并队列](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue) 使用时特别有用。合并队列运行不附加到拉取请求，因此不会发布评论，但作业摘要仍会显示结果。

> [!NOTE]
> **要求**
>
> 作业摘要需要成功的报告上传。在托管的 Tuist 服务器上，你的 CI 运行必须 <.localized_link href="/guides/integrations/continuous-integration#authentication">认证</.localized_link>。自托管实例在启用网络可信报告发布时，也可以接受无凭据的报告。
