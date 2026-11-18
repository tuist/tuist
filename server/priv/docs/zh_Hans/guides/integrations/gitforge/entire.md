---
{
  "title": "Entire",
  "titleTemplate": ":title | Git 托管平台 | 集成 | 指南 | Tuist",
  "description": "在 Entire Trails 上发布 Tuist 的构建、测试、包体积和预览洞察。"
}
---
# Entire 集成 {#entire}

Tuist 会在每个已连接仓库的开放或草稿状态 [Trail](https://docs.entire.com/guides/trails/overview) 上维护一份摘要讨论。该摘要包含可用的构建结果、测试失败和不稳定测试、包大小以及应用预览，并提供指向 Tuist 上完整报告的链接。

> [!IMPORTANT]
> **早期访问**
>
> Entire 插件需要合作伙伴注册，其 Trail 讨论和 Webhook 契约仍处于实验阶段。你的 Tuist 管理员可以为所有账户或选定账户启用此集成。你的 Entire 项目也必须被允许安装已注册的插件。

## 设置 {#setup}

安装流程与 GitHub 集成相同：先为你的账户安装插件，然后将仓库连接到 Tuist 项目。在托管版 Tuist 中，管理员负责插件注册和服务器配置；你只需执行以下步骤。

1. 打开你账户的 **Settings → Integrations**。
2. 在 **Entire** 中，选择 **Install Entire plugin**。选择你希望与 Tuist 共享的 Entire 项目和仓库。

   ![从账户集成中安装 Entire 插件](/images/guides/integrations/gitforge/entire/integrations.png)

3. 返回 Tuist，选择 **Add new project connection**。在 **Choose repository to connect to** 中，选择你的 Tuist 项目和 Entire 仓库，然后选择 **Create Connection**。如果只有一个可用的 Tuist 项目，它将被自动选中。

   ![将 Tuist 项目连接到 Entire 仓库](/images/guides/integrations/gitforge/entire/add-project-connection.png)

4. 继续使用你现有的已认证 Tuist 命令从 CI 上传洞察数据。Tuist 会将这些数据匹配到每个 Trail 的当前提交 SHA；无需使用任何 Entire 专属的 CLI 标志。

Tuist 项目可以在保留 GitHub 连接的同时，也将摘要发布到 Entire。这对于 GitHub 镜像很有用。Trail 摘要不需要 Tuist 的 CI 执行器，也不会更改你现有的 CI 提供商。

随着洞察数据的到达，Tuist 会更新同一份讨论。打开或重新打开 Trail 时，也会获取其头部提交之前已上传的洞察数据。已关闭和已合并的 Trail 不会更新。旧提交的结果永远不会作为当前头部的结果呈现。如果当前提交没有洞察数据，Tuist 会保持现有摘要不变；每条结果都包含其提交哈希。

要移除项目连接，请打开其 **Manage** 菜单并选择 **Remove connection**，操作方式与 GitHub 相同。这将停止未来的更新并删除 Tuist 的本地讨论指针。已发布的评论仍保留在 Entire 上。重新连接后，如果现有摘要仍可访问，则会被恢复。要更改插件的仓库访问权限或卸载插件，请在 Entire 中使用项目的 **Plugins** 设置。

## 服务器配置 {#server-configuration}

本节面向 Tuist 服务器运营者。使用 [plugin registration guide](https://docs.entire.com/guides/api/plugins/register) 向 Entire 注册插件。请求 `contents:read` 和 `discussions:write`。读取权限用于获取 Trail 事件和发现讨论；不需要仓库写入权限。

配置以下服务器环境变量：

| 变量 | 用途 |
| --- | --- |
| `TUIST_ENTIRE_PLUGIN_SLUG` | 由 Entire 确认的 Slug |
| `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY` | PEM 格式的 Ed25519 私钥，通过你的密钥存储提供 |
| `TUIST_ENTIRE_PLUGIN_KEY_ID` | 使用基于 JWKS 的密钥注册时的密钥 ID；否则为可选 |
| `TUIST_ENTIRE_CORE_URL` | 用于安装请求的 Entire Core；默认为 `https://eu.auth.entire.io` |
| `TUIST_ENTIRE_DELIVERY_JWKS_URL` | 注册时由 Entire 提供的 Webhook 签名密钥 URL |

对于托管 Helm 部署，将私有 PEM 存储在环境的 1Password 保险库中，命名为 `ENTIRE_PLUGIN/private_key`，然后同时启用 `server.config.entirePluginKey.enabled` 和 `server.config.managedSecrets`。External Secrets 通过现有的 server-config Secret 提供 `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY`，且不会截断多行 PEM。可以通过 `server.config.entirePluginKey.item` 和 `.field` 配置项名称和字段名称。此映射默认关闭，且不配置 slug 或 Webhook 签名密钥 URL；请在注册后单独提供这些值。每个环境应使用自己的签名密钥。仅与 Entire 共享公共 PEM，切勿共享私钥。

将 `https://<your-tuist-host>/integrations/entire/callback` 注册为安装后回调 URL，将 `https://<your-tuist-host>/webhooks/entire` 注册为 Webhook URL。应用服务器迁移后，全局启用 `entire_trails` 功能标志以向所有账户提供此集成，或为选定账户启用。如需公开推广，请联系你的 Entire 对接人，允许在插件所属项目之外进行安装；启用 Tuist 功能标志不会改变 Entire 的安装策略。Entire Trail 摘要独立于 Tuist 的 CI 执行配置和功能标志。

Tuist 会验证安装回执和 Webhook 签名，颁发短生命周期的仓库范围令牌，并在发布前发现每个仓库的当前处理区域。令牌绝不会嵌入报告链接中。
