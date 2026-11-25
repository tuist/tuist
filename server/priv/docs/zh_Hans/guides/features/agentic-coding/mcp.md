---
{
  "title": "模型上下文协议 (MCP)",
  "titleTemplate": ":title · 智能体编码 · 功能 · 指南 · Tuist",
  "description": "通过 Tuist 的 MCP 端点，让 AI 智能体访问测试洞察等资源。"
}
---
# 模型上下文协议

[模型上下文协议 (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro) 是一项开放标准，允许人工智能代理与外部服务和数据源进行交互。它使 [Claude](https://claude.ai/)、[Claude Code](https://docs.anthropic.com/en/docs/claude-code)、[Codex](https://developers.openai.com/codex/) 等应用程序，以及 [Zed](https://zed.dev)、[Cursor](https://www.cursor.com) 或 [Visual Studio Code](https://code.visualstudio.com) 等编辑器能够与 Tuist 互操作。

Tuist 在 `https://tuist.dev/mcp` 托管服务器端模型上下文协议端点。通过将客户端连接到该端点，代理可以访问你的 Tuist 项目数据，包括测试洞察、不稳定测试分析等。大多数工具读取的是已认证用户在仪表板中已经可见的 Tuist 数据。每个工具都会声明注解，说明其是否为只读、是否可能导致难以撤销的更改 (`destructiveHint`)，以及是否能够访问 Tuist 之外的资源 (`openWorldHint`)。以下工具会更改状态，且各自受限于用户对账户或项目的权限：

- **组织和成员**：`create_organization`、`add_organization_member`（添加现有用户或更改成员角色）、`invite_organization_member`（向任意地址发送邀请邮件）以及 `cancel_organization_invitation`。
- **项目**：`create_project`、`start_project_logo_upload` 和 `complete_project_logo_upload`（替换徽标）、`connect_project_repository` 和 `disconnect_project_repository`（GitHub 仓库链接）。
- **测试**：`update_test_case`（静音、跳过、重新启用或将测试用例标记为不稳定；更改可能会触达账户的 webhook 端点）。
- **通知规则**：`create_notification_rule`、`update_notification_rule` 和 `delete_notification_rule`。
- **持续集成运行器**：`create_runner_profile`、`update_runner_profile`（缩小保存缓存卷的作业范围会丢弃待处理的保存）、`delete_runner_profile` 和 `delete_runner_volume`（删除卷中保存的内容）。
- **沙盒**：`create_sandbox`、`pause_sandbox`、`resume_sandbox`、`extend_sandbox`、`archive_sandbox`、`delete_sandbox`（删除其磁盘），以及在沙盒设备（当前为 macOS 沙盒中的 iOS 模拟器）上执行 `boot_sandbox_device`、`launch_sandbox_app` 和 `open_sandbox_url`。
- **反馈**：`report_feedback`（向 Tuist 团队发送关于工具或提示的报告；仅在 tuist.dev 上可用）。
- **组织 AI**：`save_organization_ai_model`、`remove_organization_ai_model`、`set_organization_ai_default_model`、`save_organization_ai_task_route`、`remove_organization_ai_task_route` 和 `remove_organization_ai_provider`（删除提供者的密钥和模型，并取消关联 Anthropic 上链接的 Claude 组织）。
- **代理集成**：`connect_amp_workspace`（授予工作区的 orbs CI 访问账户的权限）、`disconnect_amp_workspace` 和 `connect_claude_environment`（允许 Claude Managed Agents 环境在 Tuist 沙盒中运行会话）。

`add_organization_member`、`cancel_organization_invitation`、`complete_project_logo_upload`、`disconnect_project_repository`、`update_test_case`、`update_notification_rule`、`delete_notification_rule`、`update_runner_profile`、`delete_runner_profile`、`delete_runner_volume`、`delete_sandbox`、`disconnect_amp_workspace`、`remove_organization_ai_provider`、`remove_organization_ai_model` 和 `remove_organization_ai_task_route` 声明 `destructiveHint: true`，因为它们会替换或删除现有状态。`invite_organization_member`、`update_test_case`、`connect_claude_environment`、`remove_organization_ai_provider` 和 `report_feedback` 声明 `openWorldHint: true`，因为它们会发送电子邮件、通知外部 webhook 端点、调用 Anthropic 或向 Tuist 团队发送报告。

个人 Claude 和 ChatGPT 订阅仅在仪表板的 AI 设置中连接，因此订阅令牌和登录信息绝不会经过模型上下文协议客户端。账户设置工具需要用户身份验证。它们不适用于项目令牌或普通账户令牌。当用户在浏览器中授权客户端或认领 `auth.md` 注册时，Tuist 仅在该模型上下文协议端点上将该凭据与用户关联，以便设置工具完成请求的工作流。由于任何人都可以注册客户端，在浏览器中授权时会显示一个同意页面，其中列出了客户端名称及其访问权限发送到的主机，Tuist 仅在你在此处批准后才会颁发凭据。未请求任何范围的客户端将获得 `mcp` 范围组。客户端必须使用带有 `S256` 的 PKCE，其重定向 URI 必须使用 HTTPS、环回地址上的 HTTP 或应用程序自身的方案。

Tuist 实现了 [2026-07-28 协议](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)。请求是无状态的：客户端在每次请求中发送其协议元数据，并且可以直接调用工具而无需初始化。`server/discover` 返回服务器的身份、功能、支持的版本和说明。不存在会话标识符或独立的事件流。使用 2025-06-18 或 2025-03-26 初始化流的客户端仍然受支持；它们也在没有服务器会话的情况下运行。

## 模型上下文协议与技能对比

模型上下文协议工具和 <.localized_link href="/guides/features/agentic-coding/skills">技能</.localized_link> 的功能可能存在重叠。鉴于目前两者之间的重叠，每个工作流应选择一种方法并一致使用，而不是在同一流中混合使用两者。

对于支持插件安装的客户端，请使用 <.localized_link href="/guides/features/agentic-coding/plugins">Tuist 插件</.localized_link> 一并安装两者。

## 配置

在客户端中将 `https://tuist.dev/mcp` 添加为远程模型上下文协议服务器。服务器的初始化说明和公共服务器卡片以内联方式描述了具有动态客户端注册和标准浏览器授权流的 OAuth 2.0，无需代理获取或遵循外部身份验证文档。这些服务器范围的说明保持了工作流指导的通用性：工具身份验证不会对本地命令行工具或构建系统集成进行身份验证，代理应通过相关的 Tuist 工具验证请求的更改。特定于构建系统的设置和身份验证检查记录在集成指南和提示中。Tuist 仍然分别在 `https://tuist.dev/auth.md` 宣传 [Open Authorization](https://oauth.net/2/) 发现元数据和当前的 [auth.md 协议](https://workos.com/auth-md)。

如果你的某个组织强制实施单点登录，则在浏览器中授权客户端需要通过该组织登录的会话，必要时 Tuist 会先将你重定向到提供者。请参阅 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">单点登录</.localized_link>。

该端点接受无状态的 `2026-07-28` 模型上下文协议请求生命周期（包括 `server/discover`），同时也支持较旧的基于会话的生命周期。现有客户端可以继续使用其当前的连接方法。

支持模型上下文协议事件的客户端可以订阅项目事件。有关可用的事件和交付要求，请参阅 [事件](#events)。

已支持远程浏览器身份验证的客户端可以继续在浏览器中进行身份验证。支持 `auth.md` 的客户端和代理可以匿名注册、提供受信任的提供者身份断言，或启动服务身份验证的电子邮件声明。注册会返回一个由 Tuist 签名的身份断言，代理可在标准令牌端点将其交换为一小时有效的访问令牌。Tuist 发布其公钥签名密钥，并支持标准的令牌撤销和提供者安全事件交付。

未经身份验证的代理应读取模型上下文协议端点返回的 `WWW-Authenticate` 标头，获取受保护资源元数据，获取授权服务器元数据，并遵循其 `agent_auth.skill` URL。Tuist 还在未授权响应正文中返回相同的本地 `auth_md` URL，以便由语言模型驱动的客户端无需依赖原生客户端集成即可发现该流程。部署本地的文档是端点名称、请求正文、声明轮询和断言交换的真实来源。

在代理启动电子邮件声明之前，必须要求用户确认其 Tuist 账户的电子邮件地址。不得从提供者个人资料、Git 配置、环境变量或会话元数据中推断该地址。

该端点使用 `mcp` 范围组。匿名的预声明凭据可以发现功能并阅读公共集成指南，但不被视为已登录用户。在浏览器授权或声明后，凭据将限定于用户范围，并且每个工具都会应用与仪表板相同的授权检查。有关详细信息，请参阅 <.localized_link href="/guides/server/authentication#scope-groups">范围组文档</.localized_link>。

工具解析为经过身份验证的用户已经可以读取的项目。Xcode 和 Gradle 构建工具接受构建 UUID 或仪表板 URL。UUID 必须唯一标识一个项目；如果它出现在多个项目中，工具将返回未找到，而不是选择另一个项目的报告。项目范围的仪表板和 API 读取仍然可用。报告的参与者标识符是未经验证的标签，不是凭据或额外的访问权限。

构建列表和详情工具公开可选的 `tuist_version` 元数据：用于 Xcode 和 Cargo 的报告 Tuist CLI、用于 Gradle 的 Tuist Gradle 插件，以及用于 Mix 的 `tuist_ex` 库。Xcode 还从其关联的项目生成事件中公开 `tuist_generation_version`，这可能与上传的 CLI 不同。缺失的观察值为 null，不会从服务器或其他报告中推断。Bazel 使用其现有的 `bazel_version`；Struo 运行详情公开 `once_version`。这些字段描述报告的版本，而非经过验证的身份或线路契约版本。REST 构建端点公开相同的元数据。现有的集成和不稳定测试技能不依赖于版本字段，无需更改工作流。

Tuist 操作员通过 Tuist 的内部运营工具调查客户账户，该工具记录每次调用；直接连接到此端点获得的访问权限不超过用户自身的成员资格。

### Pulse

Pulse 公开用于账户运营指标、日志、追踪和错误的只读工具，所有工具均通过 `account_handle` 寻址。前三个工具镜像 Pulse 页面及其 REST API；另外五个工具允许代理直接探索遥测数据，没有对应的 REST 接口：

| 工具 | 用途 | `/api/accounts/:account_handle/pulse` 下的 REST 等效接口 |
| --- | --- | --- |
| `query_pulse` | Pulse 页面表格 | `GET /:signal` |
| `get_pulse_analytics` | Pulse 页面小部件 | `GET /:signal/analytics` |
| `get_pulse_error_issue` | 一个错误问题及其事件 | `GET /errors/issues/:fingerprint` |
| `query_pulse_metrics` | 即时或范围 PromQL | 无 |
| `list_pulse_labels` | 标签名称，或一个标签的值 | 无 |
| `search_pulse_logs` | 过滤后的日志条目 | 无 |
| `search_pulse_traces` | 过滤后的跨度 | 无 |
| `get_pulse_trace` | 一个追踪的每个跨度 | 无 |

即使账户或项目是公开的，Pulse 也仅限于服务器配置组织的当前成员。它需要用户身份验证或与用户关联的 `mcp` 凭据以及账户读取授权。项目令牌、普通账户令牌、匿名注册以及没有组织成员资格的操作员访问权限都不授予 Pulse 访问权限。凭据无法选择其他后端或遥测租户，且只有服务器配置的账户拥有 Pulse 遥测数据，因此没有任何工具可以读取其他账户的数据。浏览器代理仅在 Pulse 页面上接收这些工具，且在该页面的账户范围内。

REST 需要用户凭据。OAuth 和 `auth.md` 用户关联仅在 `/mcp` 端点上可用；没有当前用户的账户凭据将被拒绝，无论关联账户的成员资格或可见性如何。

`query_pulse` 接受 `signal`（`metrics`、`logs`、`traces` 或 `errors`）、可选的 `query` 和 `range`（`15m`、`1h`、`6h` 或 `24h`，默认 `1h`）。指标接受 PromQL 表达式。日志、追踪和错误接受字面量、不区分大小写的文本，与日志正文、跨度名称和错误问题标题进行匹配；`*`（默认值）选择所有内容。追踪行是单个跨度。错误行是问题：按服务和指纹分组的事件，包括其事件计数、受影响的账户、窗口内的首次和最后一次出现，以及最新事件的标题、责任人、级别和平台。表格接受 `search`、`page`（默认 `1`）、`page_size`（`1`–`100`，默认 `20`）、`sort_by` 和 `sort_order`（`asc` 或 `desc`）。排序列取决于信号，并在工具架构中列出。过滤器包括 `service`，以及用于日志和错误的 `level`。过滤器运算符使用相应的 `_op` 参数（`eq`、`contains` 或 `not_contains`），默认为精确相等。

排序列为：指标的 `name`/`value`；日志的 `timestamp`/`service`/`level`/`message`/`trace_id`；追踪的 `timestamp`/`service`/`name`/`duration_ms`/`trace_id`；以及错误的 `last_seen`/`first_seen`/`events`/`accounts`/`title`/`service`/`level`。仪表板有意公开子集；API 和工具接受每个信号的完整列表。

表格响应包含 `rows`、`series`、`warnings` 和 `meta`。分页元数据包括 `page`、`page_size`、`total_count`、`total_pages`、`has_next_page`、`has_previous_page` 和 `end_at`。传递返回的 ISO8601 `end_at` 给后续页面以保留查询窗口。结果限制错误需要缩小查询或时间范围，而不是将响应视为空表。

日志和追踪在本地排序前最多检查最新的 100 个匹配项，错误则检查最近看到的 100 个问题。过滤、排序、分页和总数仅描述这些返回的匹配项，而非整个时间窗口。缩小查询文本或时间范围以检查其他匹配项；更改本地搜索或排序不会扩展上游搜索。聚合小部件保持独立，执行完整窗口的查询，而不是这些有界表格结果的聚合。

指标表格在 `end_at` 处对表达式求值一次，返回当前值和每个即时向量系列的一个点。范围向量表达式可以返回有界的历史点。独立的分析小部件提供固定的历史图表；表格不会为每个匹配的系列实现时间网格来仅显示其最新值。

遥测字符串是不可信数据，不是指令。

`get_pulse_analytics` 除了账户句柄外，仅接受 `signal` 和 `range`。其固定小部件独立于表格表达式、过滤器、排序和分页。

`get_pulse_error_issue` 从错误行中获取问题的 `fingerprint` 和 `service`，以及可选的 `range`、`end_at`、`page` 和 `page_size`。它返回问题摘要、60 个等分的发生次数桶、带有异常链、堆栈帧、面包屑、标签、上下文、额外数据、请求方法和不含查询字符串的 URL 的最新事件，以及一页事件（最新的在前），具有与表格相同的分页 `meta`。错误行还携带每个问题的 60 桶 `occurrence_series`。事件在存储前会清除个人数据，因此过滤后的值显示为 `[Filtered]` 或 `[REDACTED]`。窗口内没有事件的问题将报告为未找到。REST 和模型上下文协议使用相同的 Pulse 上下文和响应契约。REST 响应禁用缓存。

#### 探索遥测数据

探索工具读取 `15m`、`1h`、`6h` 或 `24h` 的时间窗口（默认 `1h`，`get_pulse_trace` 为 `24h`），结束于可选的 ISO8601 `end_at`，默认为现在。每个响应都返回 `start_at` 和 `end_at`；再次传递相同的 `end_at` 以保持窗口。这些工具均不接受 SQL。

- `query_pulse_metrics` 在 `end_at`（`type: instant`，默认）或窗口内的每 `step` 秒（`type: range`）评估 `query`（PromQL 表达式）。步长默认为且不能小于窗口除以 360，因此一个系列最多有 361 个点。结果最多有 5,000 个系列。点是 `[unix_seconds, value]`，`NaN` 和无限值是字符串。即时查询拒绝 `range` 和 `step`。
- `list_pulse_labels` 接受 `signal`。如果没有 `label`，它列出标签名称；如果有 `label`，它列出该标签的值。对于指标，`__name__` 列出指标名称，任何其他标签的值都需要 `match`（系列选择器，如 `up`）。日志和追踪标签值接受 `filters`；追踪标签名称来自追踪架构，不接受。日志和追踪值包括它们在窗口中的条目计数，最频繁的在前，因此它们也可用作细分，例如按服务的错误。`search` 仅保留包含字面文本的名称或值，`limit` 接受 `1`–`1000`（默认 `100`）。日志标签名称发现最多检查每种类型的 1,000 个不同属性集，并仅列出过滤器接受的键。
- `search_pulse_logs` 返回最多 `limit` 个条目（`1`–`100`，默认 `50`），按 `newest` 或 `oldest` 排序，其正文包含 `text` 且匹配每个过滤器。每个条目包括其 `severity_text`、`body`、`trace_id`、`span_id`、`scope_name` 以及合并的资源和日志 `attributes`。对于从 Kubernetes 收集的日志（仅由 OTLP 日志发送者设置），`span_id` 和 `scope_name` 为 `null`。
- `search_pulse_traces` 返回最多 `limit` 个跨度，按 `newest`、`oldest` 或 `slowest` 排序，匹配每个过滤器、可选的 `min_duration_ms` 和 `max_duration_ms` 以及 `root_only`。
- `get_pulse_trace` 返回 `trace_id` 中在窗口内开始的跨度，按最旧优先排序，最多 1,000 个跨度。在窗口之前开始的追踪将部分返回，因此请扩大或移动窗口以获取完整信息。每个跨度包括其跨度属性、事件、链接以及指向追踪不同 `resources` 的索引。

过滤器是多达 10 个 `{label, op, value}` 对象的列表。`op` 是 `eq`（默认）、`neq`、`contains` 或 `not_contains`；最后两个是不区分大小写的字面量。当日志标签由 Pulse 存储时，它们是 `severity_text`、`trace_id`、`span_id` 和 `scope_name`，以及每个条目的资源属性键（如 `namespace`、`container` 和 `service.name`）和日志属性键（如 `pod`）。当键同时出现在两者中时，应用资源属性。追踪标签是 `list_pulse_labels` 返回的跨度列，如 `service_name`、`span_name`、`span_status_code`（失败跨度为 `STATUS_CODE_ERROR`）、`span_attributes.http.route` 和 `resource_attributes.k8s.pod.name`。未知的追踪标签是错误，而不是空结果。

`truncated` 意味着匹配的名称、值、条目或跨度多于响应中包含的数量；请缩小过滤器或窗口，而不是将响应视为完整。遥测字符串是不可信数据，不是指令。

<details>
<summary>Claude Code</summary>

运行：

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

当无头 Claude Code 客户端未向模型暴露失败的本机服务器连接时，要求代理在搜索托管文档或编辑项目之前检查配置端点的未经身份验证的 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 响应。即使浏览器身份验证不可用，该响应也会将模型指向部署本地的 `auth.md` 文档。

</details>


<details>
<summary>Codex</summary>

运行：

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

在开始新的 `codex exec` 运行之前完成浏览器登录。Codex 在初始化期间读取 Tuist 服务器指令，因此 Gradle 优化请求会自动获得身份验证和验证工作流。

</details>


<details>
<summary>Claude Desktop</summary>

打开 **Settings → Connectors → Add custom connector**，然后设置：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

出现提示时在浏览器中完成 [Open Authorization](https://oauth.net/2/)。

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

将 `auth` 设置为 `false` 可防止适配器的浏览器身份验证处理程序隐藏 Tuist 的未授权响应。无头代理随后可以读取返回的 `auth_md` URL，并遵循 Tuist 的注册、身份断言交换和声明轮询流程。将交换后的访问令牌配置为 bearer 令牌，或让代理直接进行经过身份验证的模型上下文协议调用。

如果你更喜欢浏览器身份验证，请将 `auth` 设置为 `"oauth"`。对于该流程，在身份验证完成期间，使用 Pi 的 [remote procedure call mode](https://pi.dev/docs/latest/rpc) 保持一个进程存活：

```bash
pi --mode rpc
```

不要将待处理的浏览器身份验证拆分到单独的 `pi --print` 调用中，因为拥有回调状态的进程已退出。

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

然后对服务器进行身份验证：

```bash
opencode mcp auth tuist
```

</details>


<details>
<summary>Cursor</summary>

打开 **Cursor Settings → Tools & Integrations → Model Context Protocol Tools** 并添加：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Visual Studio Code</summary>

使用 **Command Palette → MCP: Add Server**，然后配置具有以下设置的 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 服务器：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

打开 **Agent panel → Settings → Add Custom Server**，然后设置：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

如果你的代理支持 `auth.md`，它可以匿名启动而无需打开浏览器。当提供者身份已链接时，受信任的提供者身份也可以在没有浏览器的情况下完成。对于服务验证的电子邮件、匿名声明或首次提供者链接，代理会向你显示一个 Tuist 验证链接和六位代码。打开链接，登录，并在 Tuist 页面上输入代理的代码。切勿将代码发送回代理。Tuist 的授权服务器元数据直接指向部署自身的 `/auth.md`，其中包含确切的请求和轮询结构。

## Amp orbs 和 Claude Code 云会话中的代理

在连接到 Tuist 账户的沙箱中运行的编码代理可以使用其自身的身份令牌向端点进行身份验证，无需浏览器或存储的 Tuist 凭据：

- 账户在 **Settings → Integrations → Amp** 下连接的 Amp 工作区或项目的 **Amp orbs** 会发送 orb 的 ID 令牌。在 Amp 中，将服务器的 `Authorization` 标头设置为 `Bearer ${amp:id-token}`。Amp 为服务器 URL 的来源铸造令牌，因此 URL 必须是此 Tuist 实例自身的地址，并在令牌过期前刷新它。为其他来源铸造的令牌将被拒绝。
- 连接的 Claude Code 环境的 **Claude Code cloud sessions** 会发送 Tuist 作为 `TUIST_OIDC_TOKEN` 传递给它们的会话令牌。将标头设置为 `Bearer ${TUIST_OIDC_TOKEN}`。

Tuist 的 Linux 沙箱不会为你添加服务器：它们附带 Tuist CLI（使用相同身份登录）和一个技能，用于告知代理何时根据项目历史记录检查结果。若要也为代理提供 MCP 工具，请使用上述标头将服务器添加到你的 Amp 或 Claude Code 设置中，或添加到项目的 `.mcp.json`。

这些令牌提供对连接账户每个项目的只读访问权限：它们携带 `mcp` 组的读取范围，不包含创建、更改或删除数据（例如静音或跳过测试）的范围。断开工作区或环境连接将在下一个请求时停止访问，且访问权限永远不会超过令牌本身的有效期。连接到多个 Tuist 账户的 Amp 工作区将被拒绝，因为其令牌未指定单一账户。当连接缺失时，未授权响应的 `error_description` 会说明这一点。

此只读访问权限仅适用于模型上下文协议端点。同一沙箱中的命令行工具和构建系统集成仍会交换令牌以获取连接的 CI 访问权限。

## WebMCP

在支持 [WebMCP](https://webmachinelearning.github.io/webmcp) 的浏览器中，Tuist 的页面通过 `document.modelContext` 注册工具，因此内置于浏览器的代理可以在无需额外配置的情况下调用它们。调用在 Tuist 服务器上运行。

- **Website and documentation pages** 注册文档和源代码工具（`search_tuist`、`search_tuist_code`、`list_tuist_files` 和 `read_tuist_file`）。它们不需要你登录。
- 当你登录时，**An account's dashboard pages** 会为该账户注册 Tuist 的只读工具。每个页面仅为其显示的内容注册工具，针对项目的构建系统：Gradle 项目的构建页面获得 Gradle 构建工具，其测试页面获得测试和覆盖率工具，运行器页面获得运行器工具，沙箱页面获得沙箱工具。每个页面还获得文档工具 `list_projects` 和 `get_project`。工具以登录用户的身份运行，因此它们只能访问你在仪表板中可以读取的数据，且仅限你正在查看的账户。当你移动到另一个页面或账户时，工具会被该页面的工具替换。

创建、更改或删除数据的工具无法通过 WebMCP 使用，因为浏览器代理会在你未添加它们的情况下接收这些工具，并读取构建和测试产生的内容。连接 MCP 客户端到 `/mcp` 端点以使用这些工具。

如果组织强制单点登录，请使用其提供者登录仪表板以使用其工具。

## 构建系统集成使用两个凭据

用于模型上下文协议工具的凭据不会对 Gradle 插件或 Bazel 的远程服务进行身份验证。在代理编辑或验证 Gradle 或 Bazel 集成之前，它应运行：

```bash
tuist auth whoami --url https://tuist.dev
```

如果该命令未经过身份验证，代理必须停止并要求用户运行：

```bash
tuist auth login --url https://tuist.dev
```

对于本地或自托管部署，请替换两个命令和 `tuist.toml` 中的 URL。在所有地方保持主机名拼写一致。例如，`localhost` 和 `127.0.0.1` 使用单独存储的凭据。


## 功能

### 工具

以下工具可通过 Tuist 模型上下文协议服务器使用：

每个工具都发布人类可读的描述以及明确的输入和输出模式。成功的调用返回符合所宣传输出模式的结构化内容，以及序列化为文本的相同结果，供尚不支持结构化内容的客户端使用。

接受单个记录标识符的工具（如 `build_run_id`、`test_run_id`、`test_case_id`、`bundle_id`、`run_id`、`generation_id` 或 `cache_run_id`）也接受该记录的 Tuist 仪表板 URL。直接从浏览器粘贴 URL，而不要从中提取标识符。

`get_xcode_build`、`get_test_run`、`get_gradle_build` 和 `get_project` 可以包含 `side_quests`：项目未使用但记录显示会有帮助的 Tuist 功能。每个功能都有一个 `id`、一个说明其依据证据的 `tip`，以及一个 `docs` 链接。要求代理先完成用户的请求，提及适用的附加建议，并仅在用户同意时执行其中一项。这些建议仅返回给项目账户的成员，无论他们是通过用户会话、MCP 令牌还是代理身份连接：

| ID | 工具 | 建议时机 |
|----|------|----------------|
| `xcode_compilation_cache` | `get_xcode_build` | 使用 Xcode 26 或更高版本处理的干净构建未运行任何可缓存的编译任务。 |
| `gradle_build_cache` | `get_gradle_build` | 构建执行了可缓存的任务，但 Gradle 的构建缓存未为其中任何任务计算键值，这意味着构建缓存已关闭。 |
| `flaky_test_quarantine` | `get_test_run` | 一次运行包含不稳定测试，且项目中没有启用的自动化将其静音或跳过。不建议用于 Struo 项目。 |
| `test_sharding` | `get_test_run` | 在 Tuist 支持分片的构建系统中，一次未分片的 CI 运行耗时 10 分钟或更久。提示会说明选择性测试当时跳过了多少测试。 |
| `tuist_runners` | `get_xcode_build`, `get_test_run` | 一次 CI 运行使用了 GitHub Actions、Bitrise、GitLab CI 或 Buildkite 机器，且该账户从未在 Tuist Runners 上运行过作业。仅适用于 tuist.dev。 |
| `pull_request_comments` | `get_xcode_build`, `get_test_run` | 一次 GitHub Actions 运行属于一个未连接到其 GitHub 仓库的项目。 |
| `other_build_systems` | `get_project` | 该账户并未在所有支持的构建系统中使用 Tuist。提示列出了标识其他系统的文件，以便代理检查仓库。 |

#### 文档和社区搜索

此只读工具通过驱动文档网站的同一搜索引擎，搜索 Tuist 的文档、[应用程序编程接口](https://en.wikipedia.org/wiki/API)参考、GitHub 发布、社区论坛和 GitHub Issues。发布结果包括产品、版本、发布日期和预发布状态。默认搜索稳定版本，可以使用 `include_prereleases` 包含预发布版本。该工具仅在托管于 `https://tuist.dev/mcp` 的 Tuist 服务器上可用。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `search_tuist` | 搜索公开的 Tuist 文档、应用程序编程接口参考、GitHub 发布、社区讨论和 GitHub Issues。可选择限制为一个 `source`（`docs`、`api_reference`、`releases`、`forum`、`issues`）。 | `query` |

#### 反馈

当 Tuist 工具或提示未按预期工作时（例如结果令人困惑、出现错误、数据缺失或缺少功能），代理可以告知 Tuist 团队。要求代理建议提交报告，并仅在您同意后发送。每份报告都会开启与 Tuist 支持的对话，他们可能会通过电子邮件回复您。报告包括代理的预期结果、实际发生的情况、可选建议、您的 Tuist 用户 ID、句柄和电子邮件，以及您所属的组织。代理还可以指明问题发生的账户和项目，以便团队知道跟进哪个组织；仅接受您所属的账户。只有以 Tuist 用户身份登录的代理才能发送报告，每个用户每小时最多可提交 10 份报告。该工具仅在托管于 `https://tuist.dev/mcp` 的 Tuist 服务器上可用。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `report_feedback` | 报告 Tuist 工具或提示的问题。可选择命名 `tool_name`、问题发生的 `account_handle` 和 `project_handle`，并添加 `suggestion`。 | `category`, `expected`, `actual` |

#### 基于源代码的回答

这些只读工具允许代理使用与托管服务器一起部署的确切公共 Tuist 源代码修订版作为事实来源，以回答依赖于当前行为的问题。它们仅在 `https://tuist.dev/mcp` 可用。

兼容的客户端在初始化期间会收到关于工具源代码修订版、链接和结果限制的事实描述，以及内联 OAuth 身份验证信息。这些描述不规定回答风格或验证工作流程。用户可以直接提问，而无需先调用 `ask_tuist` 提示；该提示仍可用于显式的基于源代码的工作流程。

每个操作都有固定的并发、持续时间、遍历、读取字节数和响应大小限制。搜索和列表结果包括 `truncated` 和 `truncation_reason` 字段。当结果被截断时，请缩小路径、文件模式或搜索词的范围，而不是将结果视为详尽无遗。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `search_tuist_code` | 通过搜索源文件来回答有关当前行为、默认值、配置、功能开关、错误处理或未记录细节的问题。结果包括周围行、固定修订版的源代码链接和扫描统计信息。 | `pattern` |
| `list_tuist_files` | 当相关路径未知时，发现源子系统或附近的测试。列表具有有限的深度和结果数量。 | 无 |
| `read_tuist_file` | 在找到相关路径后，检查实现文件、调用点或测试中的特定行范围。截断的响应提供 `next_start_line` 以继续。 | `path` |

#### 项目

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_accounts` | 列出经过身份验证的用户可用的个人和组织账户句柄，包括每个账户是否可以创建项目。 | 无 |
| `get_organization` | 获取组织的成员目录。待处理的邀请需要与仪表板相同的管理员权限；永远不会返回邀请接受令牌。 | `account_handle` |
| `create_organization` | 为经过身份验证的用户创建 Tuist 组织。 | `handle` |
| `create_project` | 在经身份验证的用户可访问的账户下创建 Tuist 项目。 | `account_handle`, `project_handle` |
| `add_organization_member` | 将现有的 Tuist 用户添加到组织或更新现有成员的角色。接受 `user`（默认）、`admin` 或 `viewer`，其中查看者可以读取仪表板和运行记录，但无法更改任何内容。 | `organization_handle`, `email` |
| `invite_organization_member` | 邀请电子邮件地址加入组织，无论该地址是否属于现有的 Tuist 用户。Tuist 会发送一封包含接受链接的电子邮件，该链接在 14 天后过期；当服务器无法发送电子邮件时，`email_sent` 为 `false`，必须从仪表板复制链接。接受 `user`（默认）、`admin` 或 `viewer`。需要组织管理员权限。 | `organization_handle`, `email` |
| `cancel_organization_invitation` | 取消待处理的组织邀请，使其链接无法再被接受。需要组织管理员权限。 | `organization_handle`, `email` |
| `list_projects` | 列出经身份验证的用户可访问的所有项目。 | 无 |
| `get_project` | 获取项目的配置和连接的仓库 URL。 | `account_handle`, `project_handle` |
| `connect_project_repository` | 将项目链接到账户的 GitHub App 安装可访问的 GitHub 仓库。项目采用仓库的默认分支。需要项目管理员权限。 | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | 移除项目与其 GitHub 仓库的链接。需要项目管理员权限。 | `account_handle`, `project_handle` |

#### 账户令牌

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_account_tokens` | 列出账户令牌元数据，不暴露令牌值。 | `account_handle` |
| `get_account_token` | 获取账户令牌元数据，不暴露其值。 | `account_handle`, `token_id` |
| `list_project_tokens` | 列出项目令牌元数据，不暴露令牌值。 | `account_handle`, `project_handle` |

#### 通知规则

这些工具管理经过身份验证的用户的自有通知规则：当规则所涵盖的项目中发生事件（例如新的预览），或者在未列出具体项目时在你可接收通知的任何项目中发生事件，且满足其条件时，执行其操作，例如向你的 Tuist 应用设备发送推送通知。如果没有规则，你将不会收到任何通知。它们需要用户身份验证，仅作用于你自己的规则，并且仅接受你所属账户的项目。它们不提供给仪表板页面，因为规则跨越你所有的账户。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_notification_events` | 列出规则可以订阅的事件类型，每种类型都带有用于其条件的 JSON Schema。 | 无 |
| `list_notification_condition_options` | 建议项目中事件的条件值，例如其最近预览的轨道和分支。 | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | 列出你的规则。 | 无 |
| `create_notification_rule` | 根据事件、可选项目和条件以及至少一个操作创建规则。 | `event`, `actions` |
| `update_notification_rule` | 更改规则的启用状态、项目、条件或操作。 | `rule_id` |
| `delete_notification_rule` | 删除规则。 | `rule_id` |

#### 持续集成运行器

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_runner_jobs` | 列出账户的持续集成运行器作业。 | `account_handle` |
| `get_runner_job` | 获取持续集成运行器作业，包括其机器是否内存不足、停止原因以及需要更改的内容。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | 列出为持续集成运行器作业记录的步骤。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | 列出为持续集成运行器作业记录的机器指标。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | 列出持续集成运行器作业最多 500 条捕获的日志行。 | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | 列出账户的持续集成工作流汇总。 | `account_handle` |
| `list_runner_profiles` | 列出账户的持续集成运行器配置文件，并包含每个配置文件的 `runs-on` 标签。 | `account_handle` |
| `get_runner_catalog` | 列出运行器配置文件可用的机器规格和 Xcode 版本。 | `account_handle` |
| `create_runner_profile` | 创建包含平台、机器规格以及在 macOS 上的 Xcode 版本的运行器配置文件。可选择设置哪些分支保存其缓存卷。需要账户管理权限或 `account:runners:write` 作用域。 | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | 更改运行器配置文件的机器规格、Xcode 版本，或哪些分支保存其自定义缓存卷的变更。省略的字段保持其值不变。需要账户管理权限或 `account:runners:write` 作用域。 | `account_handle`, `profile_name` |
| `delete_runner_profile` | 经用户确认后删除运行器配置文件。默认配置文件无法删除。需要账户管理权限或 `account:runners:write` 作用域。 | `account_handle`, `profile_name` |

运行器卷工具公开与“卷”仪表板相同的数据。读取工具需要运行器访问权限；清除操作需要账户管理权限或 `account:runners:write` 作用域，以及用户确认。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_runner_volumes` | 按名称和仓库过滤、排序并分页显示卷。 | `account_handle` |
| `get_runner_volume` | 仓库、平台、容量、已用空间和最后使用时间。 | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | 分页显示作业和工作流引用、缓存状态、命中结果和挂载时间。 | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | 由作业挂载的卷。 | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | 存储序列、作业运行次数、命中率和趋势。可选 `volume_id`、`start` 和 `end`（ISO 8601）；默认为七天，最长 90 天。 | `account_handle` |
| `delete_runner_volume` | 删除卷及其保存的内容。正在运行的作业保留其私有副本但无法保存；后续使用相同密钥的作业将从空状态开始。 | `account_handle`, `volume_id` |

列表接受 `page` 和 `page_size`（最多 100）。卷清单还接受 `name` 和 `repository`（精确匹配，以 AND 组合）、`sort_by`（`volume`、`repository`、`used_space`、`capacity`、`last_used`）和 `sort_order`（`asc`、`desc`）。未知的测量值和命中结果保持为 `null`。缓存状态描述是否保存了卷变更，而非作业成功与否。

#### 沙盒

沙盒工具公开与沙盒仪表板相同的数据和操作，并具有与 [API](https://tuist.dev/api/docs) 相同的访问权限：账户成员可以使用账户中每个沙盒上的所有工具。只读查看者无法使用它们。账户需要启用沙盒功能。仪表板的沙盒页面注册只读工具。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_sandboxes` | 分页显示沙盒及其状态、规格和时间戳。可选 `search`（沙盒中的文本、Amp Orb 或 Anthropic 会话 ID）、`status`、`vcpus`、`sort_by`（`created`、`last_active`、`identifier`）和 `sort_order`。 | `account_handle` |
| `get_sandbox` | 沙盒的状态、规格、节点、归档和时间戳。 | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU 小时数、创建的沙盒数量、会话、设置和启动持续时间，以及相对于账户限制的峰值 vCPU、内存和磁盘使用情况，附带趋势。可选 `start` 和 `end`（ISO 8601）；默认为 30 天，最长 90 天。 | `account_handle` |
| `create_sandbox` | 启动一个空白沙盒并在其运行后返回。可选 `platform`（`linux` 或 `darwin`）、`xcode_version`（macOS 沙盒的确切 Xcode 版本，从工具描述列出的版本中选择；隐含 `darwin`）、`repository`（macOS 沙盒的 github.com `owner/name`，连接到账户的一个项目：当 Linux Claude Code 环境具有 macOS 设置脚本时，Mac 从其 <.localized_link href="/guides/features/sandboxes/claude#remote-mac-snapshots">就绪快照</.localized_link> 启动）、`template`、`vcpus` 搭配 `memory_mb`（Linux：2x4096、4x8192 或 8x16384，默认 2x4096；macOS：8x8192、8x16384 或 8x24576，默认 8x8192）、`workspace_gb` 和 `lifetime_seconds`（在取消运行中的命令、暂停并归档沙盒之前允许运行的时长，保留其文件：默认两小时，最多一天）。其描述指示代理查找仓库构建所使用的 Xcode 版本（`.xcode-version`、mise、CI 配置或文档）并传递该版本，因为其他 Xcode 版本会错过仓库的缓存和快照，阅读 Mac 上位于 `/opt/tuist/agent-guide.md` 的指南，并使用下方的模拟器工具展示在 iOS 模拟器中运行的应用。Mac 上的 Tuist（当仓库固定版本时为其固定版本）会自行 <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">使用账户的缓存</.localized_link>。 | `account_handle` |
| `pause_sandbox` | 将正在运行的沙盒快照保存到其节点的磁盘。 | `account_handle`, `sandbox_id` |
| `resume_sandbox` | 恢复已暂停或归档的沙盒。 | `account_handle`, `sandbox_id` |
| `extend_sandbox` | 从现在开始重新启动沙盒的生命周期，可选 `lifetime_seconds`（最多一天）。由集成拥有的沙盒没有生命周期。 | `account_handle`, `sandbox_id` |
| `archive_sandbox` | 排队将已暂停沙盒的磁盘移动到对象存储。 | `account_handle`, `sandbox_id` |
| `delete_sandbox` | 经用户确认后删除沙盒及其磁盘。 | `account_handle`, `sandbox_id` |
| `list_sandbox_devices` | 沙盒的设备及其 `id`、`name`、`platform`、`runtime` 和 `state`（`Booted`、`Shutdown`）。目前这些是 macOS 沙盒的模拟器，例如 iOS；尚不支持 Android 模拟器。 | `account_handle`, `sandbox_id` |
| `boot_sandbox_device` | 按名称或 ID 启动设备并等待最多 40 秒；模拟器会显示在“模拟器”应用中。启动已启动的设备会成功。 | `account_handle`, `sandbox_id`, `device` |
| `launch_sandbox_app` | 在已启动的设备上启动应用，如果应用正在运行则重启它。传递 `app_path`（在沙盒中构建的 .app）以先安装它，或传递 `app_id`（在 iOS 上为捆绑包 ID）以使用已安装的应用。当有多个设备启动时，可选 `device`。 | `account_handle`, `sandbox_id` |
| `open_sandbox_url` | 在浏览器（iOS 上的 Safari）中打开网页，或在已启动的设备上打开应用的深层链接。可选 `device`。 | `account_handle`, `sandbox_id`, `url` |
| `get_sandbox_screenshot` | 返回已启动设备的图像，或使用 `target: screen` 返回沙盒的整个屏幕图像：JPEG 格式，较长边最多 1600 像素，以适应代理的上下文。可选 `device`。如需磁盘上的全尺寸 PNG，请使用 `tuist sandbox screenshot`。 | `account_handle`, `sandbox_id` |

设备工具在沙盒中运行固定命令；它们不运行你传递的命令，只有 CLI 的 `tuist sandbox exec` 可以执行。它们在 Linux 沙盒上回答 `devices_unsupported`，在设备启动前回答 `device_not_booted`，对于沙盒没有的名称或 ID 回答 `device_not_found`，对于缺失的 `app_path` 或未安装的应用回答 `app_not_found`。

沙盒工具的错误以单独一行上的稳定代码开头，例如 `code: fleet_busy`，随后是需要执行的操作；伴随等待的代码会添加一行 `retry_after_seconds:`。API 在其错误主体中发送相同的 `code`。当所有主机都繁忙时，`create_sandbox` 会在回答 `fleet_busy` 之前等待最多 25 秒。

#### Amp 工作区

这些工具管理 <.localized_link href="/guides/server/authentication#amp-orbs">Amp 工作区连接</.localized_link>，允许 orbs 无需令牌即可登录 Tuist。它们使用与仪表板“集成”页面相同的仅限管理员权限。orb 中的代理可以从 `$AMP_WORKSPACE_ID` 和 `$AMP_PROJECT_ID` 读取其自身的 ID。连接允许的每个 orb 都能获得对账户中所有项目的 CI 访问权限，因此代理应在连接前与用户确认。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_amp_workspace_connections` | 列出账户连接的 Amp 工作区以及每个工作区限制的项目（如果有）。 | `account_handle` |
| `connect_amp_workspace` | 连接 Amp 工作区。可选 `project_id` 将登录限制为单个 Amp 项目的 orbs。 | `account_handle`, `workspace_id` |
| `disconnect_amp_workspace` | 断开工作区连接。其 orbs 已有的会话保持有效，直到过期。 | `account_handle`, `connection_id` |

#### Claude 环境

这些工具连接 Claude Managed Agents 自托管环境，使其会话在 Tuist 沙盒中运行，如同“设置”→“集成”→“Claude”所做的那样。它们需要账户管理权限并启用沙盒。代理可以使用 Anthropic 的 API 创建环境，但只有 Claude Console 能生成其环境密钥，因此代理会向用户索取该密钥。Tuist 使用 Anthropic API 密钥或工作负载身份联合启动会话，并在保存之前使用该凭据获取环境。Anthropic 端的设置使用用户自己的 Anthropic 凭据；Tuist 永远不会接收这些凭据。密钥通过客户端和模型传递，因此请仅显式提供它们。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_claude_environments` | 列出已连接的环境及其使用的凭据，以及联合规则应信任的发行人 URL 和主题前缀。 | `account_handle` |
| `connect_claude_environment` | 使用 `api_key` 连接环境，或使用 `organization_id`、`workspace_id`、`service_account_id` 和 `federation_rule_id`。可选 `platform`、`vcpus` 和 `memory_mb` 设置沙盒规格。 | `account_handle`, `environment_id`, `environment_key` |

#### 组织 AI

这些工具管理组织的服务器端 AI 任务所使用的模型，如同“设置”→“AI”所做的那样，并遵循其规则：仅限组织管理员，且仅适用于具有 AI 设置的组织。每个任务（例如 `pulse_grouping` 或 `pulse_explanation`）在有任务路由时使用该路由，否则使用默认模型；如果两者都没有，则不发送请求。每个工具返回整个配置，包括每个任务的当前模型以及它是来自其路由、默认模型还是无。添加或编辑提供商需要 API 密钥，因此需在仪表板或 REST API（`/api/accounts/{handle}/ai`）中进行，而不是通过这些工具。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `get_organization_ai_configuration` | 读取提供商（不含密钥）、模型、默认模型、任务路由以及每个任务的当前模型。 | `account_handle` |
| `save_organization_ai_model` | 添加模型（`name`、`provider_id`、`upstream_model_id`），或通过 `id` 更新模型。 | `account_handle` |
| `remove_organization_ai_model` | 删除模型及其任务路由。 | `account_handle`, `model_id` |
| `set_organization_ai_default_model` | 选择默认模型，或使用 null 清除它。 | `account_handle`, `model_id` |
| `save_organization_ai_task_route` | 将 `task` 路由到配置的 `model_id`，或通过 `id` 更新路由。一个任务最多有一个路由。 | `account_handle` |
| `remove_organization_ai_task_route` | 删除路由，使任务再次使用默认模型。 | `account_handle`, `route_id` |
| `remove_organization_ai_provider` | 删除提供商及其密钥、模型和它们的路由；取消链接已关联的 Claude 组织。 | `account_handle`, `provider_id` |

#### Webhooks

Webhook 工具使用与仪表板相同的仅限管理员权限。交付尝试包含为端点记录的请求和响应数据，但绝不包含端点签名密钥。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_webhook_endpoints` | 列出账户的 Webhook 端点。 | `account_handle` |
| `get_webhook_endpoint` | 获取 Webhook 端点。 | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | 列出端点的交付尝试。 | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | 获取交付尝试。 | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode 构建

用于 Xcode、Gradle、Bazel、Mix 和 Cargo 的构建详情工具公开现有的 `custom_metadata: {tags, values}` 结构，包括基础设施观测数据（如果已报告）。值保持为字符串，并保留不熟悉的键。例如，`tuist.cpu.available_processors` 描述运行时可用的逻辑处理器，而 `tuist.gradle.max_workers` 是 Gradle 工作器限制，`tuist.jvm.max_heap_bytes` 是 JVM 堆限制，而非主机内存。这些是不可信的客户端观测数据，而非经过验证的运行器身份。缺失的观测数据保持缺失；导入的日志和较旧的客户端可能没有基础设施元数据。Struo 元数据等待协调的客户端/协议更新。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_xcode_builds` | 列出项目的 Xcode 构建运行。 | `account_handle`, `project_handle` |
| `get_xcode_build` | 获取特定 Xcode 构建运行的详细信息，包括包含原始 `.xcactivitylog` 的归档文件的临时下载 URL。 | `build_run_id` |
| `list_xcode_build_targets` | 列出特定 Xcode 构建运行的构建目标。 | `build_run_id` |
| `list_xcode_build_files` | 列出特定 Xcode 构建运行的编译文件。 | `build_run_id` |
| `list_xcode_build_steps` | 列出记录的构建步骤，包含耗时和结果，但不包含日志文本。 | `build_run_id` |
| `get_xcode_build_step` | 获取一个记录的构建步骤，包括其日志和截断标志。 | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | 列出特定构建运行的构建问题（警告和错误）。 | `build_run_id` |
| `list_xcode_build_cache_tasks` | 列出特定 Xcode 构建运行的可缓存任务（缓存命中/未命中）。 | `build_run_id` |
| `list_xcode_build_cas_outputs` | 列出特定 Xcode 构建运行的[内容寻址存储](https://en.wikipedia.org/wiki/Content-addressable_storage)输出。 | `build_run_id` |

`list_xcode_build_steps` 默认返回每页 20 个步骤（通过 `page_size` 最多 100 个），并提供 `page` 和 `pagination_metadata` 用于导航。使用 `search` 匹配标题、项目或目标，或过滤确切的 `project`、`target`、`category`（例如 `swiftCompilation`）和 `status`（`success` 或 `failure`）。按 `duration_ms` 排序以首先显示最慢的步骤（默认），或按 `start_ms` 排序以显示时间顺序。步骤 ID 用于打破平局，并作为十进制字符串返回以保留其完整的 64 位精度。ID 仅限于单个构建，不应跨构建匹配。

可选的 `start_ms` 和 `end_ms` 选择与从构建开始计算的毫秒时间范围重叠的步骤；结束时间是独占的。这两个工具都接受构建 UUID 或仪表板 URL 作为 `build_run_id`。将返回的步骤 `id` 原样作为 `step_id` 传递以检索其日志。每个步骤的日志最多保留 64 KiB，`log_truncated` 指示省略的输出。

处理 Xcode 构建时默认会收集步骤。记录的步骤数据保留 90 天。列表响应包括 `availability`：当存在记录的步骤时为 `available`，即使过滤器不匹配任何内容；当构建仍在处理且尚未有步骤时为 `processing`；或者当步骤未被记录或已过期时为 `unavailable`。

HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` 和 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` 上提供相同的操作，具有相同的过滤器和分页。两者都需要对构建的项目具有读取权限。

#### Gradle 构建

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | 返回完整的身份验证、项目设置、Gradle 插件、缓存策略和两次构建验证工作流。代理在编辑现有的 Android 或 Gradle 项目之前应调用此方法。 | 无 |
| `list_gradle_builds` | 列出项目的 Gradle 构建运行，包括自定义元数据。使用可选的 `tag` 参数按自定义标签进行过滤。 | `account_handle`, `project_handle` |
| `get_gradle_build` | 获取构建元数据、任务/缓存计数以及 `failures`：每个失败任务和配置步骤的失败消息。 | `build_run_id` |
| `list_gradle_build_tasks` | 列出任务结果、复合构建标识、可缓存性、增量状态和失败消息。 | `build_run_id` |
| `list_gradle_build_steps` | 列出定时任务、配置和转换，支持搜索、元数据和重叠时间过滤器。 | `build_run_id` |
| `get_gradle_build_step` | 通过不透明 ID 检查记录的步骤元数据；失败任务或配置步骤的 `log` 是其失败消息。 | `build_run_id`, `step_id` |

Gradle 和 Bazel 步骤列表默认返回 20 个结果（最多 100 个），支持 `search`、确切的 `project`、`target`、`category` 和 `status`、重叠的 `start_ms` / `end_ms` 过滤器（结束时间独占），以及 `duration_ms` 或 `start_ms` 排序。原样传递返回的 ID；它们仅限于其构建。列表公开 `time_origin` 和 `coverage`。较旧的 Gradle 报告使用 `first_recorded_timestamp`，因为没有上传构建开始时间。Bazel 配置文件通过 `trace_profile` 覆盖范围和作为时间起点的 `profile_start` 公开所有记录的间隔。较旧的构建回退到保留的 BEP 摘要。源记录在 90 天后过期。Bazel 详细信息在发布时包括经过清理的操作日志。失败任务或配置步骤的 Gradle 详细信息包括 Tuist Gradle 插件作为 `log` 报告的失败消息：异常消息及其原因链，如同 Gradle 控制台打印的那样，没有堆栈跟踪或任务输出，项目内的路径变为相对路径，凭据和其他本地路径被脱敏，每个步骤最多 16 KiB，每次构建最多 32 个失败步骤。其他 Gradle 步骤、由较旧插件版本报告的构建以及无凭据报告的 `log` 为 null。配置步骤在失败时报告 `failure`，否则报告 `unknown`。`compare_builds` 提示使用此覆盖范围来区分完整的 Bazel 跟踪和保留的摘要，并在检查更广泛的调用输出之前，引导代理查看步骤详情以获取操作结果和日志。

单步工具 `get_gradle_build_step` 和 `get_bazel_build_step` 通过 ID 检索步骤，不接受时间过滤器；使用相应的列表工具按时间范围过滤步骤。

如果在列出和获取步骤之间到达完整配置文件，则从保留摘要返回的 Bazel 步骤 ID 仍然可读。步骤数据已过期的索引配置文件报告为不可用。Gradle 步骤列表包括零持续时间的缓存和跳过操作。

#### Bazel 调用

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | 返回身份验证、项目设置、Bazel 配置和验证工作流。 | 无 |
| `list_bazel_invocations` | 按最新顺序列出完成的[Bazel 构建事件协议](https://bazel.build/remote/bep)调用，包括构建指标、有界的执行时间线、关键路径诊断以及与项目相关的远程缓存总数。按 `status`、`git_branch`、`git_commit_sha`、`is_ci` 和 `command` 过滤。 | `account_handle`, `project_handle` |
| `get_bazel_invocation` | 获取一个完成的 Bazel 调用，包括构建指标、有界的执行时间线、关键路径诊断以及与项目相关的远程缓存总数。 | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | 列出记录的 Bazel 配置文件间隔，带有过滤器和明确的覆盖范围。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | 检查记录的 Bazel 步骤及其发布的操作结果和经过清理的日志。 | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_remote_actions` | 列出 Tuist 远程执行为调用运行的操作，包括助记符、目标、操作摘要、退出代码、执行路径和阶段计时。可选的 `sort_by`（`duration` 或 `queued_at`）、`failed` 和 `mnemonic` 过滤器。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_remote_action` | 获取一个远程操作的 argv、环境（类似秘密的值被掩码）、平台、工作目录、输出路径、工作器、退出代码、stdout 和 stderr 的前 16 KiB、在 stderr 中识别的编译器 `errors`、阶段计时和操作摘要。 | `account_handle`, `project_handle`, `invocation_id`, `action_id` |
| `get_bazel_remote_action_log` | 按字节偏移量读取远程操作的 stdout 或 stderr 最多 64 KiB，默认为流的末尾。长流会被完整复制，或者如果更长则保留前 16 KiB 和后 16 MiB；`recorded` 列出可用范围。 | `account_handle`, `project_handle`, `invocation_id`, `action_id`, `stream` |
| `list_bazel_invocation_logs` | 按执行顺序列出为 Bazel 调用捕获的经过清理的日志：Bazel 进度输出的有界尾部以及 `test.log` 工件。可选的 `stream`（`stdout` 或 `stderr`）、`source`（`progress` 或 `test_log`）、`target_label` 和 `errors` 过滤器可缩小结果范围。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | 获取为 Bazel 调用捕获的一个经过清理的日志块。 | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | 列出原始的 Bazel 远程缓存观察结果，包括其操作、端点和观察时间，可选择缩小到特定调用、结果或操作。 | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | 获取一个原始的 Bazel 远程缓存观察结果。 | `account_handle`, `project_handle`, `cache_event_id` |

#### 远程执行

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `get_remote_execution_activity` | 列出项目当前正在运行的 Bazel 调用及其正在运行和排队的远程操作，包括每个操作的调用、助记符、目标、操作摘要、机器大小以及进入该状态的时间。执行网关在预先准备的 VM 上运行的操作在完成之前不会列出。 | `account_handle`, `project_handle` |
| `get_remote_execution_usage` | 获取项目在 `[from, to)` 期间的远程执行情况和测量的执行时间，包括总计、按机器大小、按调度模式以及按小时、天或月统计。时间段默认为最近 30 天，最多跨越 366 天。 | `account_handle`, `project_handle` |

`list_bazel_invocations` 过滤器为精确匹配，在同一秒内完成的调用按调用 ID 排序。要查找分支上最新的失败调用，请使用 `status: "failure"`、`git_branch` 和 `page_size: 1` 进行调用。REST 端点 `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations` 接受相同的过滤器。

在 `list_bazel_build_steps` 上设置 `remote_execution: true` 以仅返回具有安全关联的服务器阶段计时的操作（来自索引配置文件）。列表和详细响应公开可选的可空值 `remote_queue_ms`、`remote_input_fetch_ms`、`remote_execution_ms` 和 `remote_output_upload_ms`。这些值对记录的阶段求和，包括操作内的重试；缺失或空值表示不可用，而非零。它们是配置文件观察结果，并非计费用量或新鲜执行的证明，因为缓存的服务器结果可能携带执行元数据。客户端上传被排除在外。即使发生了远程工作，较旧或不明确的配置文件也可能不返回匹配的操作。步骤 REST 端点接受相同的 `remote_execution=true` 过滤器。仪表板的“远程执行”选项卡使用相同的查询和 90 天保留期。

测试日志携带其来源测试结果的 `target_label` 和尝试 `status`，因此 `target_label: "//foo:bar_test"` 仅返回该目标的测试日志。`errors: true` 返回失败尝试的测试日志以及包含 Bazel 报告器以 `ERROR:`、`FAIL:` 或 `TIMEOUT:` 开头的行的 stderr 进度块。进度输出不归因于目标，在记录归因之前写入的日志字段为空。失败的操作及其输出可通过 `list_bazel_build_steps` 按目标获取，每个测试用例的失败信息可通过测试运行工具获取。

#### Cargo 构建

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_cargo_builds` | 列出项目的 Cargo 构建，按最新顺序排列。按 `git_branch`、`status`、`is_ci` 或 `command` 过滤。Cargo 测试执行结果可通过测试工具获取，而非此构建列表。 | `account_handle`, `project_handle` |
| `get_cargo_build` | 获取构建元数据、聚合缓存计数器以及最多 500 个带有诊断信息的已记录编译器作业。`compilations_truncated` 指示省略的作业；诊断信息仅涵盖返回的作业。 | `account_handle`, `project_handle`, `build_id` |

在 `get_cargo_build` 上设置 `include_cache_inspection: true` 以检索经过验证的任务决策和 CAS 操作，限制为 4 MB。默认情况下，以及当记录缺失或无效时，`cache_inspection` 为空。请尊重其部分捕获的 `truncated` 标志；传输不建立每个任务命中的本地/远程来源。HTTP 详细端点接受相同的查询参数。

#### Mix 构建

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_mix_builds` | 列出项目的 Mix (Elixir) 编译构建，按最新顺序排列，包括自定义元数据。按 `git_branch`、`status`、`is_ci` 或 `mix_env` 过滤。 | `account_handle`, `project_handle` |
| `get_mix_build` | 获取构建元数据、诊断计数和依赖缓存摘要。 | `account_handle`, `project_handle`, `build_id` |

#### 构建跟踪

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `get_build_trace` | 获取 Xcode、Gradle、Bazel 或 Mix 构建时间线的下载链接，作为可在 [Perfetto](https://ui.perfetto.dev) 中打开的跟踪文件。 | `account_handle`, `project_handle`, `build_id` |

`build_id` 是构建运行 ID（Bazel 的调用 ID）或构建的仪表板 URL。返回的 `trace_url` 提供 [Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSON 文件。任何持有该链接的人都可以在 `expires_at`（调用后一小时）之前无需其他凭据即可下载该构建的跟踪文件。代理可以使用 `curl` 下载它，交给你在 Perfetto 中打开，或使用 Perfetto 的 `trace_processor` 进行查询。跟踪文件包含按并行性打包到通道中的记录步骤、跨越整个构建的轨道，以及在构建记录机器指标时的 CPU 和内存计数器。它包含与上述步骤工具相同的数据，但不含日志。仪表板从每个构建的“时间线”选项卡提供相同的文件。

#### Struo 运行

<a id="once-runs"></a>

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_once_runs` | 列出项目的 Struo 运行，按最新顺序排列。按 `kind`（`build`、`test` 或 `generic`）、`status`、`is_ci` 或 `git_branch` 过滤。未完成的运行状态为 `in_progress`。 | `account_handle`, `project_handle` |
| `get_once_run` | 获取一次运行，包括其操作总数、缓存摘要，对于测试运行还包括测试总数。 | `account_handle`, `project_handle`, `run_id` |

Cargo 构建、Mix 构建和 Struo 运行 ID 在项目内是唯一的。通过 HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`、`.../mix/builds` 和 `.../once/runs` 上可提供相同的读取操作，每个都有一个用于单个 ID 的详细端点。

#### 任务、操作、模块和文件

这些项目级工具用于检查跨运行的持久构建标识。首先使用 `list_build_entities`，然后将返回的稳定 `id` 与相同的 `kind` 一起传递给 `get_build_entity` 或 `list_build_entity_history`，同时提供 `account_handle` 和 `project_handle`。无需构建或调用标识符。

| 工具 | 描述 | 必需参数 |
| --- | --- | --- |
| `list_build_entities` | 列出在项目构建中看到的某一类任务、模块、操作或文件。 | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | 获取一个构建实体，包括其原生标识和所选时间段的分析数据。 | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | 列出一个构建实体的记录执行、编译或缓存事件，按最新顺序排列。 | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | 工具链 | 历史列表 |
| --- | --- | --- |
| `bazel_actions` | Bazel 操作 | BEP 报告的操作执行 |
| `gradle_tasks` | Gradle 任务 | 任务执行 |
| `xcode_modules` | Xcode 模块 | 编译和模块缓存事件 |
| `once_actions` | Struo 操作 | 执行 |
| `mix_files` | Mix 编译文件 | 编译 |
| `mix_modules` | Mix 编译模块 | 编译 |
| `cargo_crates` | Cargo crate | 记录的 rustc 调用 |

这些工具正在逐步推出，仅返回已启用它们的项目的数据；对于其他项目，它们返回错误而非空结果。只有使用其构建工具链的项目才可用某种类型。这些工具接受有界的 `start_at`/`end_at` 过滤器、`environment`（`any`、`ci` 或 `local`）以及精确的 `branch`。`list_build_entities` 接受 `q`；`list_build_entity_history` 支持不透明的 `after`/`before` 游标。未知的时间或缓存观测值保持不可用，而不是变为零或缺失。历史记录引用记录的父级和原生执行，以便使用现有的运行工具进行深入分析。

`get_build_entity` 指标包括 `duration_samples`，即具有记录时间的观测值数量：真正的零持续时间计入，缺少时间不计入。此计数可能低于观测值计数；不可用的持续时间统计信息保持为空。

Xcode 模块的持续时间来自构建日志中测量的目标编译。模块缓存解析和没有编译工作的目标不提供持续时间样本。编译观测值引用 Xcode 构建；缓存事件引用生成或缓存命令。

Bazel 操作通过目标标签、助记符和配置的主要输出来识别，在不依赖输入相关缓存摘要的情况下保持单独的操作和配置 distinct。历史记录 BEP 报告的执行，而不是缓存查找或跟踪配置文件阶段。完整的执行覆盖需要 `--build_event_publish_all_actions`；工件交付是尽力而为，因此缺失的观测值并不意味着没有工作运行。较旧的没有稳定标识或执行开始的 Kura 负载仍然被接受但未编入索引。缺失的结束时间测量保持不可用，真正的零持续时间计入。

Mix 模块的持续时间测量包含文件的编译，而不是独立测量的模块工作。当客户端报告目标映射时，Struo 操作使用声明的目标/能力/索引槽位；仅诊断标签不是稳定标识。现有客户端和运行级工具保持不变地得到支持。

Cargo crate 按确切记录的 crate 根、名称和类型分组。检出路径更改可能会分割历史记录，并且不区分构建配置文件、功能和目标三元组。历史记录测量 rustc 调用，而不是每个文件的工作或缓存命中；缺失的作业不确立删除或完整的工作区清单。

分析读取具有有限的内存和执行时间。如果查询超过这些限制，工具将返回错误而不是虚构一个空结果。

新观测值在部署后编入索引；此功能不回填现有的运行遥测数据。在 <.localized_link href="/guides/server/data-retention">数据保留政策</.localized_link> 下，身份元数据的寿命长于单个观测值。

#### 测试

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_test_runs` | 列出项目的测试运行，每个都带有其 `selective_testing_strategy`。按 `selective_testing`（`coverage`，包括基于覆盖率的选择的回退，或 `module_hash`）过滤。`query` 字段是 `git_branch`、`scheme`、`status` 和 `selective_testing`：`field:"value"` 精确匹配，`field~"value"` 匹配不区分大小写的子字符串（不适用于 `selective_testing`），前导 `-` 否定任一运算符。例如，`-git_branch~"gh-readonly-queue"` 排除合并队列分支。空格分隔的查询过滤器和显式参数以 AND 语义组合。 | `account_handle`, `project_handle` |
| `get_test_run` | 获取测试运行的详细指标，包括其自身的代码覆盖率（`coverage`：是否测量了任何内容、其行数和数值，以及是否是部分的或从脏检出运行）、其选择性测试摘要（`selective_testing`：策略、基线提交，以及请求、选择、跳过和估计的测试计数，这些用于计算测试选择有效性），以及其结果包（`.xcresult`）和运行它的命令的会话归档（CLI 日志）的临时下载 URL，或者当没有命令链接到运行时为 `null`。分片运行的 `result_bundle_url` 是第一个报告分片的包；`shard_result_bundles` 列出每个分片报告的包，包括 CI 重试，及其分片索引和状态，因此可以检查失败但没有失败测试的分片。 | `test_run_id` |
| `list_test_module_runs` | 列出特定测试运行的测试模块运行。 | `test_run_id` |
| `list_test_suite_runs` | 列出特定测试运行的测试套件运行，可选按模块过滤。 | `test_run_id` |
| `list_test_cases` | 列出项目的测试用例（支持如 `flaky` 等过滤器）。 | `account_handle`, `project_handle` |
| `get_test_case` | 获取测试用例的详细指标，包括可靠性率、不稳定性率和运行次数。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | 列出测试用例运行，可选按测试用例或测试运行过滤。 | `account_handle`, `project_handle` |
| `get_test_case_run` | 获取特定测试用例运行的失败详情和重复情况，以及当其运行的基于覆盖率的选择保留了该测试时的原因（`selective_testing`：决策、原因、匹配的变更文件和分片）。 | `test_case_run_id` |
| `list_test_case_run_attachments` | 列出测试用例运行的附件。每个附件都包含一个临时下载 URL。 | `test_case_run_id` |
| `list_test_case_events` | 列出测试用例的状态变更，例如将其静音或跳过。 | `test_case_id` |
| `update_test_case` | 更新测试用例的状态或不稳定分类。变更可以向配置的 webhook 端点（包括外部服务）发送事件。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | 列出测试运行的选择性测试目标结果。 | `test_run_id` |
| `list_selective_testing_tests` | 列出测试运行的基于覆盖率的选择所决定、选择和跳过的测试，包括每个决策的原因、选择它的变更文件、其分片以及在运行中的结果。按 `decision`、`reason` 或 `search` 过滤。 | `test_run_id` |
| `list_selective_testing_changed_files` | 列出自测试运行的基于覆盖率的选择基线以来发生变更的文件，包括每个文件选择了多少测试，以及它是否是因变更导致选择回退的跟踪文件。 | `test_run_id` |
| `get_coverage` | 获取项目的代码覆盖率及其目标，在某个提交或分支的最新完整提交处。如果没有 `git_commit_sha` 或 `branch`，则读取默认分支。 | `account_handle`, `project_handle` |
| `list_coverage_files` | 列出某个提交的代码覆盖率所测量的文件及其行覆盖率，在某个提交或分支的最新完整提交处。支持 `search`、排序和分页。 | `account_handle`, `project_handle` |
| `get_coverage_file` | 获取文件的代码覆盖率及其函数，在某个提交或分支的最新完整提交处。设置 `include_lines` 以获取每行的执行计数。 | `account_handle`, `project_handle`, `path` |
| `list_coverage_branches` | 列出具有代码覆盖率的分支，默认分支排在前面。 | `account_handle`, `project_handle` |
| `list_coverage_commits` | 列出分支的提交及其覆盖率状态（`complete`、`incomplete`、`in_progress`、`not_measured`）、数值以及相对于之前完整提交的变更，最新的排在前面。使用游标分页。 | `account_handle`, `project_handle` |
| `list_coverage_runs` | 列出位于某个提交或分支之后的具有代码覆盖率的测试运行，每个标记为 `full`、`partial` 或 `discarded`（脏检出）。使用游标分页。 | `account_handle`, `project_handle` |
| `list_coverage_targets` | 列出某个提交按目标的覆盖率，随后是其运行从二进制缓存中获取但没有覆盖率计数器的目标（`measured: false`）。支持 `search`、排序和分页。 | `account_handle`, `project_handle` |

代码覆盖率工具可供启用了代码覆盖率的账户使用。

#### 包

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_bundles` | 列出项目的包（应用二进制文件）。可选按 `git_branch` 和 `tags` 过滤（所有标签必须精确匹配）。 | `account_handle`, `project_handle` |
| `get_bundle` | 获取特定包的详细信息，包括自定义标签。 | `bundle_id` |
| `get_bundle_artifact_tree` | 获取包的完整构件树，作为按路径排序的平面列表。 | `bundle_id` |

`list_bundles` 接受 `tags: ["paid", "production"]` 以区分构建变体或环境。标签是区分大小写的标签，包含字母、数字、连字符或下划线，最多 10 个标签，每个标签最多 50 个字符。列表和详细结果包括 `custom_metadata.tags`。分页计数和分支过滤器应用于带标签的结果；省略 `tags` 保留未过滤的行为。无效的标签过滤器将返回错误，而不是扩大查询范围。

#### 生成

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_generations` | 列出项目的生成运行。 | `account_handle`, `project_handle` |
| `get_generation` | 获取特定生成运行的详细信息。 | `generation_id` |

#### 缓存运行

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_cache_runs` | 列出项目的缓存运行。 | `account_handle`, `project_handle` |
| `get_cache_run` | 获取特定缓存运行的详细信息，包括其会话归档（CLI 日志）的临时下载 URL。 | `cache_run_id` |
| `list_xcode_module_cache_targets` | 列出生成或缓存运行的模块缓存目标，显示每个目标的缓存命中/未命中状态和诊断组件哈希，包括额外的哈希输入。 | `run_id` |

#### 预览

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_previews` | 列出项目的可共享应用预览。 | `account_handle`, `project_handle` |
| `get_preview` | 获取预览及其构建的临时下载 URL。 | `preview_id` |
| `get_latest_preview` | 查找正在运行的应用二进制的最新预览。 | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### 自动化

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_automation_alerts` | 列出项目的自动化警报。 | `account_handle`, `project_handle` |
| `get_automation_alert` | 获取自动化警报。 | `alert_id` |
| `list_automation_alert_revisions` | 列出自动化警报的修订历史。操作凭据已脱敏。 | `alert_id` |
| `list_project_notification_alerts` | 列出项目通知警报规则。需要与仪表板设置页面相同的管理员权限。Webhook 地址已脱敏。 | `account_handle`, `project_handle` |

### 事件

使用无状态 `2026-07-28` 模型上下文协议生命周期的客户端可以调用 `events/list` 来发现事件及其负载架构：

| 事件 | 发送时机 | 订阅过滤器 |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | 测试用例从非不稳定变为不稳定。 | `account_handle`, `project_handle` |
| `build.failed` | 本地或持续集成 Xcode、Gradle 或 Bazel 构建以失败结束。 | `account_handle`, `project_handle` |
| `test_run.failed` | 本地或持续集成测试运行以失败结束，包括合并的分片运行或放弃的运行。 | `account_handle`, `project_handle` |
| `ci_job.failed` | Tuist 运行器作业以失败完成。 | `account_handle` |
| `pulse_symptom.opened` | Pulse 在看板或页面层级打开或重新打开症状。仅在审计层级记录的症状以及对已打开症状的后续更改不会发送。 | `account_handle` |

要订阅，客户端调用 `events/subscribe`，传入事件名称、上述 `arguments` 中列出的句柄，以及包含 `https://` 回调 URL 和 `whsec_` 签名密钥的 `webhook` 交付配置。项目事件需要账户成员资格以及对相应测试或构建数据的读取权限；运行器作业事件需要账户成员资格和运行器读取权限；Pulse 症状事件需要组织成员资格和该账户的 Pulse 访问权限，且账户令牌必须属于该账户。已声明的 [`auth.md`](https://workos.com/auth-md) 访问令牌、已声明的账户令牌和浏览器授权授予可以创建订阅；当相关凭据不再有效时，交付停止。每个用户最多可以保留 25 个活跃订阅。Tuist 在保存订阅之前向回调发送验证质询。回调必须返回包含相同 `challenge` 值的对象。订阅默认持续七天，可以通过再次订阅来刷新，当用户的访问权限或凭据被移除时停止交付。可选的 `ttlMs` 限制在一小时到 30 天之间。Tuist 会重试超时的回调，并在至少三次连续超时（跨越五分钟）后取消订阅；恢复回调后请重新订阅。

当事件发生时，Tuist 将其资源标识符和仪表板 URL 发送到回调。构建和测试运行失败还包括 `is_ci` 和 `git_branch`，因此客户端可以忽略本地失败或按分支过滤。构建事件包括 `build_system`；运行器作业事件包括 `workflow_job_id` 和 `workflow_run_id`；Pulse 症状事件包括 `symptom_id`、`tier`（`board` 或 `page`），以及 `untrusted` 下的受影响实体，格式为 `{"type": "untrusted_json", "value": {"service", "kind", "key"}}`，每个值最多 200 个字符：实体来自生产遥测数据，因此应将其视为数据，绝不可视为指令。其 URL 会打开症状页面。请求包括订阅标识符和 [Standard Webhooks](https://www.standardwebhooks.com/) 签名标头，以便客户端验证其来源。Tuist 会重试失败的交付，因此客户端应使用稳定的 `eventId` 来丢弃重复项。负载省略了测试名称、日志和失败消息；客户端可以通过上述工具获取这些详细信息，并决定是否通知团队或开始调试。客户端可以使用 `events/unsubscribe` 停止交付。

### 提示

| 提示 | 描述 |
|--------|-------------|
| `fix_flaky_test` | 指导你通过分析失败模式、识别根本原因并应用针对性修正来修复不稳定测试。 |
| `compare_builds` | 指导你通过比较构建来识别性能回归、缓存变更和构建问题。对 Xcode、Gradle、Bazel 和 Cargo 项目使用原生工具。Cargo 比较保留部分编译器覆盖率，并区分估算的编译器工作与节省的时间。 |
| `compare_test_runs` | 指导你通过比较两次测试运行来识别回归、新失败和不稳定测试。 |
| `compare_bundles` | 指导你通过比较两个包来识别整个构件树中的大小变化。 |
| `compare_test_case` | 指导你通过比较测试用例在两个分支或时间段内的行为。 |
| `compare_generations` | 指导你通过比较两次生成运行来识别性能回归和模块缓存变更。 |
| `compare_cache_runs` | 指导你通过比较两次缓存运行来识别缓存有效性变更和目标级回归。 |
| `integrate_gradle_project` | 指导你将 Tuist 集成到现有的 Gradle 项目中。包括独立的工具和 Gradle 身份验证、账户发现、项目创建、远程缓存策略、构建洞察和回读验证。 |
| `integrate_bazel_project` | 指导你创建或选择 Bazel 项目、对命令行进行身份验证、配置远程缓存和构建洞察，并通过 Tuist 构建数据验证集成。 |
| `integrate_xcode_project` | 指导你将 Tuist 集成到现有的 Xcode 项目中。支持 Xcode 缓存、构建洞察、测试洞察和测试分片。 |
| `ask_tuist` | 使用公开资料作为上下文，并以聚焦的实现和测试证据作为当前行为的真实来源，来回答 Tuist 问题。它需要一个 `question` 并引用与修订版本绑定的证据。 |

项目数据提示接受 `account_handle` 和 `project_handle`，以便将调查范围限定在特定项目。比较提示还接受 `base` 和 `head` 参数，以指定要比较的两个项目（通过 ID、仪表板 URL 或分支名称）。`ask_tuist` 接受 `question` 而非项目参数。`integrate_gradle_project` 还接受 `features`，这是一个逗号分隔的 Gradle 集成列表，包括：`remote_cache`、`build_insights`、`test_insights`、`flaky_tests` 和 `test_sharding`。`integrate_bazel_project` 接受可选的 `server_url`，用于自托管或本地安装。`integrate_xcode_project` 接受包含 `xcode_cache`、`build_insights`、`test_insights` 和 `test_sharding` 的 `features`。

#### Gradle 集成提示功能

`integrate_gradle_project` 提示和 `get_gradle_integration_guide` 工具记录了完整的设置工作流。服务器的初始化说明中也引用了该工具，这使得不枚举提示的代理也能发现它。

| 功能 | 代理配置的内容 |
|---------|---------------------------|
| `remote_cache` | 启用 Gradle 的构建缓存，配置 Tuist 远程缓存上传策略，并建议仅从具有本地只读使用权的持续集成运行器进行上传。 |
| `build_insights` | 应用 Tuist Gradle 插件，并在需要时配置构建分析上传行为。 |
| `test_insights` | 应用 Tuist Gradle 插件，以便自动上传 Gradle `Test` 任务结果。 |
| `flaky_tests` | 指导设置不稳定测试检测、可选的 Gradle Test Retry 插件用法以及测试隔离配置。 |
| `test_sharding` | 添加用于 `tuistPrepareTestShards`、分片矩阵生成和基于 `TUIST_SHARD_INDEX` 的测试执行的持续集成工作流。 |

当省略 `features` 时，提示会要求代理澄清用户想要哪些集成，或在编辑 Gradle 项目之前从请求中推断出最小的有用集合。

#### Xcode 集成提示功能

`integrate_xcode_project` 提示记录了 Tuist 支持的每项 Xcode 集成：

| 功能 | 代理配置的内容 |
|---------|---------------------------|
| `xcode_cache` | 配置 `tuist setup cache`、生成项目的缓存设置、手动 Xcode 缓存构建设置，以及仅限于持续集成运行器的上传策略。 |
| `build_insights` | 通过 `tuist setup insights` 配置 `tuist inspect build`、`tuist xcodebuild`、`-resultBundlePath` 以及可选的机器指标。 |
| `test_insights` | 配置 `tuist inspect test`、方案测试后操作以及用于持续集成测试运行的结果包生成。 |
| `test_sharding` | 添加带有 `TUIST_SHARD_INDEX` 的 Xcode 或生成项目的分片规划和分片执行工作流。 |

当省略 `features` 时，提示会要求代理澄清用户想要哪些集成，或在编辑 Xcode 项目之前从请求中推断出最小的有用集合。
