---
{
  "title": "插件",
  "titleTemplate": ":title · 智能体编码 · 功能 · 指南 · Tuist",
  "description": "安装适用于 Cursor 的 Tuist 插件，或选择厂商中立的 Agent Plugins 包。"
}
---

# 插件

Tuist 将智能体技能和托管 MCP 服务器打包为插件，以便你可以一次性安装两者。选择与你的编码智能体匹配的包。

## Claude Code

[Tuist Claude Code 市场](https://github.com/tuist/claude-plugin)提供了 Tuist 插件，可通过以下命令安装：

```bash
claude plugin marketplace add tuist/claude-plugin
claude plugin install tuist@tuist-plugins
```

该插件提供 Tuist 技能，并将 Claude Code 连接到托管的 MCP 服务器。

## Cursor

从 [Cursor Marketplace](https://cursor.com/marketplace) 安装 [适用于 Cursor 的 Tuist 插件](https://github.com/tuist/cursor-plugin)：

1. 在 Cursor 侧边栏中打开 **Customize**。
2. 搜索 **Tuist**。
3. 选择 **Install**，然后选择是为当前项目还是为你的用户账户安装。

你也可以在 Cursor 中输入 `/add-plugin` 来打开相同的安装流程。该插件提供 Tuist 技能，并将 Cursor 连接到托管的 MCP 服务器。

如果你的组织管理 Cursor 市场，请先从 **Settings → Plugins → Team Marketplaces → Import Marketplace** 导入 `https://github.com/tuist/cursor-plugin`。

## 其他编码智能体

[Tuist Agent Plugin](https://github.com/tuist/agent-plugin) 遵循开放、厂商中立的 [Agent Plugins](https://agent-plugins.org/) 标准。按照兼容客户端的说明，将其指向该仓库以安装或引用插件目录：

```bash
git clone https://github.com/tuist/agent-plugin.git
```

它会安装 Tuist 技能，并将 `https://tuist.dev/mcp` 注册为远程 MCP 服务器。对于尚不支持 Agent Plugins 的客户端，请单独安装 [技能](/guides/features/agentic-coding/skills) 或配置 [MCP 服务器](/guides/features/agentic-coding/mcp)。

## 身份验证

大多数技能使用 Tuist 命令行界面，因此在让智能体访问你的项目数据之前，请先对其进行一次身份验证：

```bash
tuist auth login
```

托管的 MCP 服务器会在需要时请求其自身的登录。有关针对特定客户端的设置和身份验证详情，请参阅 [MCP 指南](/guides/features/agentic-coding/mcp)。
