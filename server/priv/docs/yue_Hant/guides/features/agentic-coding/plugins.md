---
{
  "title": "外掛程式",
  "titleTemplate": ":title · Agentic coding · 功能 · 指南 · Tuist",
  "description": "安裝適用於 Cursor 的 Tuist 外掛程式，或供應商中立的 Agent Plugins 套件。"
}
---

# 外掛程式

Tuist 將代理技能與託管 MCP 伺服器打包為外掛程式，方便你一次安裝兩者。請選擇符合你編碼代理的套件。

## Claude Code

[Tuist Claude Code 市集](https://github.com/tuist/claude-plugin)已將 Tuist 外掛程式打包，可使用以下指令安裝：

```bash
claude plugin marketplace add tuist/claude-plugin
claude plugin install tuist@tuist-plugins
```

此外掛程式提供 Tuist 技能，並將 Claude Code 連接至託管的 MCP 伺服器。

## Cursor

從 [Cursor Marketplace](https://cursor.com/marketplace) 安裝 [Tuist plugin for Cursor](https://github.com/tuist/cursor-plugin)：

1. 在 Cursor 側邊欄中開啟 **Customize**。
2. 搜尋 **Tuist**。
3. 選取 **Install**，然後選擇要為當前專案或你的使用者帳戶安裝。

你也可以在 Cursor 中輸入 `/add-plugin` 以開啟相同的安裝流程。此外掛程式提供 Tuist 技能，並將 Cursor 連接至託管的 MCP 伺服器。

如果你的組織管理 Cursor 市集，請先從 **Settings → Plugins → Team Marketplaces → Import Marketplace** 匯入 `https://github.com/tuist/cursor-plugin`。

## 其他編碼代理

[Tuist Agent Plugin](https://github.com/tuist/agent-plugin) 遵循開放且供應商中立的 [Agent Plugins](https://agent-plugins.org/) 標準。請依照該客戶端安裝或引用外掛程式目錄的指示，將相容的客戶端指向該儲存庫：

```bash
git clone https://github.com/tuist/agent-plugin.git
```

它會安裝 Tuist 技能，並將 `https://tuist.dev/mcp` 註冊為遠端 MCP 伺服器。對於尚未支援 Agent Plugins 的客戶端，請分別安裝 [skills](/guides/features/agentic-coding/skills) 或設定 [MCP server](/guides/features/agentic-coding/mcp)。

## 驗證

大多數技能都使用 Tuist 命令列介面，因此在要求代理存取你的專案資料之前，請先進行一次驗證：

```bash
tuist auth login
```

託管的 MCP 伺服器會在需要時要求自行登入。請參閱 [MCP guide](/guides/features/agentic-coding/mcp) 以取得針對特定客戶端的設定與驗證詳細資訊。
