---
{
  "title": "Origin",
  "titleTemplate": ":title | Git 代码托管平台 | 集成 | 指南 | Tuist",
  "description": "将原生 Cursor Origin 仓库连接到 Tuist 拉取请求报告。"
}
---
# Origin 集成 {#origin}

Tuist 可以在原生 [Cursor Origin](https://cursor.com/docs/api/origin) 仓库的拉取请求中发布构建、测试、预览和捆绑报告。它会更新应用中现有的 Tuist 运行报告，而不是为每次上传都发布新评论。

安装应用不会执行构建或测试。你现有的工作流会继续将结果上传到 Tuist，而该集成会将这些结果带入你的拉取请求中。

## 设置 {#setup}

Tuist 账户的管理员应打开**设置 → 集成**，在 Origin 卡片中选择**安装 Origin 应用**，并在 Cursor 中批准访问权限。选择 Tuist 应访问的 Origin 账户或命名空间以及仓库，然后返回 Tuist。该连接属于 Tuist 账户，而非单个项目。

你也可以直接从 Origin 安装该应用。批准访问后，如有需要请登录 Tuist 并选择要连接的组织的。只有你管理的组织和你个人账户可用。如果只有一个账户可用，Tuist 会自动连接该账户而不显示选择器。如果你从 Tuist 开始操作，组织已预先选中，此步骤将被跳过。

选择**添加新项目连接**以打开仓库选择模态框。选择一个未连接的 Tuist 项目和一个从已连接的 Origin 账户中发现的仓库，然后选择**创建连接**。如果连接了多个 Origin 账户，请先选择账户。只有原生 Origin 仓库可供连接。Tuist 会在连接项目之前再次验证拉取请求访问权限，并采用仓库的默认分支。

使用**管理集成**在新标签页中打开 Cursor 的授权流程，调整仓库访问权限或连接另一个 Origin 账户。仓库加载失败会显示**重试**，这与成功的空仓库列表是分开的。

使用<.localized_link href="/guides/server/authentication#account-tokens">账户令牌</.localized_link>对结果上传进行身份验证。

## 报告和权限 {#reports-and-permissions}

在批准应用时，你授予了连接仓库和发布报告所需的权限：

| 权限 | 用途 |
| --- | --- |
| 拉取请求：读取 | 查找所报告提交对应的开放拉取请求。 |
| 拉取请求评审：读取和写入 | 读取、发布和更新 Tuist 运行报告评论。 |
| 仓库元数据：读取 | 发现仓库及其默认分支。由 Origin 自动包含。 |

Tuist 不需要访问你的源代码或合并拉取请求的权限。

要将结果与拉取请求关联，上传内容必须包括仓库的 Origin 克隆 URL、Git 引用和完整提交 SHA。只有当这些信息指向当前头提交处的单个开放拉取请求时，Tuist 才会发布报告。已被取代的提交的结果不会覆盖当前报告。

Origin 卡片列出了项目到仓库的连接。在项目连接上选择**管理 → 移除连接**以停止其报告，而无需卸载应用。在 Cursor 中卸载应用以撤销其访问权限；Tuist 在处理安装通知时会移除该安装及其项目连接。

## 自托管服务器 {#server-configuration}

如果你自行托管 Tuist 服务器，请先为你的部署注册并配置一个 Origin 应用。按照<.localized_link href="/guides/server/self-host/server#platform-origin">Origin 自托管说明</.localized_link>操作，然后返回上述设置步骤以连接账户和项目。
