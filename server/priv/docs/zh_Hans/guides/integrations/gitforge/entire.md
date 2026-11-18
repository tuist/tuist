---
{
  "title": "Entire",
  "titleTemplate": ":title | Git 代码托管平台 | 集成 | 指南 | Tuist",
  "description": "在 Entire Trails 上发布 Tuist 的构建、测试、包体积和预览洞察。"
}
---
# Entire 集成 {#entire}

Tuist 可以在 [Entire](https://entire.com) 代码库中处于开启状态或草稿状态的 [Trails](https://docs.entire.com/guides/trails/overview) 上发布构建、测试、预览和包的分析结果。每个 Trail 都会获得一个 Tuist 门禁，其中包含运行报告、针对失败和不稳定测试的全量变更发现项，以及一条摘要评论；Tuist 会在有新分析结果时更新该评论，而不是为每次上传都发布新评论。

安装插件不会执行构建或测试。你现有的工作流会继续将结果上传到 Tuist，而该集成会将这些结果引入你的 Trails。

## 设置 {#setup}

由 Tuist 账户的管理员安装插件，然后将代码库连接到 Tuist 项目，操作方式与 <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link> 和 <.localized_link href="/guides/integrations/gitforge/origin">Origin</.localized_link> 集成相同。

1. 打开你账户的 **Settings → Integrations**。
2. 在 Entire 卡片中，选择 **Install Entire plugin**。选择你想要与 Tuist 共享的 Entire 项目和代码库。

   ![从账户集成安装 Entire 插件](/images/guides/integrations/gitforge/entire/integrations.png)

3. 回到 Tuist，选择 **Add new project connection**。在 **Choose repository to connect to** 中，选择你的 Tuist 项目和 Entire 代码库，然后选择 **Create Connection**。如果只有一个可用的 Tuist 项目，它会被自动选中。

   ![将 Tuist 项目连接到 Entire 代码库](/images/guides/integrations/gitforge/entire/add-project-connection.png)

4. 继续使用你现有的、已认证的 Tuist 命令从 CI 上传结果，例如使用 <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>。Tuist 会将结果匹配到每个 Trail 的当前头提交，因此不需要任何 Entire 专属的标志位。

Tuist 项目可以在保留其 GitHub 连接的同时向 Entire 发布结果，这在 Entire 代码库镜像 GitHub 代码库时非常有用。该集成不需要 Tuist 的 CI 执行器，也不会更改你的 CI 提供商。

## 报告与权限 {#reports-and-permissions}

在安装插件时，你需要授予它查找 Trails 和发布报告所需的权限：

| 权限 | 用途 |
| --- | --- |
| Repository contents: read | 接收 Trail 事件，并查找带有其头提交的处于开启状态或草稿状态的 Trails。 |
| Checks: write | 在 Trail 的头提交上发布 Tuist 门禁。 |
| Findings: write | 将失败的测试和不稳定测试作为发现项发布，并解决被更新报告取代的发现项。 |
| Discussions: write | 发布并更新摘要评论。即使没有此权限，Tuist 仍会发布门禁和发现项。 |

Tuist 不需要对你源代码的写入权限，也不需要合并 Trails 的权限。

Tuist 会在每个 Trail 上发布三项内容：

- **门禁：** Tuist 检查会出现在 **Gates** 下，附带运行报告和指向 Tuist 上项目的链接。它列在 Tuist 插件下，与 GitHub 镜像的 **Checks** 门禁分开。它以 `neutral` 结论完成，Entire 将其显示为通过，因为上传的结果无法告知 Tuist 是否所有预期的 CI 作业都已完成。即使存在发现项，它也不会阻止合并，因此请保留你的 CI 提供商用于强制执行通过/失败状态的必需检查。
- **发现项：** 失败的测试和不稳定测试会作为全量变更发现项出现，并链接到 Tuist 上的测试用例。发现项不会影响 Entire 的 Agent 审查门禁。
- **摘要评论：** 与 GitHub 和 Origin 上的拉取请求评论类似，每个项目会为每个 Trail 保留一条 Tuist 运行报告评论。如果你删除了它，下一次报告会再次发布。

当新结果到达时，Tuist 会为 Trail 的当前头提交发布更新的报告，并解决被取代的发现项。重试不会创建重复的审查、发现项或评论，包括在 Entire 对发布的响应丢失的情况下。打开或重新打开 Trail 会获取已为其头提交上传的结果。如果当前头提交不存在任何结果，Tuist 不会发布新内容，因此旧提交的门禁无法满足新头提交的要求。已关闭和已合并的 Trails 不会更新。

Entire 卡片列出了项目到代码库的连接。在项目连接上选择 **Manage → Remove connection** 以停止其报告，而无需卸载插件。已发布的报告仍保留在 Entire 上，重新连接会开始新的报告。要更改插件的代码库访问权限或卸载它，请使用 Entire 中项目的 **Plugins** 设置。

## 自托管服务器 {#server-configuration}

如果你托管自己的 Tuist 服务器，请先为你的部署注册并配置 Entire 插件。按照 <.localized_link href="/guides/server/self-host/server#platform-entire">Entire 自托管说明</.localized_link> 操作，然后返回上述设置步骤以连接账户和项目。
