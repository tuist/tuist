---
{
  "title": "模型上下文协议 (MCP)",
  "titleTemplate": ":title · 智能体编码 · 功能 · 指南 · Tuist",
  "description": "通过 Tuist 的 MCP 端点，让 AI 智能体访问测试洞察等功能。"
}
---
# 模型上下文协议

[模型上下文协议 (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro) 是一项开放标准，允许人工智能代理与外部服务和数据源进行交互。它使 [Claude](https://claude.ai/)、[Claude Code](https://docs.anthropic.com/en/docs/claude-code)、[Codex](https://developers.openai.com/codex/) 等应用，以及 [Zed](https://zed.dev)、[Cursor](https://www.cursor.com) 或 [Visual Studio Code](https://code.visualstudio.com) 等编辑器能够与 Tuist 互操作。

Tuist 在 `https://tuist.dev/mcp` 托管服务器端模型上下文协议端点。通过将客户端连接到该端点，代理可以访问你的 Tuist 项目数据，包括测试洞察、不稳定测试分析等。大多数工具为只读，且仅限于已认证的 Tuist 项目数据。账户设置工具可以列出账户、创建组织、创建项目，并在已认证用户拥有所需权限时将现有用户添加到组织中。每个工具都会声明注解，说明其是否为只读、是否可能导致难以撤销的更改，以及是否可以更改公共互联网状态。账户设置工具需要用户认证。它们不适用于项目令牌或普通账户令牌。当用户在浏览器中授权客户端或认领 `auth.md` 注册时，Tuist 仅在该模型上下文协议端点上将该凭据与用户关联，以便设置工具完成请求的工作流。

Tuist 实现了 [2026-07-28 协议](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)。请求是无状态的：客户端在每次请求中发送其协议元数据，并可以直接调用工具而无需初始化。`server/discover` 返回服务器的身份、功能、支持的版本和说明。不存在会话标识符或独立的事件流。使用 2025-06-18 或 2025-03-26 初始化流的客户端仍然受支持；它们也在没有服务器会话的情况下运行。

## 模型上下文协议与技能对比

模型上下文协议工具和 <.localized_link href="/guides/features/agentic-coding/skills">技能</.localized_link> 的功能可能存在重叠。鉴于目前两者之间存在重叠，请为每个工作流选择一种方法并一致使用，而不是在同一流中混合使用两者。

对于支持插件安装的客户端，请使用 <.localized_link href="/guides/features/agentic-coding/plugins">Tuist 插件</.localized_link> 一并安装两者。

## 配置

在客户端中将 `https://tuist.dev/mcp` 添加为远程模型上下文协议服务器。服务器的初始化说明和公开服务器卡片描述了带有动态客户端注册的标准 OAuth 2.0 以及标准浏览器授权流，无需代理获取或遵循外部认证文档。这些服务器范围的说明保持了工作流指导的通用性：工具认证不会对本地命令行工具或构建系统集成进行认证，代理应通过相关的 Tuist 工具验证请求的更改。特定于构建系统的设置和认证检查记录在集成指南和提示中。Tuist 仍然分别在 `https://tuist.dev/auth.md` 上提供 [Open Authorization](https://oauth.net/2/) 发现元数据和当前的 [auth.md 协议](https://workos.com/auth-md)。

如果你的某个组织强制实施单点登录，则在浏览器中授权客户端需要通过该组织登录的会话，并且在需要时 Tuist 会先将你重定向到提供商。请参阅 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">单点登录</.localized_link>。

该端点接受无状态的 `2026-07-28` 模型上下文协议请求生命周期（包括 `server/discover`），同时也支持较旧的基于会话的生命周期。现有客户端可以继续使用其当前的连接方法。

支持模型上下文协议事件的客户端可以订阅项目事件。有关可用的事件和交付要求，请参阅 [事件](#events)。

已经支持远程浏览器认证的客户端可以继续在浏览器中进行认证。支持 `auth.md` 的客户端和代理可以匿名注册、提供受信任的提供商身份断言，或启动服务认证的邮箱认领。注册会返回一个由 Tuist 签名的身份断言，代理在标准令牌端点将其交换为一小时有效的访问令牌。Tuist 发布其公钥签名密钥，并支持标准令牌撤销和提供商安全事件交付。

未经认证的代理应读取模型上下文协议端点返回的 `WWW-Authenticate` 标头，获取受保护资源元数据，获取授权服务器元数据，并遵循其 `agent_auth.skill` URL。Tuist 还在未授权响应正文中返回相同的本地 `auth_md` URL，以便由语言模型驱动的客户端可以在不依赖原生客户端集成的情况下发现该流程。部署本地文档是端点名称、请求体、认领轮询和断言交换的真实来源。

在代理开始邮箱认领之前，必须要求用户确认其 Tuist 账户的邮箱地址。不得从提供商个人资料、Git 配置、环境变量或会话元数据中推断该地址。

该端点使用 `mcp` 范围组。匿名的认领前凭据可以发现功能并阅读公开的集成指导，但不被视为已登录用户。在浏览器授权或认领后，凭据具有用户范围，并且每个工具都应用与仪表板相同的授权检查。详情请参阅 <.localized_link href="/guides/server/authentication#scope-groups">范围组文档</.localized_link>。

工具解析为已认证用户已有权读取的项目。Xcode 和 Gradle 构建工具接受构建 UUID 或仪表板 URL。UUID 必须唯一标识一个项目；如果它出现在多个项目中，工具将返回未找到，而不是选择另一个项目的报告。项目范围的仪表板和 API 读取仍然可用。报告的行为者标识符是未经验证的标签，不是凭据或额外的访问权限。

构建列表和详情工具公开可选的 `tuist_version` 元数据：用于 Xcode 和 Cargo 的报告 Tuist CLI、用于 Gradle 的 Tuist Gradle 插件，以及用于 Mix 的 `tuist_ex` 库。Xcode 还从其关联的项目生成事件中公开 `tuist_generation_version`，该版本可能与上传的 CLI 不同。缺失的观测值为 null，不会从服务器或其他报告中推断。Bazel 使用其现有的 `bazel_version`；Once 运行详情公开 `once_version`。这些字段描述报告的版本，而非已验证的身份或线路契约版本。REST 构建端点公开相同的元数据。现有的集成和不稳定测试技能不依赖版本字段，无需更改工作流程。

Tuist 操作员通过 Tuist 的内部运营工具调查客户账户，该工具会记录每次调用；直接连接到此端点不会获得超出用户自身成员资格的访问权限。

<details>
<summary>Claude Code</summary>

运行：

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

当无头 Claude Code 客户端未向模型暴露失败的原生服务器连接时，要求代理在搜索托管文档或编辑项目之前检查配置端点的未认证 [超文本传输协议](https://developer.mozilla.org/en-US/docs/Web/HTTP) 响应。即使浏览器认证不可用，该响应也会将模型指向部署本地的 `auth.md` 文档。

</details>


<details>
<summary>Codex</summary>

运行：

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

在开始新的 `codex exec` 运行之前完成浏览器登录。Codex 在初始化期间读取 Tuist 服务器指令，因此 Gradle 优化请求会自动接收认证和验证工作流程。

</details>


<details>
<summary>Claude Desktop</summary>

打开 **设置 → 连接器 → 添加自定义连接器**，然后设置：

- **名称：** `tuist`
- **URL：** `https://tuist.dev/mcp`

在提示时在浏览器中完成 [开放授权](https://oauth.net/2/)。

</details>


<details>
<summary>Pi</summary>

Pi 不包含模型上下文协议客户端。在审查其源代码和安全影响后，你可以安装第三方 [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) 扩展：

```bash
pi install npm:pi-mcp-adapter
```

添加项目级 `.mcp.json` 文件：

```json
{
  "mcpServers": {
    "tuist": {
      "url": "https://tuist.dev/mcp",
      "auth": false
    }
  }
}
```

将 `auth` 设置为 `false` 可防止适配器的浏览器认证处理程序隐藏 Tuist 的未授权响应。无头代理随后可以读取返回的 `auth_md` URL，并遵循 Tuist 的注册、身份断言交换和认领轮询流程。将交换后的访问令牌配置为持有者令牌，或让代理直接进行认证的模型上下文协议调用。

如果你更喜欢浏览器认证，请将 `auth` 设置为 `"oauth"`。对于该流程，在认证完成期间保持一个进程处于活动状态，使用 Pi 的 [远程过程调用模式](https://pi.dev/docs/latest/rpc)：

```bash
pi --mode rpc
```

不要将待处理的浏览器认证拆分到单独的 `pi --print` 调用中，因为拥有回调状态的进程已退出。

</details>


<details>
<summary>OpenCode</summary>

将 Tuist 模型上下文协议服务器添加到 `opencode.json`：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "tuist": {
      "type": "remote",
      "url": "https://tuist.dev/mcp"
    }
  }
}
```

然后认证服务器：

```bash
opencode mcp auth tuist
```

</details>


<details>
<summary>Cursor</summary>

打开 **Cursor 设置 → 工具与集成 → 模型上下文协议工具** 并添加：

- **名称：** `tuist`
- **URL：** `https://tuist.dev/mcp`

</details>


<details>
<summary>Visual Studio Code</summary>

使用 **命令面板 → MCP: 添加服务器**，然后配置 [超文本传输协议](https://developer.mozilla.org/en-US/docs/Web/HTTP) 服务器：

- **名称：** `tuist`
- **URL：** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

打开 **代理面板 → 设置 → 添加自定义服务器**，然后设置：

- **名称：** `tuist`
- **URL：** `https://tuist.dev/mcp`

</details>

如果你的代理支持 `auth.md`，它可以匿名启动而无需打开浏览器。当提供商身份已链接时，受信任的提供商身份也可以在不打开浏览器的情况下完成。对于服务认证的邮箱、匿名认领或首次提供商链接，代理会向你显示一个 Tuist 验证链接和六位代码。打开链接，登录，并在 Tuist 页面上输入代理的代码。切勿将代码发送回代理。Tuist 的授权服务器元数据直接指向部署自己的 `/auth.md`，其中包含确切的请求和轮询结构。

## WebMCP

在支持 [WebMCP](https://webmachinelearning.github.io/webmcp) 的浏览器中，Tuist 的页面通过 `document.modelContext` 注册工具，因此内置于浏览器的代理可以在无需任何额外配置的情况下调用它们。调用在 Tuist 服务器上运行。

- **网站和文档页面** 注册文档和源码工具（`search_tuist`、`search_tuist_code`、`list_tuist_files` 和 `read_tuist_file`）。它们不需要你登录。
- **账户的仪表板页面** 在你登录时为该账户注册 Tuist 的只读工具。每个页面仅注册其显示内容所需的工具，针对项目的构建系统：Gradle 项目的构建页面获取 Gradle 构建工具，其测试页面获取测试和覆盖率工具，运行器页面获取运行器工具，沙盒页面获取沙盒工具。个人账户 AI 设置页面的订阅部分获取 `list_ai_subscriptions`，它仅回答你自己的账户。每个页面还获取文档工具 `list_projects` 和 `get_project`。工具以登录用户的身份运行，因此它们只能访问你在仪表板中可以读取的数据，且仅限你正在查看的账户。当你移动到另一个页面或账户时，工具会被替换为该页面的工具。

创建、更改或删除数据的工具无法通过 WebMCP 使用，因为浏览器代理会在你未添加它们的情况下接收工具，并读取构建和测试产生的内容。将 MCP 客户端连接到 `/mcp` 端点以使用这些工具。

如果组织强制使用单点登录，请使用其提供商登录仪表板以使用其工具。

## 构建系统集成使用两种凭据

用于模型上下文协议工具的凭据不会验证 Gradle 插件或 Bazel 的远程服务。在代理编辑或验证 Gradle 或 Bazel 集成之前，它应运行：

```bash
tuist auth whoami --url https://tuist.dev
```

如果该命令未通过身份验证，代理必须停止并请求用户运行：

```bash
tuist auth login --url https://tuist.dev
```

对于本地或自托管部署，请替换两个命令以及 `tuist.toml` 中的 URL。确保所有位置的主机名拼写完全一致。例如，`localhost` 和 `127.0.0.1` 使用单独存储的凭据。


## 功能

### 工具

以下工具可通过 Tuist 模型上下文协议服务器使用：

每个工具都会发布人类可读的描述以及明确的输入和输出模式。成功的调用会返回符合所声明输出模式的结构化内容，并为尚未使用结构化内容的客户端提供序列化为文本的相同结果。

接受单个记录标识符（如 `build_run_id`、`test_run_id`、`test_case_id`、`bundle_id`、`run_id`、`generation_id` 或 `cache_run_id`）的工具也接受该记录的 Tuist 仪表板 URL。直接从浏览器粘贴 URL，而不是从中提取标识符。

#### 文档和社区搜索

此只读工具通过与文档网站相同的搜索引擎搜索 Tuist 的文档、[应用程序编程接口](https://en.wikipedia.org/wiki/API)参考、GitHub 发布、社区论坛和 GitHub 问题。发布结果包括产品、版本、发布日期和预发布状态。默认情况下搜索稳定版本，可以通过 `include_prereleases` 包含预发布版本。该工具仅在 `https://tuist.dev/mcp` 上的 Tuist 托管服务器上可用。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `search_tuist` | 搜索公开的 Tuist 文档、应用程序编程接口参考、GitHub 发布、社区讨论和 GitHub 问题。可选择限制为一个 `source`（`docs`、`api_reference`、`releases`、`forum`、`issues`）。 | `query` |

#### 反馈

当 Tuist 工具或提示未按预期工作时，代理可以告知 Tuist 团队，例如结果令人困惑、出现错误、数据缺失或缺少功能。代理会被要求建议一份报告，并且仅在你同意后才发送。每份报告都会开启与 Tuist 支持的对话，他们可能会通过电子邮件回复你。报告包括代理的预期、实际发生的情况、可选建议、你的 Tuist 用户 ID、句柄和电子邮件，以及你所属的组织。代理还可以指明问题发生的账户和项目，以便团队知道跟进哪个组织；仅接受你所属的账户。只有以 Tuist 用户身份登录的代理才能发送报告，每个用户每小时最多可以提交 10 份报告。该工具仅在 `https://tuist.dev/mcp` 上的 Tuist 托管服务器上可用。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `report_feedback` | 报告 Tuist 工具或提示的问题。可选择命名 `tool_name`、问题发生的 `account_handle` 和 `project_handle`，并添加 `suggestion`。 | `category`, `expected`, `actual` |

#### 基于源码的回答

这些只读工具允许代理使用与托管服务器一起部署的确切公共 Tuist 源码修订版作为依赖于当前行为的答案的真实来源。它们仅在 `https://tuist.dev/mcp` 上可用。

兼容的客户端在初始化期间会收到关于工具源码修订版、链接和结果限制的事实性描述，以及内联 OAuth 身份验证信息。这些描述不规定回答风格或验证工作流程。用户可以直接提问，而无需先调用 `ask_tuist` 提示；该提示仍可用于显式的基于源码的工作流程。

每个操作都有固定的并发、持续时间、遍历、读取字节数和响应大小限制。搜索和列表结果包括 `truncated` 和 `truncation_reason` 字段。当结果被截断时，请缩小路径、文件模式或搜索词的范围，而不是将结果视为详尽无遗。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `search_tuist_code` | 通过搜索源文件来回答有关当前行为、默认值、配置、功能开关、错误处理或未记录细节的问题。结果包括周围的行、固定修订版的源码链接和扫描统计信息。 | `pattern` |
| `list_tuist_files` | 当相关路径未知时，发现源子系统或附近的测试。列表具有有限的深度和结果数量。 | 无 |
| `read_tuist_file` | 在找到相关路径后，检查实现文件、调用站点或测试中的特定行范围。截断的响应提供 `next_start_line` 以继续。 | `path` |

#### 项目

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_accounts` | 列出经过身份验证的用户可用的个人和组织账户句柄，包括每个账户是否可以创建项目。 | 无 |
| `get_organization` | 获取组织的成员目录。待处理的邀请需要与仪表板相同的管理员权限；邀请接受令牌永远不会返回。 | `account_handle` |
| `create_organization` | 为经过身份验证的用户创建 Tuist 组织。 | `handle` |
| `create_project` | 在經過身份驗證的用戶可訪問的賬戶下創建 Tuist 項目。 | `account_handle`, `project_handle` |
| `add_organization_member` | 將現有的 Tuist 用戶添加到組織或更新現有成員的角色。接受 `user`（默認）、`admin` 或 `viewer`，其中查看者可以閱讀儀表板和運行記錄，但無法更改任何內容。 | `organization_handle`, `email` |
| `invite_organization_member` | 邀請電子郵件地址加入組織，無論該地址是否屬於現有的 Tuist 用戶。Tuist 會發送一個有效期為 14 天的接受鏈接；當服務器無法發送電子郵件時，`email_sent` 為 `false`，必須從儀表板複製該鏈接。接受 `user`（默認）、`admin` 或 `viewer`。需要組織管理員權限。 | `organization_handle`, `email` |
| `cancel_organization_invitation` | 取消待處理的組織邀請，使其鏈接無法再被接受。需要組織管理員權限。 | `organization_handle`, `email` |
| `list_projects` | 列出經過身份驗證的用戶可訪問的所有項目。 | 無 |
| `get_project` | 獲取項目的配置和連接的存儲庫 URL。 | `account_handle`, `project_handle` |
| `connect_project_repository` | 將項目鏈接到賬戶的 GitHub App 安裝可訪問的 GitHub 存儲庫。項目採用存儲庫的默認分支。需要項目管理員權限。 | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | 移除項目與其 GitHub 存儲庫的鏈接。需要項目管理員權限。 | `account_handle`, `project_handle` |

#### 賬戶令牌

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_account_tokens` | 列出賬戶令牌元數據，不暴露令牌值。 | `account_handle` |
| `get_account_token` | 獲取賬戶令牌元數據，不暴露其值。 | `account_handle`, `token_id` |
| `list_project_tokens` | 列出項目令牌元數據，不暴露令牌值。 | `account_handle`, `project_handle` |

#### AI 訂閱

這些工具管理經過身份驗證的用戶自己的 Claude 和 ChatGPT 訂閱，用於線程等 AI 功能。它們需要用戶身份驗證和對 AI 功能的訪問權限，僅返回連接元數據，從不返回憑據。斷開連接會刪除保存的憑據，但不會撤銷提供商處的授權。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_ai_subscriptions` | 列出每個訂閱是否已連接以及服務器是否可以連接它。 | 無 |
| `connect_claude_subscription` | 保存 `claude setup-token` 打印的訂閱令牌。該令牌是通過客戶端和模型傳遞的秘密信息，因此請僅明確提供；將其粘貼到儀表板的 AI 設置中可使其不出現在對話中。 | `token` |
| `start_chatgpt_subscription_login` | 啟動 OpenAI 設備登錄並返回驗證 URL 和用戶在那裡輸入的代碼，以及 `login_id`。15 分鐘後過期。 | 無 |
| `poll_chatgpt_subscription_login` | 檢查待處理的登錄：在用戶批准代碼之前為 `pending`，然後變為 `connected`。 | `login_id` |
| `cancel_chatgpt_subscription_login` | 取消待處理的登錄。已連接的訂閱保持連接狀態。 | `login_id` |
| `disconnect_ai_subscription` | 刪除訂閱的保存憑據和任何待處理的登錄。 | `provider` |

#### 通知規則

這些工具管理經過身份驗證的用戶自己的通知規則：當事件（例如新的預覽）發生在規則的項目中（或者在未列出任何項目時，發生在您可收到通知的任何項目中）並滿足其條件時，執行其操作，例如向您的 Tuist 應用設備發送推送通知。沒有規則就不會收到通知。它們需要用戶身份驗證，僅對您自己的規則起作用，並且僅接受您所屬賬戶的項目。它們不提供給儀表板頁面，因為規則涵蓋您所有的賬戶。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_notification_events` | 列出規則可以訂閱的事件類型，每個類型都帶有用於其條件的 JSON Schema。 | 無 |
| `list_notification_condition_options` | 建議項目中事件的條件值，例如其最近預覽的軌道和分支。 | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | 列出您的規則。 | 無 |
| `create_notification_rule` | 從事件、可選項目和條件以及至少一個操作創建規則。 | `event`, `actions` |
| `update_notification_rule` | 更改規則的啟用狀態、項目、條件或操作。 | `rule_id` |
| `delete_notification_rule` | 刪除規則。 | `rule_id` |

#### 持續集成運行器

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_runner_jobs` | 列出賬戶的持續集成運行器作業。 | `account_handle` |
| `get_runner_job` | 獲取持續集成運行器作業。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | 列出為持續集成運行器作業記錄的步驟。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | 列出為持續集成運行器作業記錄的機器指標。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | 列出持續集成運行器作業最多 500 條捕獲的日誌行。 | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | 列出賬戶的持續集成工作流匯總。 | `account_handle` |
| `list_runner_profiles` | 列出賬戶的持續集成運行器配置文件，並包含每個配置文件的 `runs-on` 標籤。 | `account_handle` |
| `get_runner_catalog` | 列出運行器配置文件可以使用的機器規格和 Xcode 版本。 | `account_handle` |
| `create_runner_profile` | 使用平台、機器規格以及在 macOS 上的 Xcode 版本創建運行器配置文件。可選擇設置哪些分支保存其緩存卷。需要賬戶管理員權限或 `account:runners:write` 範圍。 | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | 更改運行器配置文件的機器規格、Xcode 版本或哪些分支保存其自定義緩存卷更改。省略的字段保持其值不變。需要賬戶管理員權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |
| `delete_runner_profile` | 經用戶確認後刪除運行器配置文件。默認配置文件無法刪除。需要賬戶管理員權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |

運行器卷工具公開與卷儀表板相同的數據。讀取工具需要運行器訪問權限；清除需要賬戶管理員權限或 `account:runners:write` 範圍，以及用戶確認。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_runner_volumes` | 按名稱和存儲庫篩選，對卷進行排序和分頁。 | `account_handle` |
| `get_runner_volume` | 存儲庫、平台、容量、已用空間和最後使用時間。 | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | 分頁的作業和工作流引用、緩存狀態、命中結果和掛載時間。 | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | 由作業掛載的卷。 | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | 存儲序列、作業運行次數、命中率和趨勢。可選 `volume_id`、`start` 和 `end`（ISO 8601）；默認為七天，最多 90 天。 | `account_handle` |
| `delete_runner_volume` | 刪除卷及其保存的內容。正在運行的作業保留其私有副本但無法保存；後續具有相同密鑰的作業將從空狀態開始。 | `account_handle`, `volume_id` |

列表接受 `page` 和 `page_size`（最多 100）。卷庫存還接受 `name` 和 `repository`（精確匹配，以 AND 組合）、`sort_by`（`volume`、`repository`、`used_space`、`capacity`、`last_used`）和 `sort_order`（`asc`、`desc`）。未知的測量和命中結果保持為 `null`。緩存狀態描述卷更改是否已保存，而非作業成功與否。

#### 沙盒

沙盒工具公開與沙盒儀表板相同的數據和操作。沙盒運行任意命令，因此每個工具（包括只讀工具）都需要賬戶管理員權限，且賬戶需啟用沙盒功能。儀表板的沙盒頁面註冊只讀工具。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_sandboxes` | 對沙盒進行分頁，顯示其狀態、規格和時間戳。可選 `search`（沙盒中的文本、Amp Orb 或 Anthropic 會話 ID）、`status`、`vcpus`、`sort_by`（`created`、`last_active`、`identifier`）和 `sort_order`。 | `account_handle` |
| `get_sandbox` | 沙盒的狀態、規格、節點、歸檔和時間戳。 | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU 小時數、創建的沙盒數量、會話、設置和啟動持續時間，以及相對於賬戶限制的峰值 vCPU、內存和磁盤使用情況，並包含趨勢。可選 `start` 和 `end`（ISO 8601）；默認為 30 天，最多 90 天。 | `account_handle` |
| `create_sandbox` | 啟動一個空白沙盒並在運行後返回它。可選 `platform`（`linux` 或 `darwin`）、`template`、帶 `memory_mb` 的 `vcpus`（Linux：2x4096、4x8192 或 8x16384，默認 2x4096；macOS：8x8192、8x16384 或 8x24576，默認 8x8192）和 `workspace_gb`。 | `account_handle` |
| `pause_sandbox` | 將正在運行的沙盒快照保存到其節點的磁盤。 | `account_handle`, `sandbox_id` |
| `resume_sandbox` | 恢復已暫停或歸檔的沙盒。 | `account_handle`, `sandbox_id` |
| `archive_sandbox` | 將已暫停沙盒的磁盤排隊遷移至對象存儲。 | `account_handle`, `sandbox_id` |
| `delete_sandbox` | 在用戶確認後刪除沙盒及其磁盤。 | `account_handle`, `sandbox_id` |

#### Webhook

Webhook 工具使用與儀表板相同的管理員專屬權限。發送嘗試包含為端點記錄的請求和響應數據，但絕不包含端點簽名密鑰。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_webhook_endpoints` | 列出賬戶的 Webhook 端點。 | `account_handle` |
| `get_webhook_endpoint` | 獲取一個 Webhook 端點。 | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | 列出端點的發送嘗試。 | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | 獲取一次發送嘗試。 | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode 構建

用於 Xcode、Gradle、Bazel、Mix 和 Cargo 的構建詳情工具公開現有的 `custom_metadata: {tags, values}` 結構，包括基礎設施觀測數據（如果已報告）。值保持為字符串，並保留不熟悉的鍵。例如，`tuist.cpu.available_processors` 描述運行時可用的邏輯處理器，而 `tuist.gradle.max_workers` 是 Gradle 工作器限制，`tuist.jvm.max_heap_bytes` 是 JVM 堆限制，而非主機內存。這些是不可信的客戶端觀測數據，而非經過驗證的運行器身份。缺失的觀測數據保持缺失；導入的日誌和較舊的客戶端可能沒有基礎設施元數據。統一的元數據格式有待客戶端/協議協調更新。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_xcode_builds` | 列出項目的 Xcode 構建運行。 | `account_handle`, `project_handle` |
| `get_xcode_build` | 獲取特定 Xcode 構建運行的詳細信息，包括保存原始 `.xcactivitylog` 的歸檔文件的臨時下載 URL。 | `build_run_id` |
| `list_xcode_build_targets` | 列出特定 Xcode 構建運行的構建目標。 | `build_run_id` |
| `list_xcode_build_files` | 列出特定 Xcode 構建運行的編譯文件。 | `build_run_id` |
| `list_xcode_build_steps` | 列出記錄的構建步驟，包含耗時和結果，但不含日誌文本。 | `build_run_id` |
| `get_xcode_build_step` | 獲取一個記錄的構建步驟，包括其日誌和截斷標誌。 | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | 列出特定構建運行的構建問題（警告和錯誤）。 | `build_run_id` |
| `list_xcode_build_cache_tasks` | 列出特定 Xcode 構建運行的可緩存任務（緩存命中/未命中）。 | `build_run_id` |
| `list_xcode_build_cas_outputs` | 列出特定 Xcode 構建運行的 [內容尋址存儲](https://en.wikipedia.org/wiki/Content-addressable_storage) 輸出。 | `build_run_id` |

`list_xcode_build_steps` 默認返回每頁 20 個步驟（通過 `page_size` 最多可達 100 個），並提供 `page` 和 `pagination_metadata` 用於導航。使用 `search` 匹配標題、項目或目標，或過濾精確的 `project`、`target`、`category`（例如 `swiftCompilation`）和 `status`（`success` 或 `failure`）。按 `duration_ms` 排序以優先顯示最慢的步驟（默認），或按 `start_ms` 排序以顯示時間順序。步驟 ID 用於打破平局，並作為十進制字符串返回以保留其完整的 64 位精度。ID 僅限於單個構建，不應跨構建匹配。

可選的 `start_ms` 和 `end_ms` 選擇與從構建開始計算的毫秒時間範圍重疊的步驟；結束時間為獨佔。兩個工具都接受構建 UUID 或儀表板 URL 作為 `build_run_id`。將返回的步驟 `id` 原樣作為 `step_id` 傳遞以檢索其日誌。每個步驟的日誌最多保留 64 KiB，`log_truncated` 指示省略的輸出。

處理 Xcode 構建時默認會收集步驟。記錄的步驟數據保留 90 天。列表響應包括 `availability`：當存在記錄的步驟時為 `available`，即使過濾器未匹配任何內容；當構建仍在處理且尚無步驟時為 `processing`；或者當步驟未記錄或已過期時為 `unavailable`。

相同的操作可通過 HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` 和 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` 上使用，具有相同的過濾器和分頁功能。兩者都需要對構建所屬項目具有讀取權限。

#### Gradle 構建

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | 返回完整的身份驗證、項目設置、Gradle 插件、緩存策略和兩次構建驗證工作流。代理在編輯現有的 Android 或 Gradle 項目之前應調用此接口。 | 無 |
| `list_gradle_builds` | 列出項目的 Gradle 構建運行，包括自定義元數據。通過可選的 `tag` 參數按自定義標籤過濾。 | `account_handle`, `project_handle` |
| `get_gradle_build` | 獲取構建元數據以及任務/緩存計數。 | `build_run_id` |
| `list_gradle_build_tasks` | 列出任務結果、複合構建標識、可緩存性和增量狀態。 | `build_run_id` |
| `list_gradle_build_steps` | 列出定時任務、配置和轉換，支持搜索、元數據和重疊時間過濾。 | `build_run_id` |
| `get_gradle_build_step` | 通過不透明 ID 檢查記錄的步驟元數據；不提供每步驟日誌。 | `build_run_id`, `step_id` |

Gradle 和 Bazel 步驟列表默認返回 20 條結果（最多 100 條），支持 `search`、精確的 `project`、`target`、`category` 和 `status`、重疊的 `start_ms` / `end_ms` 過濾器（結束時間為獨佔），以及按 `duration_ms` 或 `start_ms` 排序。請原樣傳遞返回的 ID；它們僅限於各自的構建。列表提供 `time_origin` 和 `coverage`。較舊的 Gradle 報告使用 `first_recorded_timestamp`，因為未上傳構建開始時間。Bazel 配置文件通過 `trace_profile` 覆蓋範圍公開所有記錄的時間間隔，並以 `profile_start` 作為時間起點。較舊的構建會回退到保留的 BEP 摘要。源記錄在 90 天後過期。Bazel 詳情在發布時包含經過清理的操作日誌；Gradle 詳情的 `log` 為 null。`compare_builds` 提示利用此覆蓋範圍來區分完整的 Bazel 追蹤與保留的摘要，並指導代理在檢查更廣泛的調用輸出之前，先查看步驟詳情以獲取操作結果和日誌。

單步工具 `get_gradle_build_step` 和 `get_bazel_build_step` 通過 ID 檢索步驟，不接受時間過濾器；請使用相應的列表工具按時間範圍過濾步驟。

如果在列出步驟和獲取步驟之間收到了完整的配置文件，則從保留摘要中返回的 Bazel 步驟 ID 仍然可讀。如果索引配置文件的步驟數據已過期，則報告為不可用。Gradle 步驟列表包括持續時間為零的緩存和跳過操作。

#### Bazel 調用

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | 返回身份驗證、項目設置、Bazel 配置和驗證工作流。 | 無 |
| `list_bazel_invocations` | 列出已完成的 [Bazel Build Event Protocol](https://bazel.build/remote/bep) 調用，包括構建指標、有界的執行時間線、關鍵路徑診斷以及項目的相關遠程緩存總計。 | `account_handle`, `project_handle` |
| `get_bazel_invocation` | 獲取一個已完成的 Bazel 調用，包括構建指標、有界的執行時間線、關鍵路徑診斷以及相關的遠程緩存總計。 | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | 列出記錄的 Bazel 配置文件間隔，帶有過濾器和明確的覆蓋範圍。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | 檢查記錄的 Bazel 步驟及其發布的操作結果和經過清理的日誌。 | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | 按執行順序列出為 Bazel 調用捕獲的經過清理的測試日誌。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | 獲取為 Bazel 調用捕獲的一個經過清理的測試日誌。 | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | 列出原始的 Bazel 遠程緩存觀察記錄，包括其操作、端點和觀察時間，可選擇縮小到特定調用、結果或操作。 | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | 獲取一個原始的 Bazel 遠程緩存觀察記錄。 | `account_handle`, `project_handle`, `cache_event_id` |

#### Cargo 構建

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_cargo_builds` | 列出項目的 Cargo 構建，最新的排在前面。按 `git_branch`、`status`、`is_ci` 或 `command` 過濾。Cargo 測試執行結果可通過測試工具獲取，而非此構建列表。 | `account_handle`, `project_handle` |
| `get_cargo_build` | 獲取構建元數據、聚合緩存計數器，以及最多 500 個帶有診斷信息的記錄編譯作業。`compilations_truncated` 指示省略的作業；診斷信息僅涵蓋返回的作業。 | `account_handle`, `project_handle`, `build_id` |

在 `get_cargo_build` 上設置 `include_cache_inspection: true` 以檢索經過驗證的任務決策和 CAS 操作，限制為 4 MB。默認情況下，當記錄缺失或無效時，`cache_inspection` 為 null。請尊重其部分捕獲的 `truncated` 標誌；傳輸不會確定每個任務命中的本地/遠程來源。HTTP 詳情端點接受相同的查詢參數。

#### Mix 構建

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_mix_builds` | 列出項目的 Mix (Elixir) 編譯構建，最新的排在前面，包括自定義元數據。按 `git_branch`、`status`、`is_ci` 或 `mix_env` 過濾。 | `account_handle`, `project_handle` |
| `get_mix_build` | 獲取構建元數據、診斷計數和依賴緩存摘要。 | `account_handle`, `project_handle`, `build_id` |

#### 構建追蹤

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `get_build_trace` | 獲取 Xcode、Gradle、Bazel 或 Mix 構建時間線的下載鏈接，作為可在 [Perfetto](https://ui.perfetto.dev) 中打開的追蹤文件。 | `account_handle`, `project_handle`, `build_id` |

`build_id` 是構建運行 ID（Bazel 的調用 ID）或構建的儀表板 URL。返回的 `trace_url` 提供 [Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSON 文件。任何持有該鏈接的人都可以在 `expires_at`（調用後一小時）之前下載該構建的追蹤文件，無需其他憑證。代理可以使用 `curl` 下載它，交給你並在 Perfetto 中打開，或使用 Perfetto 的 `trace_processor` 進行查詢。追蹤文件包含按並行性打包到通道中的記錄步驟、跨越整個構建的軌道，以及在構建記錄機器指標時的 CPU 和內存計數器。它包含與上述步驟工具相同的數據，但不包含日誌。儀表板從每個構建的時間線標籤頁提供相同的文件。

#### Once 運行

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_once_runs` | 列出項目的 Once 運行，最新的排在前面。按 `kind`（`build`、`test` 或 `generic`）、`status`、`is_ci` 或 `git_branch` 過濾。尚未完成的運行狀態為 `in_progress`。 | `account_handle`, `project_handle` |
| `get_once_run` | 獲取一次運行及其操作總數、緩存摘要，對於測試運行還包括測試總數。 | `account_handle`, `project_handle`, `run_id` |

Cargo 構建、Mix 構建和 Once 運行的 ID 在項目內是唯一的。通過 HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`、`.../mix/builds` 和 `.../once/runs` 提供相同的讀取接口，每個接口都有一個用於單個 ID 的詳情端點。

#### 任務、操作、模塊和文件

這些項目範圍的工具檢查跨運行的持久構建身份。從 `list_build_entities` 開始，然後將返回的穩定 `id` 與相同的 `kind` 一起傳遞給 `get_build_entity` 或 `list_build_entity_history`，並附上 `account_handle` 和 `project_handle`。不需要構建或調用標識符。

| 工具 | 描述 | 必需參數 |
| --- | --- | --- |
| `list_build_entities` | 列出在項目構建中看到的一類任務、模塊、操作或文件。 | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | 獲取一個構建實體及其原生身份和所選時期的分析數據。 | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | 列出一個構建實體的記錄執行、編譯或緩存事件，最新的排在前面。 | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | 工具鏈 | 歷史列表 |
| --- | --- | --- |
| `bazel_actions` | Bazel 操作 | BEP 報告的操作執行 |
| `gradle_tasks` | Gradle 任務 | 任務執行 |
| `xcode_modules` | Xcode 模塊 | 編譯和模塊緩存事件 |
| `once_actions` | Once 操作 | 執行 |
| `mix_files` | Mix 編譯文件 | 編譯 |
| `mix_modules` | Mix 編譯模塊 | 編譯 |
| `cargo_crates` | Cargo crate | 記錄的 rustc 調用 |

這些工具正在逐步推出，僅返回已啟用它們的項目的數據；對於其他項目，它們返回錯誤而不是空結果。某種類型僅對使用其構建工具鏈的項目可用。工具接受有界的 `start_at`/`end_at` 過濾器、`environment`（`any`、`ci` 或 `local`）以及精確的 `branch`。`list_build_entities` 接受 `q`；`list_build_entity_history` 支持不透明的 `after`/`before` 游標。未知的計時或緩存觀察保持不可用，而不是變成零或未命中。歷史記錄引用記錄的父級和原生執行，以便使用現有的運行工具進行下鑽。

`get_build_entity` 指標包括 `duration_samples`，即具有記錄計時的觀察數量：真實的零持續時間計入，缺失的計時不計入。此計數可能低於觀察計數；不可用的持續時間統計信息保持為 null。

Xcode 模塊持續時間來自構建日誌中測量的目標編譯。模塊緩存解析和沒有編譯工作的目標不提供持續時間樣本。編譯觀察引用 Xcode 構建；緩存事件引用生成或緩存命令。

Bazel 操作由目標標籤、助記符和配置的主要輸出來標識，在不依賴於輸入相關的緩存摘要的情況下保持單獨的操作和配置區別開來。歷史記錄 BEP 報告的執行，而不是緩存查找或追蹤配置文件階段。完整的執行覆蓋需要 `--build_event_publish_all_actions`；工件交付是盡力而為，因此缺失的觀察並不證明沒有工作運行。較舊的沒有穩定身份或執行開始的 Kura 負載仍然被接受但未編入索引。缺失的結束時間測量保持不可用，真實的零持續時間計入。

Mix 模塊持續時間測量包含文件的編譯，而不是獨立測量的模塊工作。當客戶端報告目標映射時，Once 操作使用聲明的目標/能力/索引槽；僅診斷標籤不是穩定的身份。現有的客戶端和運行級別工具保持不變的支持。

Cargo crate 按精確記錄的 crate 根目錄、名稱和類型分組。檢出路徑更改可能會分割歷史記錄，並且構建配置文件、功能和目標三元組不被區分。歷史測量 rustc 調用，而不是每文件工作或緩存命中；缺失的作业不確立刪除或完整的工作區清單。

分析讀取具有有界的內存和執行時間。如果查詢超過這些限制，工具將返回錯誤而不是發明一個空結果。

新觀察在部署後編入索引；此功能不回填現有的運行遙測數據。在 <.localized_link href="/guides/server/data-retention">數據保留策略</.localized_link> 下，身份元數據比單個觀察更長久。

#### 測試

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_test_runs` | 列出項目的測試運行。`query` 字段是 `git_branch`、`scheme` 和 `status`：`field:"value"` 精確匹配，`field~"value"` 匹配不區分大小寫的子字符串，前導 `-` 否定任一運算符。例如，`-git_branch~"gh-readonly-queue"` 排除合併隊列分支。空格分隔的查詢過濾器和顯式參數與 AND 語義結合。 | `account_handle`, `project_handle` |
| `get_test_run` | 获取测试运行的详细指标，包括其结果包（`.xcresult`）和会话归档的临时下载 URL。 | `test_run_id` |
| `list_test_module_runs` | 列出特定测试运行的测试模块运行。 | `test_run_id` |
| `list_test_suite_runs` | 列出特定测试运行的测试套件运行，可按模块筛选。 | `test_run_id` |
| `list_test_cases` | 列出项目的测试用例（支持如 `flaky` 等过滤器）。 | `account_handle`, `project_handle` |
| `get_test_case` | 获取测试用例的详细指标，包括可靠性率、不稳定率和运行次数。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | 列出测试用例运行，可按测试用例或测试运行筛选。 | `account_handle`, `project_handle` |
| `get_test_case_run` | 获取特定测试用例运行的失败详情和重复情况。 | `test_case_run_id` |
| `list_test_case_run_attachments` | 列出测试用例运行的附件。每个附件都包含一个临时下载 URL。 | `test_case_run_id` |
| `list_test_case_events` | 列出测试用例的状态变更，例如将其静音或跳过。 | `test_case_id` |
| `update_test_case` | 更新测试用例的状态或不稳定分类。变更可以向配置的 webhook 端点（包括外部服务）分派事件。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | 列出测试运行的选择性测试目标结果。 | `test_run_id` |
| `get_coverage` | 获取项目在某个提交或分支最新完整提交时的代码覆盖率及其目标。如果不指定 `git_commit_sha` 或 `branch`，则读取默认分支。 | `account_handle`, `project_handle` |
| `list_coverage_files` | 列出在某个提交或分支最新完整提交时由代码覆盖率测量的文件及其行覆盖率。支持 `search`、排序和分页。 | `account_handle`, `project_handle` |
| `get_coverage_file` | 获取文件在某个提交或分支最新完整提交时的代码覆盖率及其函数。设置 `include_lines` 以获取每行的执行计数。 | `account_handle`, `project_handle`, `path` |

代码覆盖率工具适用于已启用代码覆盖率的账户。

#### Bundle

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_bundles` | 列出项目的 bundle（应用二进制文件）。可按 `git_branch` 和 `tags` 筛选（所有标签必须精确匹配）。 | `account_handle`, `project_handle` |
| `get_bundle` | 获取特定 bundle 的详细信息，包括自定义标签。 | `bundle_id` |
| `get_bundle_artifact_tree` | 获取 bundle 的完整构件树，作为按路径排序的平面列表。 | `bundle_id` |

`list_bundles` 接受 `tags: ["paid", "production"]` 以区分构建变体或环境。标签是区分大小写的标签，包含字母、数字、连字符或下划线，最多 10 个标签，每个标签最多 50 个字符。列表和详细信息结果包括 `custom_metadata.tags`。分页计数和分支过滤器应用于带标签的结果；省略 `tags` 将保留未过滤的行为。无效的标签过滤器将返回错误，而不是扩大查询范围。

#### 生成

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_generations` | 列出项目的生成运行。 | `account_handle`, `project_handle` |
| `get_generation` | 获取特定生成运行的详细信息。 | `generation_id` |

#### 缓存运行

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_cache_runs` | 列出项目的缓存运行。 | `account_handle`, `project_handle` |
| `get_cache_run` | 获取特定缓存运行的详细信息。 | `cache_run_id` |
| `list_xcode_module_cache_targets` | 列出生成或缓存运行的模块缓存目标，显示每个目标的缓存命中/未命中状态和诊断组件哈希，包括额外的哈希输入。 | `run_id` |

#### 预览

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_previews` | 列出项目的可共享应用预览。 | `account_handle`, `project_handle` |
| `get_preview` | 获取预览及其构建的临时下载 URL。 | `preview_id` |
| `get_latest_preview` | 查找正在运行的应用二进制文件的最新预览。 | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### 自动化

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_automation_alerts` | 列出项目的自动化警报。 | `account_handle`, `project_handle` |
| `get_automation_alert` | 获取自动化警报。 | `alert_id` |
| `list_automation_alert_revisions` | 列出自动化警报的修订历史。操作凭据已脱敏。 | `alert_id` |
| `list_project_notification_alerts` | 列出项目通知警报规则。需要与仪表板设置页面相同的管理员权限。Webhook 地址已脱敏。 | `account_handle`, `project_handle` |

### 事件

使用无状态 `2026-07-28` Model Context Protocol 生命周期的客户端可以调用 `events/list` 来发现事件及其负载架构：

| 事件 | 发送时机 | 订阅过滤器 |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | 测试用例从稳定变为不稳定。 | `account_handle`, `project_handle` |
| `build.failed` | 本地或持续集成的 Xcode、Gradle 或 Bazel 构建以失败结束。 | `account_handle`, `project_handle` |
| `test_run.failed` | 本地或持续集成测试运行以失败结束，包括合并的分片运行或已放弃的运行。 | `account_handle`, `project_handle` |
| `ci_job.failed` | Tuist 运行器作业以失败完成。 | `account_handle` |

要订阅，客户端需调用 `events/subscribe`，传入事件名称、上述 `arguments` 中列出的句柄，以及包含 `https://` 回调 URL 和 `whsec_` 签名密钥的 `webhook` 交付配置。项目事件需要账户成员身份以及对相应测试或构建数据的读取权限；运行器作业事件需要账户成员身份和运行器读取权限。已声明的 [`auth.md`](https://workos.com/auth-md) 访问令牌、已声明的账户令牌和浏览器授权授予可以创建订阅；当相关凭据不再有效时，交付将停止。每个用户最多可保留 25 个活跃订阅。Tuist 在保存订阅之前会向回调发送验证质询。回调必须返回包含相同 `challenge` 值的对象。订阅默认持续七天，可以通过再次订阅来刷新，并在用户的访问权限或凭据被移除时停止交付。可选的 `ttlMs` 限制在一小时到 30 天之间。Tuist 会重试超时的回调，并在至少三次连续超时（跨越五分钟）后取消订阅；请在恢复回调后重新订阅。

当事件发生时，Tuist 会将其资源标识符和仪表板 URL 发送到回调。构建和测试运行失败还包括 `is_ci` 和 `git_branch`，因此客户端可以忽略本地失败或按分支过滤。构建事件包括 `build_system`；运行器作业事件包括 `workflow_job_id` 和 `workflow_run_id`。请求包含订阅标识符和 [Standard Webhooks](https://www.standardwebhooks.com/) 签名标头，以便客户端验证其来源。Tuist 会重试失败的交付，因此客户端应使用稳定的 `eventId` 来丢弃重复项。负载省略了测试名称、日志和失败消息；客户端可以通过上述工具获取这些详细信息，并决定是否通知团队或开始调试。客户端可以使用 `events/unsubscribe` 停止交付。

### 提示词

| 提示词 | 描述 |
|--------|-------------|
| `fix_flaky_test` | 指导你通过分析失败模式、识别根本原因并应用针对性修正来修复不稳定测试。 |
| `compare_builds` | 指导你通过比较构建来识别性能回归、缓存更改和构建问题。对 Xcode、Gradle、Bazel 和 Cargo 项目使用原生工具。Cargo 比较保留部分编译器覆盖率，并区分估计的编译器工作与节省的时间。 |
| `compare_test_runs` | 指导你通过比较两次测试运行来识别回归、新失败和不稳定测试。 |
| `compare_bundles` | 指导你通过比较两个 bundle 来识别构件树中的大小变化。 |
| `compare_test_case` | 指导你通过比较测试用例在两个分支或时间段内的行为。 |
| `compare_generations` | 指导你通过比较两次生成运行来识别性能回归和模块缓存更改。 |
| `compare_cache_runs` | 指导你通过比较两次缓存运行来识别缓存有效性更改和目标级回归。 |
| `integrate_gradle_project` | 指导你将 Tuist 集成到现有 Gradle 项目中。包括独立的工具和 Gradle 身份验证、账户发现、项目创建、远程缓存策略、构建洞察和回读验证。 |
| `integrate_bazel_project` | 指导你创建或选择 Bazel 项目、对命令行进行身份验证、配置远程缓存和构建洞察，并通过 Tuist 构建数据验证集成。 |
| `integrate_xcode_project` | 指导你将 Tuist 集成到现有 Xcode 项目中。支持 Xcode 缓存、构建洞察、测试洞察和测试分片。 |
| `ask_tuist` | 使用公开材料作为上下文，并以聚焦的实现和测试证据作为当前行为的真实来源来回答 Tuist 问题。它需要 `question` 并引用修订固定的证据。 |

项目数据提示词接受 `account_handle` 和 `project_handle` 以将调查范围限定在特定项目。比较提示词还接受 `base` 和 `head` 参数以指定要比较的两个项目（通过 ID、仪表板 URL 或分支名称）。`ask_tuist` 接受 `question` 而不是项目参数。`integrate_gradle_project` 还接受 `features`，这是一个要应用的 Gradle 集成的逗号分隔列表：`remote_cache`、`build_insights`、`test_insights`、`flaky_tests` 和 `test_sharding`。`integrate_bazel_project` 接受可选的 `server_url` 用于自托管或本地安装。`integrate_xcode_project` 接受包含 `xcode_cache`、`build_insights`、`test_insights` 和 `test_sharding` 的 `features`。

#### Gradle 集成提示词功能

`integrate_gradle_project` 提示词和 `get_gradle_integration_guide` 工具记录了完整的设置工作流。该工具还被服务器的初始化说明引用，这使得不枚举提示词的代理也能发现它。

| 功能 | 代理配置的内容 |
|---------|---------------------------|
| `remote_cache` | 启用 Gradle 的构建缓存，配置 Tuist 远程缓存上传策略，并建议仅从具有本地只读使用权的持续集成运行器进行上传。 |
| `build_insights` | 应用 Tuist Gradle 插件，并在需要时配置构建分析上传行为。 |
| `test_insights` | 应用 Tuist Gradle 插件，以便自动上传 Gradle `Test` 任务结果。 |
| `flaky_tests` | 指导设置不稳定测试检测、可选的 Gradle Test Retry 插件使用以及测试隔离配置。 |
| `test_sharding` | 添加用于 `tuistPrepareTestShards`、分片矩阵生成和基于 `TUIST_SHARD_INDEX` 的测试执行的持续集成工作流。 |

当省略 `features` 时，提示词会要求代理明确用户想要哪些集成，或在编辑 Gradle 项目之前从请求中推断出最小的有用集合。

#### Xcode 集成提示词功能

`integrate_xcode_project` 提示词记录了 Tuist 支持的每种 Xcode 集成：

| 功能 | 代理配置的内容 |
|---------|---------------------------|
| `xcode_cache` | 配置 `tuist setup cache`、生成项目的缓存设置、手动 Xcode 缓存构建设置，以及仅限于持续集成运行器的上传策略。 |
| `build_insights` | 通过 `tuist setup insights` 配置 `tuist inspect build`、`tuist xcodebuild`、`-resultBundlePath` 和可选的机器指标。 |
| `test_insights` | 配置 `tuist inspect test`、方案测试后操作以及用于持续集成测试运行的结果包生成。 |
| `test_sharding` | 添加带有 `TUIST_SHARD_INDEX` 的 Xcode 或生成项目的分片规划和分片执行工作流。 |

当省略 `features` 时，提示词会要求代理明确用户想要哪些集成，或在编辑 Xcode 项目之前从请求中推断出最小的有用集合。
