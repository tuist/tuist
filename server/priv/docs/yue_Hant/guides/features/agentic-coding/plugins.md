---
{
  "title": "外掛程式",
  "titleTemplate": ":title · Agentic coding · 功能 · 指南 · Tuist",
  "description": "安裝 Tuist 嘅 Cursor 外掛程式，或者供應商中立嘅 Agent Plugins 套件。"
}
---

# 外掛程式

Tuist 將代理技能同託管 MCP 伺服器打包成外掛程式，方便你一次過安裝。揀選配合你編碼代理嘅套件。

## Claude Code

[Tuist Claude Code marketplace](https://github.com/tuist/claude-plugin) 將 Tuist 外掛程式打包，可用以下指令安裝：

```bash
claude plugin marketplace add tuist/claude-plugin
claude plugin install tuist@tuist-plugins
```

此外掛程式提供 Tuist 技能，並將 Claude Code 連接到託管 MCP 伺服器。

## Cursor

從 [Cursor Marketplace](https://cursor.com/marketplace) 安裝 [Tuist plugin for Cursor](https://github.com/tuist/cursor-plugin)：

1. 喺 Cursor 側邊欄開啟 **Customize**。
2. 搜尋 **Tuist**。
3. 揀選 **Install**，然後決定係為目前項目定係你嘅用戶帳戶安裝。

你亦可以喺 Cursor 輸入 `/add-plugin` 來開啟相同嘅安裝流程。此外掛程式提供 Tuist 技能，並將 Cursor 連接到託管 MCP 伺服器。

如果你嘅組織管理 Cursor 市集，請先由 **Settings → Plugins → Team Marketplaces → Import Marketplace** 匯入 `https://github.com/tuist/cursor-plugin`。

## 其他編碼代理

[Tuist Agent Plugin](https://github.com/tuist/agent-plugin) 遵循開放、供應商中立嘅 [Agent Plugins](https://agent-plugins.org/) 標準。按照兼容客戶端嘅指示，將佢指向儲存庫以安裝或引用外掛程式目錄：

```bash
git clone https://github.com/tuist/agent-plugin.git
```

佢會安裝 Tuist 技能，並將 `https://tuist.dev/mcp` 註冊為遠端 MCP 伺服器。對於尚未支援 Agent Plugins 嘅客戶端，請分別安裝 [skills](/guides/features/agentic-coding/skills) 或設定 [MCP server](/guides/features/agentic-coding/mcp)。

## 驗證

大部分技能都使用 Tuist 命令列介面，因此喺要求代理存取你嘅項目數據之前，請先進行一次驗證：

```bash
tuist auth login
```

託管 MCP 伺服器會喺需要時要求獨立登入。請參閱 [MCP guide](/guides/features/agentic-coding/mcp) 了解針對特定客戶端嘅設定同驗證詳情。
