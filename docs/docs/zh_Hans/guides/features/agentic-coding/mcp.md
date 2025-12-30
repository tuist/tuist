---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's MCP server to have a language-based interface for your app development environment."
}
---
# 模型上下文协议（MCP）

[模型上下文协议（MCP）](https://www.claudemcp.com)是由[克劳德](https://claude.ai)提出的一个标准，用于
LLM 与开发环境交互。您可以将其视为 LLM 的 USB-C。就像集装箱运输使货物和运输更具互操作性，或 TCP 等协议将应用层与传输层分离一样，MCP 使
[Claude](https://claude.ai/)、[Claude
Code](https://docs.anthropic.com/en/docs/claude-code) 等由 LLM 驱动的应用程序，以及
[Zed](https://zed.dev)、[Cursor](https://www.cursor.com) 或 [VS
Code](https://code.visualstudio.com) 等编辑器能够与其他领域互操作。

Tuist 通过其 CLI 提供了一个本地服务器，这样您就可以与**应用程序开发环境**
进行交互。通过将客户端应用程序连接到该服务器，您可以使用语言与您的项目进行交互。

在本页中，您将了解如何设置它及其功能。

信息
<!-- -->
Tuist MCP 服务器使用 Xcode 的最新项目作为您要与之交互的项目的真实来源。
<!-- -->
:::

## 设置

Tuist 为常用的 MCP 兼容客户端提供自动设置命令。只需为您的客户端运行相应的命令即可：

### [克劳德](https://claude.ai)

运行[克劳德桌面](https://claude.ai/download)：
```bash
tuist mcp setup claude
```

这将配置`~/Library/Application Support/Claude/claude_desktop_config.json`.

### [克劳德代码](https://docs.anthropic.com/en/docs/claude-code)

运行克劳德代码：
```bash
tuist mcp setup claude-code
```

这将配置与克劳德桌面相同的文件。

### [光标](https://www.cursor.com)

对于 Cursor IDE，您可以在全局或本地进行配置：
```bash
# Global configuration
tuist mcp setup cursor --global

# Local configuration (in current project)
tuist mcp setup cursor

# Custom path configuration
tuist mcp setup cursor --path /path/to/project
```

### [泽德](https://zed.dev)

对于 Zed 编辑器，您也可以在全局或本地进行配置：
```bash
# Global configuration
tuist mcp setup zed --global

# Local configuration (in current project)
tuist mcp setup zed

# Custom path configuration
tuist mcp setup zed --path /path/to/project
```

### [VS代码](https://code.visualstudio.com)

对于带有 MCP 扩展的 VS Code，可在全局或本地进行配置：
```bash
# Global configuration
tuist mcp setup vscode --global

# Local configuration (in current project)
tuist mcp setup vscode

# Custom path configuration
tuist mcp setup vscode --path /path/to/project
```

### 手动配置

如果您喜欢手动配置或使用不同的 MCP 客户端，请将 Tuist MCP 服务器添加到客户端配置中：

代码组

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

在以下章节中，您将了解 Tuist MCP 服务器的功能。

### 资源

#### 近期项目和工作区

Tuist 会记录您最近使用过的 Xcode
项目和工作区，让您的应用程序可以访问它们的依赖关系图，从而获得强大的洞察力。您可以查询这些数据，了解项目结构和关系的详细信息，例如

- 特定目标的直接和传递依赖关系是什么？
- 哪个目标的源文件最多？
- 图中有哪些静态产品（如静态库或框架）？
- 能否按字母顺序列出所有目标，以及它们的名称和产品类型（如应用程序、框架、单元测试）？
- 哪些目标依赖于特定框架或外部依赖性？
- 项目中所有目标的源文件总数是多少？
- 目标之间是否存在循环依赖关系？
- 哪些目标使用特定资源（如图像或 plist 文件）？
- 图中最深的依赖链是什么，涉及哪些目标？
- 能否向我展示所有测试目标及其相关应用程序或框架目标？
- 根据最近的互动，哪些目标的构建时间最长？
- 两个特定目标之间的依赖关系有何不同？
- 项目中是否有未使用的源文件或资源？
- 哪些目标有共同的依赖关系？

有了 Tuist，您可以前所未有地深入研究 Xcode 项目，从而更轻松地理解、优化和管理最复杂的设置！
