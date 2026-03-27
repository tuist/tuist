---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's MCP server to have a language-based interface for your app development environment."
}
---
# 模型上下文通訊協定 (MCP)

[Model Context
Protocol（MCP）](https://www.claudemcp.com)是由[Claude](https://claude.ai)提出的一種 LLM
與開發環境互動的標準。您可以將其視為 LLM 的 USB-C。就像貨櫃運送（shipping containers）讓貨物與運輸更具互通性，或是 TCP
等通訊協定將應用程式層與傳輸層解耦一樣，MCP 讓[Claude](https://claude.ai/)、[Claude
Code](https://docs.anthropic.com/en/docs/claude-code)等由 LLM
驅動的應用程式，以及[Zed](https://zed.dev)、[Cursor](https://www.cursor.com)或[VS
Code](https://code.visualstudio.com)等編輯器能夠與其他領域互通。

Tuist 透過其 CLI 提供本機伺服器，讓您可以與**應用程式開發環境** 進行互動。透過將您的用戶端應用程式連接到它，您就可以使用語言與您的專案互動。

在本頁中，您將學習如何設定及其功能。

::: info
<!-- -->
Tuist MCP 伺服器使用 Xcode 最新的專案作為您想要與之互動的專案的真實來源。
<!-- -->
:::

## 設定

Tuist 為常用的 MCP 相容用戶端提供自動設定指令。只需為您的用戶端執行適當的指令即可：

### [Claude](https://claude.ai)

針對 [Claude desktop](https://claude.ai/download)，執行：
```bash
tuist mcp setup claude
```

這將會設定`~/Library/Application Support/Claude/claude_desktop_config.json` 的檔案。

### [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

對於 Claude Code，請執行：
```bash
tuist mcp setup claude-code
```

這將設定與 Claude 桌面相同的檔案。

### [Cursor](https://www.cursor.com)

對於 Cursor IDE，您可以全局或本機設定：
```bash
# Global configuration
tuist mcp setup cursor --global

# Local configuration (in current project)
tuist mcp setup cursor

# Custom path configuration
tuist mcp setup cursor --path /path/to/project
```

### [Zed](https://zed.dev)

對於 Zed 編輯器，您也可以全局或本機設定：
```bash
# Global configuration
tuist mcp setup zed --global

# Local configuration (in current project)
tuist mcp setup zed

# Custom path configuration
tuist mcp setup zed --path /path/to/project
```

### [VS Code](https://code.visualstudio.com)

對於具有 MCP 延伸的 VS Code，可在全局或本機設定：
```bash
# Global configuration
tuist mcp setup vscode --global

# Local configuration (in current project)
tuist mcp setup vscode

# Custom path configuration
tuist mcp setup vscode --path /path/to/project
```

### 手動設定

如果您喜歡手動設定或使用不同的 MCP 用戶端，請將 Tuist MCP 伺服器新增至用戶端設定：

::: code-group

```json [Global Tuist installation (e.g. Homebrew)]
{
  "mcpServers": {
    "tuist": {
      "command": "tuist",
      "args": ["mcp", "start"]
    }
  }
}
```

```json [Mise installation]
{
  "mcpServers": {
    "tuist": {
      "command": "mise",
      "args": ["x", "tuist@latest", "--", "tuist", "mcp", "start"] // Or tuist@x.y.z to fix the version
    }
  }
}
```
<!-- -->
:::

## 能力

在以下章節中，您將學習 Tuist MCP 伺服器的功能。

### 資源

#### 近期專案與工作區

Tuist 會記錄您最近使用過的 Xcode
專案和工作區，讓您的應用程式可以存取其相關圖表，以獲得強大的洞察力。您可以查詢這些資料，以揭露專案結構和關係的詳細資訊，例如：

- 特定目標的直接相依性和反向相依性是什麼？
- 哪個目標有最多的原始碼檔案，以及包含多少？
- 圖表中都有哪些靜態產品 (例如靜態函式庫或框架)？
- 您是否可以列出所有目標，依字母順序排序，並列出其名稱和產品類型 (例如應用程式、架構、單元測試)？
- 哪些目標依賴特定的架構或外部依賴？
- 專案中所有目標的原始碼檔案總數是多少？
- 目標之間是否存在循環依賴關係？
- 哪些目標使用特定資源 (例如映像或 plist 檔案)？
- 圖表中最深的依賴鏈是什麼，涉及哪些目標？
- 您可以向我展示所有測試目標及其相關的應用程式或架構目標嗎？
- 根據最近的互動，哪些目標的建立時間最長？
- 兩個特定目標之間的依賴性有何差異？
- 專案中是否有未使用的原始碼檔案或資源？
- 哪些目標有共同的依賴關係？

有了 Tuist，您可以前所未有地深入研究您的 Xcode 專案，即使是最複雜的設定，也能更容易理解、最佳化和管理！
