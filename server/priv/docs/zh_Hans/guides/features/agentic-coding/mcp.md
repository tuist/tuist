---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · 智能体编码 · 功能 · 指南 · Tuist",
  "description": "通过 Tuist 的 MCP 端点，让 AI 智能体访问测试洞察等数据。"
}
---
# Model Context Protocol

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro) 是一项开放标准，允许人工智能代理与外部服务和数据源进行交互。它使 [Claude](https://claude.ai/)、[Claude Code](https://docs.anthropic.com/en/docs/claude-code)、[Codex](https://developers.openai.com/codex/) 等应用，以及 [Zed](https://zed.dev)、[Cursor](https://www.cursor.com) 或 [Visual Studio Code](https://code.visualstudio.com) 等编辑器能够与 Tuist 互操作。

Tuist 在 `https://tuist.dev/mcp` 托管服务器端 Model Context Protocol 端点。通过将客户端连接到该端点，代理可以访问你的 Tuist 项目数据，包括测试洞察、不稳定测试分析等。大多数工具为只读，且作用域限于经过身份验证的 Tuist 项目数据。账户设置工具可以列出账户、创建组织、创建项目，并在经过身份验证的用户拥有所需权限时将现有用户添加到组织中。每个工具都会声明注解，说明其是否为只读、是否可能导致难以撤销的更改，以及是否可以更改公共互联网状态。`update_runner_profile`、`update_notification_rule` 和 `connect_claude_subscription` 声明 `destructiveHint: true`，因为它们可能会替换现有配置或凭据。账户设置工具需要用户身份验证。它们不适用于项目令牌或普通账户令牌。当用户在浏览器中授权客户端或认领 `auth.md` 注册时，Tuist 仅在该 Model Context Protocol 端点上将该凭据与用户关联，以便设置工具完成请求的工作流。

Tuist 实现了 [2026-07-28 protocol](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)。请求是无状态的：客户端随每个请求发送其协议元数据，并可以直接调用工具而无需初始化。`server/discover` 返回服务器的身份、功能、支持的版本和说明。不存在会话标识符或独立的事件流。使用 2025-06-18 或 2025-03-26 初始化流程的客户端仍然受支持；它们也无需服务器会话即可运行。

## Model Context Protocol 与 skills 对比

Model Context Protocol 工具和 <.localized_link href="/guides/features/agentic-coding/skills">skills</.localized_link> 的功能可能存在重叠。鉴于目前两者之间的重叠，请为每个工作流选择一种方法并一致使用，而不是在同一流程中混合使用两者。

对于支持插件安装的客户端，请使用 <.localized_link href="/guides/features/agentic-coding/plugins">Tuist plugins</.localized_link> 一起安装两者。

## 配置

将 `https://tuist.dev/mcp` 添加为客户端中的远程 Model Context Protocol 服务器。服务器的初始化说明和公开服务器卡片内联描述了带有动态客户端注册的 OAuth 2.0 以及标准浏览器授权流程，无需代理获取或遵循外部身份验证文档。这些服务器范围的说明保持工作流指导的通用性：工具身份验证不会对本地命令行工具或构建系统集成进行身份验证，代理应通过相关的 Tuist 工具验证请求的更改。特定于构建系统的设置和身份验证检查记录在集成指南和提示中。Tuist 仍然分别在 `https://tuist.dev/auth.md` 发布 [Open Authorization](https://oauth.net/2/) 发现元数据和当前的 [auth.md protocol](https://workos.com/auth-md)。

如果你的某个组织强制实施单点登录，则在浏览器中授权客户端需要通过该组织登录的会话，必要时 Tuist 会先将你重定向到提供商。请参阅 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">single sign-on</.localized_link>。

该端点接受无状态的 `2026-07-28` Model Context Protocol 请求生命周期（包括 `server/discover`），以及较旧的基于会话的生命周期。现有客户端可以继续使用其当前的连接方法。

支持 Model Context Protocol 事件的客户端可以订阅项目事件。有关可用事件和交付要求，请参阅 [Events](#events)。

已经支持远程浏览器身份验证的客户端可以继续在浏览器中进行身份验证。支持 `auth.md` 的客户端和代理可以匿名注册、提供受信任的提供商身份断言，或启动服务身份验证的电子邮件认领。注册返回由 Tuist 签名的身份断言，代理在标准令牌端点将其交换为一小时访问令牌。Tuist 发布其公钥签名密钥，并支持标准令牌撤销和提供商安全事件交付。

未经身份验证的代理应读取 Model Context Protocol 端点返回的 `WWW-Authenticate` 标头，获取受保护资源元数据，获取授权服务器元数据，并遵循其 `agent_auth.skill` URL。Tuist 还在未授权响应正文中返回相同的本地 `auth_md` URL，以便由语言模型驱动的客户端无需依赖原生客户端集成即可发现该流程。部署本地文档是端点名称、请求正文、认领轮询和断言交换的真实来源。

在代理启动电子邮件认领之前，必须要求用户确认其 Tuist 账户的电子邮件地址。不得从提供商个人资料、Git 配置、环境变量或会话元数据中推断该地址。

该端点使用 `mcp` 范围组。匿名预认领凭据可以发现功能并阅读公共集成指南，但不被视为已登录用户。在浏览器授权或认领后，凭据具有用户范围，每个工具应用与仪表板相同的授权检查。详情请参阅 <.localized_link href="/guides/server/authentication#scope-groups">scope groups documentation</.localized_link>。

工具解析为经过身份验证的用户已经可以读取的项目。Xcode 和 Gradle 构建工具接受构建 UUID 或仪表板 URL。UUID 必须唯一标识一个项目；如果它出现在多个项目中，工具将返回未找到，而不是选择另一个项目的报告。项目范围的仪表板和 API 读取仍然可用。报告的行为者标识符是未经验证的标签，不是凭据或额外的访问权限。

构建列表和详情工具公开可选的 `tuist_version` 元数据：用于 Xcode 和 Cargo 的报告 Tuist CLI、用于 Gradle 的 Tuist Gradle 插件，以及用于 Mix 的 `tuist_ex` 库。Xcode 还从其关联的项目生成事件中公开 `tuist_generation_version`，这可能与上传的 CLI 不同。缺失的观察值为 null，不会从服务器或其他报告中推断。Bazel 使用其现有的 `bazel_version`；Once 运行详情公开 `once_version`。这些字段描述报告的版本，而非经过验证的身份或网络协议版本。REST 构建端点公开相同的元数据。现有集成和不稳定测试技能不依赖版本字段，无需更改工作流。

Tuist 操作员通过 Tuist 的内部运营工具调查客户账户，该工具记录每次调用；直接连接到此端点不会获得超出用户自身成员资格之外的任何访问权限。

### Pulse

Pulse 公开用于账户运营指标、日志和追踪的只读工具，均通过 `account_handle` 寻址。前两个镜像 Pulse 页面及其 REST API；另外五个让代理直接探索遥测数据，没有等效的 REST 接口：

| 工具 | 用途 | `/api/accounts/:account_handle/pulse` 下的 REST 等效项 |
| --- | --- | --- |
| `query_pulse` | Pulse 页面表格 | `GET /:signal` |
| `get_pulse_analytics` | Pulse 页面小部件 | `GET /:signal/analytics` |
| `query_pulse_metrics` | 即时或范围 PromQL | 无 |
| `list_pulse_labels` | 标签名称，或某个标签的值 | 无 |
| `search_pulse_logs` | 过滤后的日志条目 | 无 |
| `search_pulse_traces` | 过滤后的跨度 | 无 |
| `get_pulse_trace` | 单个追踪的所有跨度 | 无 |

Pulse 仅限于服务器配置组织的当前成员，即使账户或项目是公开的。它需要用户身份验证或与用户关联的 `mcp` 凭据以及账户读取授权。项目令牌、普通账户令牌、匿名注册以及没有组织成员资格的操作员访问权限都不授予 Pulse 访问权限。凭据无法选择其他后端或遥测租户，且只有服务器配置的账户拥有 Pulse 遥测数据，因此没有任何工具可以读取其他账户的数据。浏览器代理仅在 Pulse 页面上接收这些工具，且在该页面的账户范围内。

REST 需要用户凭据。OAuth 和 `auth.md` 用户关联仅在 `/mcp` 端点上可用；没有当前用户的账户凭据将被拒绝，无论关联账户的成员资格或可见性如何。

`query_pulse` 接受 `signal`（`metrics`、`logs` 或 `traces`）、可选的 `query` 和 `range`（`15m`、`1h`、`6h` 或 `24h`，默认 `1h`）。指标接受 PromQL 表达式。日志和追踪接受与日志正文和跨度名称匹配的字面量、不区分大小写的文本；`*`（默认值）选择所有内容。追踪行是单个跨度。表格接受 `search`、`page`（默认 `1`）、`page_size`（`1`–`100`，默认 `20`）、`sort_by` 和 `sort_order`（`asc` 或 `desc`）。排序列取决于信号，并在工具模式中列出。过滤器包括 `service` 和日志 `level`。过滤器运算符使用相应的 `_op` 参数（`eq`、`contains` 或 `not_contains`），默认为精确相等。

指标的排序列为 `name`/`value`；日志为 `timestamp`/`service`/`level`/`message`/`trace_id`；追踪为 `timestamp`/`service`/`name`/`duration_ms`/`trace_id`。仪表板有意公开子集；API 和工具接受每个信号的完整列表。

表格响应包含 `rows`、`series`、`warnings` 和 `meta`。分页元数据包括 `page`、`page_size`、`total_count`、`total_pages`、`has_next_page`、`has_previous_page` 和 `end_at`。将返回的 ISO8601 `end_at` 与后续页面一起传递以保留查询窗口。结果限制错误需要缩小查询或时间范围，而不是将响应视为空表。

日志和追踪在本地排序之前最多检查 100 个最新匹配项。过滤器、排序、分页和总数仅描述那些返回的匹配项，而非整个时间窗口。缩小查询文本或时间范围以检查其他匹配项；更改本地搜索或排序不会扩展上游搜索。聚合小部件保持独立，是完整窗口的查询，而不是这些有界表格结果的聚合。

指标表格在 `end_at` 处对其表达式求值一次，返回当前值和每个即时向量系列的一个点。范围向量表达式可以返回有界的历史点。单独的 analytics 小部件提供固定的历史图表；表格不会为每个匹配系列具体化时间网格以仅显示其最新值。

遥测字符串是不可信数据，不是指令。

`get_pulse_analytics` 除了账户句柄外，仅接受 `signal` 和 `range`。其固定小部件独立于表格表达式、过滤器、排序和分页。REST 和 Model Context Protocol 使用相同的 Pulse 上下文和响应契约。REST 响应禁用缓存。

#### 探索遥测数据

探索工具读取 `15m`、`1h`、`6h` 或 `24h` 的窗口（默认 `1h`，`get_pulse_trace` 为 `24h`），结束于可选的 ISO8601 `end_at`，默认为现在。每个响应返回 `start_at` 和 `end_at`；再次传递相同的 `end_at` 以保持窗口。这些工具均不接受 SQL。

- `query_pulse_metrics` 在 `end_at`（`type: instant`，默认值）或在窗口期间每 `step` 秒（`type: range`）评估 `query`（PromQL 表达式）。步长默认为且不能小于窗口除以 360，因此一个系列最多有 361 个点。结果最多有 5,000 个系列。点是 `[unix_seconds, value]`，`NaN` 和无限值是字符串。即时查询拒绝 `range` 和 `step`。
- `list_pulse_labels` 接受 `signal`。如果没有 `label`，它列出标签名称；如果有 `label`，它列出该标签的值。对于指标，`__name__` 列出指标名称，任何其他标签的值都需要 `match`（系列选择器，例如 `up`）。日志和追踪标签值接受 `filters`；追踪标签名称来自追踪模式，不接受。日志和追踪值包括它们在窗口中的条目计数，最频繁的排在前面，因此它们也可用作细分，例如按服务划分的错误。`search` 仅保留包含字面文本的名称或值，`limit` 接受 `1`–`1000`（默认 `100`）。日志标签名称发现最多检查每种类型的 1,000 个不同属性集，并仅列出过滤器接受的键。
- `search_pulse_logs` 最多返回 `limit` 个条目（`1`–`100`，默认 `50`），按 `newest` 或 `oldest` 排序，其正文包含 `text` 且匹配所有过滤器。每个条目包括其 `severity_text`、`body`、`trace_id`、`span_id`、`scope_name` 以及合并的资源和日志 `attributes`。对于从 Kubernetes 收集的日志（仅由 OTLP 日志发送器设置），`span_id` 和 `scope_name` 为 `null`。
- `search_pulse_traces` 最多返回 `limit` 个 span，按 `newest`、`oldest` 或 `slowest` 排序，匹配所有过滤器、可选的 `min_duration_ms` 和 `max_duration_ms` 以及 `root_only`。
- `get_pulse_trace` 返回在窗口内开始的 `trace_id` 的 span，按最旧优先排序，最多 1,000 个 span。在窗口之前开始的追踪将部分返回，因此请扩大或移动窗口以获取完整数据。每个 span 包括其 span 属性、事件、链接以及指向追踪中不同 `resources` 的索引。

过滤器是多达 10 个 `{label, op, value}` 对象的列表。`op` 为 `eq`（默认）、`neq`、`contains` 或 `not_contains`；最后两个是不区分大小写的字面量。当日志标签由 Pulse 存储时，它们是 `severity_text`、`trace_id`、`span_id` 和 `scope_name`，以及每个条目的资源属性键（如 `namespace`、`container` 和 `service.name`）和日志属性键（如 `pod`）。当键同时出现在两者中时，应用资源属性。追踪标签是 `list_pulse_labels` 返回的 span 列，例如 `service_name`、`span_name`、`span_status_code`（失败 span 为 `STATUS_CODE_ERROR`）、`span_attributes.http.route` 和 `resource_attributes.k8s.pod.name`。未知的追踪标签会导致错误，而不是返回空结果。

`truncated` 表示匹配的姓名、值、条目或 span 多于响应中包含的数量；请缩小过滤器或窗口范围，不要将响应视为完整。遥测字符串是不可信数据，不是指令。

<details>
<summary>Claude Code</summary>

运行：

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

当无头 Claude Code 客户端未向模型暴露失败的原生服务器连接时，要求代理在搜索托管文档或编辑项目之前检查配置端点的未经身份验证的 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 响应。即使浏览器身份验证不可用，该响应也会将模型指向部署本地的 `auth.md` 文档。

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

Pi 不包含 Model Context Protocol 客户端。在审查其源代码和安全影响后，你可以安装第三方 [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) 扩展：

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

将 `auth` 设置为 `false` 可防止适配器的浏览器身份验证处理程序隐藏 Tuist 的未授权响应。无头代理随后可以读取返回的 `auth_md` URL，并遵循 Tuist 的注册、身份断言交换和声明轮询流程。将交换的访问令牌配置为 bearer 令牌，或让代理直接进行经过身份验证的 Model Context Protocol 调用。

如果你更喜欢浏览器身份验证，请将 `auth` 设置为 `"oauth"`。对于该流程，在身份验证完成期间，使用 Pi 的 [remote procedure call mode](https://pi.dev/docs/latest/rpc) 保持一个进程存活：

```bash
pi --mode rpc
```

不要将待处理的浏览器身份验证拆分到单独的 `pi --print` 调用中，因为拥有回调状态的进程已退出。

</details>


<details>
<summary>OpenCode</summary>

将 Tuist Model Context Protocol 服务器添加到 `opencode.json`：

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

如果你的代理支持 `auth.md`，它可以匿名启动而无需打开浏览器。当提供者身份已链接时，受信任的提供者身份也可以在没有浏览器的情况下完成。对于服务认证电子邮件、匿名认领或首次提供者链接，代理会向你显示 Tuist 验证链接和六位代码。打开链接，登录，并在 Tuist 页面上输入代理的代码。切勿将代码发送回代理。Tuist 的授权服务器元数据直接指向部署自己的 `/auth.md`，其中包含确切的请求和轮询形状。

## Amp orbs 和 Claude Code 云会话中的代理

在与 Tuist 账户连接的沙箱中运行的编码代理可以使用其自身的身份令牌向端点进行身份验证，无需浏览器或存储的 Tuist 凭据：

- 连接到 **Settings → Integrations → Amp** 下的账户的 Amp 工作区或项目的 **Amp orbs** 会发送 orb 的 ID 令牌。在 Amp 中，将服务器的 `Authorization` 标头设置为 `Bearer ${amp:id-token}`。Amp 会为服务器 URL 的来源颁发令牌，因此 URL 必须是此 Tuist 实例自身的地址，并在令牌过期前刷新它。为其他来源颁发的令牌将被拒绝。
- 已连接的 Claude Code 环境的 **Claude Code cloud sessions** 会发送 Tuist 作为 `TUIST_OIDC_TOKEN` 传递给它们的会话令牌。将标头设置为 `Bearer ${TUIST_OIDC_TOKEN}`。

Tuist 的 Linux 沙箱已预先配置好：Amp 的用户设置和 Claude Code 的用户配置中都有一个指向 `${TUIST_URL}/mcp` 的 `tuist` 服务器，以及 Tuist CLI 和一个技能，该技能会告知代理何时根据其结果对照项目历史记录进行检查。在其他地方，请自行添加具有上述标头的服务器。

这些令牌提供对已连接账户下每个项目的只读访问权限：它们携带 `mcp` 组的读取范围，不包含创建、更改或删除数据（例如静音或跳过测试）的范围。断开工作区或环境的连接会在下一个请求时停止访问，且访问权限永远不会超过令牌本身的有效期。连接到多个 Tuist 账户的 Amp 工作区将被拒绝，因为其令牌未指定单一账户。当缺少连接时，未经授权的响应中的 `error_description` 会说明这一点。

这种只读访问权限仅适用于 Model Context Protocol 端点。同一沙箱中的命令行工具和构建系统集成仍会交换令牌以获取连接的 CI 访问权限。

## WebMCP

在支持 [WebMCP](https://webmachinelearning.github.io/webmcp) 的浏览器中，Tuist 的页面会通过 `document.modelContext` 注册工具，因此内置于浏览器的代理无需任何额外配置即可调用它们。这些调用在 Tuist 服务器上运行。

- **Website and documentation pages** 注册文档和源代码工具（`search_tuist`、`search_tuist_code`、`list_tuist_files` 和 `read_tuist_file`）。它们不需要你登录。
- 当你登录后，**An account's dashboard pages** 会为该账户注册 Tuist 的只读工具。每个页面仅注册与其显示内容相关的工具，针对项目的构建系统：Gradle 项目的构建页面获得 Gradle 构建工具，其测试页面获得测试和覆盖率工具，运行器页面获得运行器工具，沙箱页面获得沙箱工具。个人账户 AI 设置页面的“订阅”部分获得 `list_ai_subscriptions`，它仅回答关于你自身账户的问题。每个页面还获得文档工具 `list_projects` 和 `get_project`。这些工具以登录用户的身份运行，因此它们只能访问你在仪表板中可以读取的数据，且仅限于你正在查看的账户。当你移动到另一个页面或账户时，工具会被替换为该页面的工具。

创建、更改或删除数据的工具无法通过 WebMCP 使用，因为浏览器代理会在你未添加它们的情况下接收这些工具，并读取构建和测试产生的内容。将 MCP 客户端连接到 `/mcp` 端点以使用这些工具。

如果组织强制实施单点登录，请使用其提供者登录仪表板以使用其工具。

## 构建系统集成使用两个凭据

用于 Model Context Protocol 工具的凭据不会验证 Gradle 插件或 Bazel 的远程服务。在代理编辑或验证 Gradle 或 Bazel 集成之前，它应运行：

```bash
tuist auth whoami --url https://tuist.dev
```

如果该命令未通过身份验证，代理必须停止并要求用户运行：

```bash
tuist auth login --url https://tuist.dev
```

对于本地或自托管部署，请替换两个命令和 `tuist.toml` 中的 URL。在所有地方保持主机名拼写一致。例如，`localhost` 和 `127.0.0.1` 使用单独的存储凭据。


## 功能

### 工具

以下工具可通过 Tuist Model Context Protocol 服务器使用：

每个工具都会发布人类可读的描述以及明确的输入和输出模式。成功的调用返回符合所宣传输出模式的结构化内容，以及为尚未使用结构化内容的客户端序列化为文本的相同结果。

接受单个记录标识符的工具，例如 `build_run_id`、`test_run_id`、`test_case_id`、`bundle_id`、`run_id`、`generation_id` 或 `cache_run_id`，也接受该记录的 Tuist 仪表板 URL。直接从浏览器粘贴 URL，而不是从中提取标识符。

`get_xcode_build`、`get_test_run`、`get_gradle_build` 和 `get_project` 可以包含 `side_quests`：项目未使用但记录显示会有帮助的 Tuist 功能。每个功能都有一个 `id`、一个说明其依据证据的 `tip` 和一个 `docs` 链接。要求代理先完成用户的请求，提及适用的支线任务，并仅在用户同意时执行其中一个。无论他们是通过用户会话、MCP 令牌还是代理身份连接，这些功能仅返回给项目账户的成员：

| ID | 工具 | 建议时机 |
|----|------|----------------|
| `xcode_compilation_cache` | `get_xcode_build` | 使用 Xcode 26 或更高版本处理的干净构建没有运行任何可缓存的编译任务。 |
| `gradle_build_cache` | `get_gradle_build` | 构建执行了可缓存的任务，但 Gradle 的构建缓存没有为其中任何任务计算密钥，这意味着构建缓存已关闭。 |
| `flaky_test_quarantine` | `get_test_run` | 一次运行包含不稳定测试，且项目中没有启用的自动化来静音或跳过它们。不建议用于 Once 项目。 |
| `test_sharding` | `get_test_run` | 在 Tuist 可以分片的构建系统中，未分片的 CI 运行耗时 10 分钟或更长时间。提示说明了选择性测试当时跳过了多少测试。 |
| `tuist_runners` | `get_xcode_build`, `get_test_run` | CI 运行使用了 GitHub Actions、Bitrise、GitLab CI 或 Buildkite 机器，且该账户从未在 Tuist Runners 上运行过作业。仅适用于 tuist.dev。 |
| `pull_request_comments` | `get_xcode_build`, `get_test_run` | GitHub Actions 运行属于未连接到其 GitHub 存储库的项目。 |
| `other_build_systems` | `get_project` | 该账户并未在所有支持的构建系统中使用 Tuist。提示列出了识别其他系统的文件，以便代理检查存储库。 |

#### 文档和社区搜索

此只读工具通过驱动文档网站的同一搜索引擎，搜索 Tuist 的文档、[应用程序接口](https://en.wikipedia.org/wiki/API)参考、GitHub 发布版本、社区论坛和 GitHub Issues。发布结果包括产品、版本、发布日期和预发布状态。默认搜索稳定版本，可以使用 `include_prereleases` 包含预发布版本。该工具仅在托管于 `https://tuist.dev/mcp` 的 Tuist 服务器上可用。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `search_tuist` | 搜索公开的 Tuist 文档、应用程序接口参考、GitHub 发布版本、社区讨论和 GitHub Issues。可选择限制为一个 `source`（`docs`、`api_reference`、`releases`、`forum`、`issues`）。 | `query` |

#### 反馈

当 Tuist 工具或提示未按预期工作时，代理可以向 Tuist 团队报告，例如结果令人困惑、出现错误、数据缺失或缺少功能。要求代理建议提交报告，并仅在您同意时发送。每份报告都会开启与 Tuist 支持的对话，他们可能会通过电子邮件回复您。报告包括代理的预期、实际发生的情况、可选建议、您的 Tuist 用户 ID、句柄和电子邮件，以及您所属的组织。代理还可以指明问题发生的账户和项目，以便团队知道跟进哪个组织；仅接受您所属的账户。只有以 Tuist 用户身份登录的代理才能发送报告，每个用户每小时最多可提交 10 份报告。该工具仅在托管于 `https://tuist.dev/mcp` 的 Tuist 服务器上可用。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `report_feedback` | 报告 Tuist 工具或提示的问题。可选择命名 `tool_name`、问题发生的 `account_handle` 和 `project_handle`，并添加 `suggestion`。 | `category`, `expected`, `actual` |

#### 基于源代码的回答

这些只读工具允许代理使用与托管服务器一起部署的确切公共 Tuist 源代码修订版作为事实来源，用于回答依赖于当前行为的问题。它们仅在 `https://tuist.dev/mcp` 可用。

兼容的客户端在初始化期间会收到有关工具源代码修订版、链接和结果限制的事实描述，以及内联 OAuth 认证信息。这些描述不规定回答风格或验证工作流程。用户可以直接提问，而无需先调用 `ask_tuist` 提示；该提示仍可用于显式的基于源代码的工作流程。

每个操作都有固定的并发、持续时间、遍历、读取字节数和响应大小限制。搜索和列表结果包括 `truncated` 和 `truncation_reason` 字段。当结果被截断时，请缩小路径、文件模式或搜索词的范围，而不是将结果视为详尽无遗。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `search_tuist_code` | 通过搜索源文件来回答有关当前行为、默认值、配置、功能开关、错误处理或未记录细节的问题。结果包括周围的行、固定修订版的源链接和扫描统计信息。 | `pattern` |
| `list_tuist_files` | 当相关路径未知时，发现源子系统或附近的测试。列表具有有限的深度和结果数量。 | 无 |
| `read_tuist_file` | 在找到相关路径后，检查实现文件、调用站点或测试中的特定行范围。截断的响应提供 `next_start_line` 以便继续。 | `path` |

#### 项目

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_accounts` | 列出经过身份验证的用户可用的个人和组织账户句柄，包括每个账户是否可以创建项目。 | 无 |
| `get_organization` | 获取组织的成员目录。待处理的邀请需要与仪表板相同的管理员权限；永远不会返回邀请接受令牌。 | `account_handle` |
| `create_organization` | 为经过身份验证的用户创建 Tuist 组织。 | `handle` |
| `create_project` | 在经过身份验证的用户可以访问的账户下创建 Tuist 项目。 | `account_handle`, `project_handle` |
| `add_organization_member` | 将现有的 Tuist 用户添加到组织或更新现有成员的角色。接受 `user`（默认）、`admin` 或 `viewer`，其中查看者可以读取仪表板和运行记录，但不能更改任何内容。 | `organization_handle`, `email` |
| `invite_organization_member` | 邀请电子邮件地址加入组织，无论该地址是否属于现有的 Tuist 用户。Tuist 会发送一封包含接受链接的电子邮件，该链接在 14 天后过期；当服务器无法发送电子邮件时，`email_sent` 为 `false`，必须从仪表板复制链接。接受 `user`（默认）、`admin` 或 `viewer`。需要组织管理员权限。 | `organization_handle`, `email` |
| `cancel_organization_invitation` | 取消待处理的组织邀请，使其链接不再可被接受。需要组织管理员权限。 | `organization_handle`, `email` |
| `list_projects` | 列出经过身份验证的用户可访问的所有项目。 | 无 |
| `get_project` | 获取项目的配置和连接的存储库 URL。 | `account_handle`, `project_handle` |
| `connect_project_repository` | 将项目链接到账户的 GitHub App 安装可以访问的 GitHub 存储库。项目采用存储库的默认分支。需要项目管理员权限。 | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | 移除项目与其 GitHub 存储库的链接。需要项目管理员权限。 | `account_handle`, `project_handle` |

#### 账户令牌

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_account_tokens` | 列出账户令牌元数据，不暴露令牌值。 | `account_handle` |
| `get_account_token` | 获取账户令牌元数据，不暴露其值。 | `account_handle`, `token_id` |
| `list_project_tokens` | 列出项目令牌元数据，不暴露令牌值。 | `account_handle`, `project_handle` |

#### AI 订阅

这些工具管理经过身份验证的用户自己的 Claude 和 ChatGPT 订阅，用于线程等 AI 功能。它们需要用户身份验证和对 AI 功能的访问权限，仅返回连接元数据，从不返回凭据。断开连接会删除保存的凭据，但不会撤销提供程序处的授权。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_ai_subscriptions` | 列出每个订阅是否已连接以及服务器是否可以连接它。 | 无 |
| `connect_claude_subscription` | 保存 `claude setup-token` 打印的订阅令牌。该令牌是一个机密，会通过客户端和模型传递，因此请显式提供；将其粘贴到仪表板的 AI 设置中可使其不出现在对话中。 | `token` |
| `start_chatgpt_subscription_login` | 启动 OpenAI 设备登录并返回用户在那里输入的验证 URL 和代码，以及一个 `login_id`。15 分钟后过期。 | 无 |
| `poll_chatgpt_subscription_login` | 检查待处理的登录：在用户批准代码之前为 `pending`，之后为 `connected`。 | `login_id` |
| `cancel_chatgpt_subscription_login` | 取消待处理的登录。已连接的订阅保持连接状态。 | `login_id` |
| `disconnect_ai_subscription` | 删除订阅的保存凭据和任何待处理的登录。 | `provider` |

#### 通知规则

这些工具管理经过身份验证的用户自己的通知规则：当规则的项目中发生事件（例如新预览）（或者在未列出任何项目时，为你可以收到通知的任何项目）并满足其条件时，执行其操作，例如向你的 Tuist 应用设备发送推送通知。没有规则你就收不到通知。它们需要用户身份验证，仅作用于你自己的规则，并且仅接受你所属账户的项目。它们不提供到仪表板页面，因为规则跨越你所有的账户。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_notification_events` | 列出规则可以订阅的事件类型，每个事件类型都带有其条件的 JSON Schema。 | 无 |
| `list_notification_condition_options` | 建议项目中事件的条件值，例如其最近预览的轨道和分支。 | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | 列出你的规则。 | 无 |
| `create_notification_rule` | 从事件、可选项目和条件以及至少一个操作创建规则。 | `event`, `actions` |
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
| `list_runner_profiles` | 列出账户的持续集成运行器配置，包括每个配置的 `runs-on` 标签。 | `account_handle` |
| `get_runner_catalog` | 列出运行器配置可以使用的机器规格和 Xcode 版本。 | `account_handle` |
| `create_runner_profile` | 创建包含平台、机器规格以及在 macOS 上的 Xcode 版本的运行器配置。可选设置哪些分支保存其缓存卷。需要账户管理员权限或 `account:runners:write` 作用域。 | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | 更改运行器配置的机器规格、Xcode 版本或哪些分支保存其自定义缓存卷变更。省略的字段保持其值不变。需要账户管理员权限或 `account:runners:write` 作用域。 | `account_handle`, `profile_name` |
| `delete_runner_profile` | 在用户确认后删除运行器配置。默认配置无法删除。需要账户管理员权限或 `account:runners:write` 作用域。 | `account_handle`, `profile_name` |

运行器卷工具公开与“卷”仪表板相同的数据。读取工具需要运行器访问权限；清除需要账户管理员权限或 `account:runners:write` 作用域，以及用户确认。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_runner_volumes` | 按名称和存储库过滤，对卷进行排序和分页。 | `account_handle` |
| `get_runner_volume` | 存储库、平台、容量、已用空间和最后使用时间。 | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | 分页的作业和工作流引用、缓存状态、命中结果和挂载时间。 | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | 由作业挂载的卷。 | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | 存储序列、作业运行次数、命中率和趋势。可选 `volume_id`、`start` 和 `end`（ISO 8601）；默认为七天，最多 90 天。 | `account_handle` |
| `delete_runner_volume` | 删除卷及其保存的内容。正在运行的作业保留其私有副本但无法保存；后续使用相同密钥的作业将从空状态开始。 | `account_handle`, `volume_id` |

列表接受 `page` 和 `page_size`（最多 100）。卷清单还接受 `name` 和 `repository`（精确匹配，以 AND 组合）、`sort_by`（`volume`、`repository`、`used_space`、`capacity`、`last_used`）和 `sort_order`（`asc`、`desc`）。未知的测量值和命中结果保持为 `null`。缓存状态描述卷变更是否已保存，而非作业成功与否。

#### 沙盒

沙盒工具公开与“沙盒”仪表板相同的数据和操作，并具有与 [API](https://tuist.dev/api/docs) 相同的访问权限：账户成员可以列出、获取、创建、暂停、恢复和删除沙盒，但服务于代理环境、Amp 或远程执行的沙盒，以及分析和归档工具，需要账户管理员权限。只读查看者无法使用它们。账户需要启用沙盒功能。仪表板的沙盒页面注册了只读工具。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_sandboxes` | 分页显示沙盒及其状态、规格和时间戳。可选 `search`（沙盒、Amp Orb 或 Anthropic 会话 ID 中的文本）、`status`、`vcpus`、`sort_by`（`created`、`last_active`、`identifier`）和 `sort_order`。 | `account_handle` |
| `get_sandbox` | 沙盒的状态、规格、节点、归档和时间戳。 | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU 小时数、创建的沙盒数量、会话、设置和启动耗时，以及相对于账户限制的峰值 vCPU、内存和磁盘使用情况，并附带趋势。可选 `start` 和 `end`（ISO 8601）；默认为 30 天，最多 90 天。 | `account_handle` |
| `create_sandbox` | 启动一个空白沙盒并在其运行后返回。可选 `platform`（`linux` 或 `darwin`）、`template`、带 `memory_mb` 的 `vcpus`（Linux：2x4096、4x8192 或 8x16384，默认 2x4096；macOS：8x8192、8x16384 或 8x24576，默认 8x8192）和 `workspace_gb`。 | `account_handle` |
| `pause_sandbox` | 将正在运行的沙盒快照保存到其节点的磁盘。 | `account_handle`, `sandbox_id` |
| `resume_sandbox` | 恢复已暂停或归档的沙盒。 | `account_handle`, `sandbox_id` |
| `archive_sandbox` | 排队将已暂停沙盒的磁盘移动到对象存储。 | `account_handle`, `sandbox_id` |
| `delete_sandbox` | 在用户确认后删除沙盒及其磁盘。 | `account_handle`, `sandbox_id` |

#### Amp 工作区

这些工具管理 <.localized_link href="/guides/server/authentication#amp-orbs">Amp 工作区连接</.localized_link>，允许 orbs 无需令牌即可登录 Tuist。它们使用与仪表板“集成”页面相同的仅管理员权限。orb 中的代理可以从 `$AMP_WORKSPACE_ID` 和 `$AMP_PROJECT_ID` 读取其自身的 ID。连接允许的每个 orb 都会获得对账户中所有项目的 CI 访问权限，因此代理应在连接前与用户确认。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_amp_workspace_connections` | 列出账户连接的 Amp 工作区以及每个工作区限制的项目（如果有）。 | `account_handle` |
| `connect_amp_workspace` | 连接 Amp 工作区。可选 `project_id` 将登录限制为一个 Amp 项目的 orbs。 | `account_handle`, `workspace_id` |
| `disconnect_amp_workspace` | 断开工作区连接。其 orbs 已有的会话在过期前保持有效。 | `account_handle`, `connection_id` |

#### Claude 环境

这些工具连接 Claude Managed Agents 自托管环境，使其会话在 Tuist 沙盒中运行，就像“设置”→“集成”→“Claude”那样。它们需要账户管理员权限并启用沙盒。代理可以使用 Anthropic 的 API 创建环境，但只有 Claude Console 会生成其环境密钥，因此代理会向用户索取该密钥。Tuist 使用 Anthropic API 密钥或工作负载身份联合启动会话，并在保存之前使用该凭据获取环境。Anthropic 端的设置使用用户自己的 Anthropic 凭据；Tuist 永远不会接收它们。密钥会通过客户端和模型传递，因此请仅显式提供它们。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_claude_environments` | 列出已连接的环境及其使用的凭据，以及联合规则应信任的颁发者 URL 和主题前缀。 | `account_handle` |
| `connect_claude_environment` | 使用 `api_key` 连接环境，或使用 `organization_id`、`workspace_id`、`service_account_id` 和 `federation_rule_id`。可选 `platform`、`vcpus` 和 `memory_mb` 用于设置沙盒规格。 | `account_handle`, `environment_id`, `environment_key` |

#### Webhooks

Webhook 工具使用与仪表板相同的仅管理员权限。交付尝试包含为端点记录的请求和响应数据，但绝不包含端点签名密钥。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_webhook_endpoints` | 列出账户的 Webhook 端点。 | `account_handle` |
| `get_webhook_endpoint` | 获取 Webhook 端点。 | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | 列出端点的交付尝试。 | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | 获取交付尝试。 | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode 构建

适用于 Xcode、Gradle、Bazel、Mix 和 Cargo 的构建详情工具公开现有的 `custom_metadata: {tags, values}` 结构，包括报告的基础设施观测数据。值保持为字符串，并保留不熟悉的键。例如，`tuist.cpu.available_processors` 描述运行时可用的逻辑处理器，而 `tuist.gradle.max_workers` 是 Gradle 工作线程限制，`tuist.jvm.max_heap_bytes` 是 JVM 堆限制，而非主机内存。这些是不可信的客户端观测数据，而非经过验证的运行器身份。缺失的观测数据保持缺失；导入的日志和较旧的客户端可能没有基础设施元数据。元数据格式待定，需等待协调一致的客户端/协议更新。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_xcode_builds` | 列出项目的 Xcode 构建运行。 | `account_handle`, `project_handle` |
| `get_xcode_build` | 获取特定 Xcode 构建运行的详细信息，包括保存原始 `.xcactivitylog` 的归档文件的临时下载 URL。 | `build_run_id` |
| `list_xcode_build_targets` | 列出特定 Xcode 构建运行的构建目标。 | `build_run_id` |
| `list_xcode_build_files` | 列出特定 Xcode 构建运行的编译文件。 | `build_run_id` |
| `list_xcode_build_steps` | 列出记录的构建步骤及其耗时和结果，不包含日志文本。 | `build_run_id` |
| `get_xcode_build_step` | 获取一个记录的构建步骤，包括其日志和截断标志。 | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | 列出特定构建运行的构建问题（警告和错误）。 | `build_run_id` |
| `list_xcode_build_cache_tasks` | 列出特定 Xcode 构建运行的可缓存任务（缓存命中/未命中）。 | `build_run_id` |
| `list_xcode_build_cas_outputs` | 列出特定 Xcode 构建运行的 [内容寻址存储](https://en.wikipedia.org/wiki/Content-addressable_storage) 输出。 | `build_run_id` |

`list_xcode_build_steps` 默认返回每页 20 个步骤（通过 `page_size` 最多 100 个），并提供 `page` 和 `pagination_metadata` 用于导航。使用 `search` 匹配标题、项目或目标，或过滤确切的 `project`、`target`、`category`（例如 `swiftCompilation`）和 `status`（`success` 或 `failure`）。按 `duration_ms` 排序以最慢的优先（默认），或按 `start_ms` 排序以按时间顺序排列。步骤 ID 用于打破平局，并作为十进制字符串返回以保留其完整的 64 位精度。ID 限定于单个构建，不应跨构建匹配。

可选 `start_ms` 和 `end_ms` 选择与从构建开始起以毫秒为单位的时间范围重叠的步骤；结束时间是独占的。这两个工具都接受构建 UUID 或仪表板 URL 作为 `build_run_id`。将返回的步骤 `id` 原样作为 `step_id` 传递以检索其日志。每个步骤的日志最多保留 64 KiB，`log_truncated` 指示省略的输出。

处理 Xcode 构建时默认会收集步骤。记录的步骤数据保留 90 天。列表响应包括 `availability`：当存在记录的步骤时为 `available`，即使过滤器不匹配任何内容；当构建仍在处理且尚无步骤时为 `processing`；或者当步骤未记录或已过期时为 `unavailable`。

HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` 和 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` 提供相同的操作，具有相同的过滤器和分页功能。两者都需要对构建所属项目的读取权限。

#### Gradle 构建

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | 返回完整的身份验证、项目设置、Gradle 插件、缓存策略和两次构建验证工作流。代理应在编辑现有的 Android 或 Gradle 项目之前调用它。 | 无 |
| `list_gradle_builds` | 列出项目的 Gradle 构建运行，包括自定义元数据。使用可选的 `tag` 参数按自定义标签进行过滤。 | `account_handle`, `project_handle` |
| `get_gradle_build` | 获取构建元数据、任务/缓存计数，以及 `failures`：每个失败任务和配置步骤的失败消息。 | `build_run_id` |
| `list_gradle_build_tasks` | 列出任务结果、复合构建标识、可缓存性、增量状态和失败消息。 | `build_run_id` |
| `list_gradle_build_steps` | 列出带计时的任务、配置和转换，支持搜索、元数据和重叠时间过滤器。 | `build_run_id` |
| `get_gradle_build_step` | 通过不透明 ID 检查记录的步骤元数据；失败任务或配置步骤的 `log` 即为其失败消息。 | `build_run_id`, `step_id` |

Gradle 和 Bazel 步骤列表默认返回 20 个结果（最多 100 个），支持 `search`、精确匹配 `project`、`target`、`category` 和 `status`、重叠的 `start_ms` / `end_ms` 过滤器（结束时间独占），以及按 `duration_ms` 或 `start_ms` 排序。原样传递返回的 ID；它们限定于各自的构建。列表公开 `time_origin` 和 `coverage`。较旧的 Gradle 报告使用 `first_recorded_timestamp`，因为未上传构建开始时间。Bazel 配置文件通过 `trace_profile` 覆盖范围和以 `profile_start` 为时间原点，公开所有记录的间隔。较旧的构建回退到保留的 BEP 摘要。源记录在 90 天后过期。Bazel 详情在发布时包含经过清理的操作日志。失败任务或配置步骤的 Gradle 详情包含 Tuist Gradle 插件作为 `log` 报告的失败消息：即 Gradle 控制台打印的异常消息及其原因链，不包含堆栈跟踪或任务输出，项目内的路径已转换为相对路径，凭据和其他本地路径已被脱敏，每个步骤最多 16 KiB，每次构建最多 32 个失败步骤。其他 Gradle 步骤、由较旧插件版本报告的构建以及无凭据报告的 `log` 为 null。配置步骤在失败时报告 `failure`，否则报告 `unknown`。`compare_builds` 提示利用此覆盖范围来区分完整的 Bazel 跟踪与保留的摘要，并指导代理在检查更广泛的调用输出之前，先查看步骤详情以获取操作结果和日志。

单步工具 `get_gradle_build_step` 和 `get_bazel_build_step` 通过 ID 检索步骤，不接受时间过滤器；请使用相应的列表工具按时间范围过滤步骤。

如果在列出步骤和获取步骤之间收到了完整的配置文件，则从保留摘要返回的 Bazel 步骤 ID 仍然可读。如果索引配置文件的步骤数据已过期，则报告为不可用。Gradle 步骤列表包括持续时间为零的缓存和跳过操作。

#### Bazel 调用

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | 返回身份验证、项目设置、Bazel 配置和验证工作流。 | 无 |
| `list_bazel_invocations` | 按最新优先顺序列出已完成的 [Bazel 构建事件协议](https://bazel.build/remote/bep) 调用，包括构建指标、有界的执行时间线、关键路径诊断以及项目的相关远程缓存总数。按 `status`、`git_branch`、`git_commit_sha`、`is_ci` 和 `command` 进行过滤。 | `account_handle`, `project_handle` |
| `get_bazel_invocation` | 获取一个已完成的 Bazel 调用，包括构建指标、有界的执行时间线、关键路径诊断以及相关的远程缓存总数。 | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | 列出记录的 Bazel 配置文件间隔，支持过滤器和明确的覆盖范围。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | 检查记录的 Bazel 步骤及其发布的操作结果和经过清理的日志。 | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | 按执行顺序列出为 Bazel 调用捕获的经过清理的日志：Bazel 进度输出的有界尾部以及 `test.log` 工件。可选的 `stream`（`stdout` 或 `stderr`）、`source`（`progress` 或 `test_log`）、`target_label` 和 `errors` 过滤器可缩小结果范围。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | 获取为 Bazel 调用捕获的一个经过清理的日志块。 | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | 列出原始的 Bazel 远程缓存观察记录，包括其操作、端点和观察时间，可选择限制为特定调用、结果或操作。 | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | 获取一条原始的 Bazel 远程缓存观察记录。 | `account_handle`, `project_handle`, `cache_event_id` |

`list_bazel_invocations` 过滤器为精确匹配，同一秒内完成的调用按调用 ID 排序。要查找分支上最新的失败调用，请使用 `status: "failure"`、`git_branch` 和 `page_size: 1` 进行调用。REST 端点 `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations` 接受相同的过滤器。

测试日志携带其来源测试结果的 `target_label` 和尝试 `status`，因此 `target_label: "//foo:bar_test"` 仅返回该目标的测试日志。`errors: true` 返回失败尝试的测试日志以及包含 Bazel 报告器以 `ERROR:`、`FAIL:` 或 `TIMEOUT:` 开头的行的 stderr 进度块。进度输出不归因于目标，且在记录归因之前写入的日志字段为空。失败的操作及其输出可通过 `list_bazel_build_steps` 按目标获取，每个测试用例的失败信息可通过测试运行工具获取。

#### Cargo 构建

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_cargo_builds` | 按最新优先顺序列出项目的 Cargo 构建。按 `git_branch`、`status`、`is_ci` 或 `command` 进行过滤。Cargo 测试执行结果可通过测试工具获取，而非此构建列表。 | `account_handle`, `project_handle` |
| `get_cargo_build` | 获取构建元数据、聚合缓存计数器，以及最多 500 个带有诊断信息的记录编译器作业。`compilations_truncated` 指示省略的作业；诊断信息仅涵盖返回的作业。 | `account_handle`, `project_handle`, `build_id` |

在 `get_cargo_build` 上设置 `include_cache_inspection: true` 以检索经过验证的任务决策和 CAS 操作，限制为 4 MB。默认情况下，以及当记录缺失或无效时，`cache_inspection` 为 null。请遵循其部分捕获的 `truncated` 标志；传输不会确定每个任务命中的本地/远程来源。HTTP 详细端点接受相同的查询参数。

#### Mix 构建

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_mix_builds` | 按最新优先顺序列出项目的 Mix (Elixir) 编译构建，包括自定义元数据。按 `git_branch`、`status`、`is_ci` 或 `mix_env` 进行过滤。 | `account_handle`, `project_handle` |
| `get_mix_build` | 获取构建元数据、诊断计数和依赖缓存摘要。 | `account_handle`, `project_handle`, `build_id` |

#### 构建跟踪

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `get_build_trace` | 获取 Xcode、Gradle、Bazel 或 Mix 构建时间线的下载链接，该文件为可在 [Perfetto](https://ui.perfetto.dev) 中打开的跟踪文件。 | `account_handle`, `project_handle`, `build_id` |

`build_id` 是构建运行 ID（Bazel 的调用 ID）或构建的仪表板 URL。返回的 `trace_url` 提供 [Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSON 文件。任何持有该链接的人都可以在 `expires_at`（调用后一小时）之前无需其他凭据即可下载该构建的跟踪文件。代理可以使用 `curl` 下载它，交给你在 Perfetto 中打开，或使用 Perfetto 的 `trace_processor` 进行查询。跟踪文件包含按并行性打包到通道中的记录步骤、跨越整个构建的轨道，以及在构建记录机器指标时的 CPU 和内存计数器。它包含与上述步骤工具相同的数据，但不含日志。仪表板从每个构建的“时间线”选项卡提供相同的文件。

#### Once 运行

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_once_runs` | 按最新优先顺序列出项目的 Once 运行。按 `kind`（`build`、`test` 或 `generic`）、`status`、`is_ci` 或 `git_branch` 进行过滤。尚未完成的运行状态为 `in_progress`。 | `account_handle`, `project_handle` |
| `get_once_run` | 获取运行及其操作总数、缓存摘要，对于测试运行还包括测试总数。 | `account_handle`, `project_handle`, `run_id` |

Cargo 构建、Mix 构建和 Once 运行 ID 在项目内是唯一的。通过 HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`、`.../mix/builds` 和 `.../once/runs` 可进行相同的读取操作，每个端点都支持针对单个 ID 的详细端点。

#### 任务、操作、模块和文件

这些项目范围的工具检查跨运行的持久构建身份。首先使用 `list_build_entities`，然后将返回的稳定 `id` 与相同的 `kind` 一起传递给 `get_build_entity` 或 `list_build_entity_history`，同时提供 `account_handle` 和 `project_handle`。不需要构建或调用标识符。

| 工具 | 描述 | 必需参数 |
| --- | --- | --- |
| `list_build_entities` | 列出在项目构建中看到的某一类任务、模块、操作或文件。 | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | 获取一个构建实体，包括其原生身份和所选时期的分析数据。 | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | 按最新优先顺序列出一个构建实体的记录执行、编译或缓存事件。 | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | 工具链 | 历史列表 |
| --- | --- | --- |
| `bazel_actions` | Bazel 操作 | BEP 报告的操作执行 |
| `gradle_tasks` | Gradle 任务 | 任务执行 |
| `xcode_modules` | Xcode 模块 | 编译和模块缓存事件 |
| `once_actions` | Once 操作 | 执行 |
| `mix_files` | Mix 编译文件 | 编译 |
| `mix_modules` | Mix 编译模块 | 编译 |
| `cargo_crates` | Cargo crate | 记录的 rustc 调用 |

这些工具正在逐步推出，仅返回已启用它们的项目的数据；对于其他项目，它们返回错误而非空结果。只有使用其构建工具链的项目才可用某种类型。工具接受有界的 `start_at`/`end_at` 过滤器、`environment`（`any`、`ci` 或 `local`）以及精确的 `branch`。`list_build_entities` 接受 `q`；`list_build_entity_history` 支持不透明的 `after`/`before` 游标。未知的时间或缓存观察结果保持不可用，而不是变为零或缺失。历史记录引用记录的父级和本机执行，以便使用现有运行工具进行深入分析。

`get_build_entity` 指标包括 `duration_samples`，即具有记录时间的观察次数：真正的零持续时间计入计数，缺失的时间不计入。此计数可能低于观察次数；不可用的持续时间统计信息保持为 null。

Xcode 模块持续时间来自构建日志中测量的目标编译。模块缓存解析和没有编译工作的目标不提供持续时间样本。编译观察引用 Xcode 构建；缓存事件引用生成或缓存命令。

Bazel 操作通过目标标签、助记符和配置的主要输出来识别，在不依赖输入相关缓存摘要的情况下保持单独的操作和配置 distinct。历史记录 BEP 报告的执行，而不是缓存查找或跟踪配置文件阶段。完整的执行覆盖需要 `--build_event_publish_all_actions`；工件交付是尽力而为，因此缺失的观察结果并不证明没有工作运行。较旧的没有稳定身份或执行开始的 Kura 负载仍被接受但未编入索引。缺失的结束时间测量保持不可用，真正的零持续时间计入计数。

Mix 模块持续时间测量包含文件的编译，而不是独立测量的模块工作。当客户端报告目标映射时，Once 操作使用声明的目标/能力/索引槽；仅诊断标签不是稳定身份。现有客户端和运行级工具保持不变地受支持。

Cargo crate 按确切记录的 crate 根、名称和类型分组。检出路径更改可能会分割历史记录，并且不区分构建配置文件、功能和目标三元组。历史记录测量 rustc 调用，而不是每个文件的工作或缓存命中；缺失的作业并不确定删除或完整的工作区清单。

分析读取具有有限的内存和执行时间。如果查询超过这些限制，工具将返回错误而不是虚构空结果。

新观察结果在部署后编入索引；此功能不会回填现有的运行遥测数据。在<.localized_link href="/guides/server/data-retention">数据保留政策</.localized_link>下，身份元数据的生命周期长于单个观察结果。

#### 测试

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_test_runs` | 列出项目的测试运行。`query` 字段包括 `git_branch`、`scheme` 和 `status`：`field:"value"` 进行精确匹配，`field~"value"` 进行不区分大小写的子字符串匹配，前导 `-` 对任一运算符取反。例如，`-git_branch~"gh-readonly-queue"` 排除合并队列分支。以空格分隔的查询过滤器和显式参数通过 AND 语义组合。 | `account_handle`, `project_handle` |
| `get_test_run` | 获取测试运行的详细指标，包括其结果包（`.xcresult`）和会话归档的临时下载 URL。 | `test_run_id` |
| `list_test_module_runs` | 列出特定测试运行的测试模块运行。 | `test_run_id` |
| `list_test_suite_runs` | 列出特定测试运行的测试套件运行，可按模块过滤。 | `test_run_id` |
| `list_test_cases` | 列出项目的测试用例（支持如 `flaky` 等过滤器）。 | `account_handle`, `project_handle` |
| `get_test_case` | 获取测试用例的详细指标，包括可靠性率、不稳定率和运行次数。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | 列出测试用例运行，可按测试用例或测试运行过滤。 | `account_handle`, `project_handle` |
| `get_test_case_run` | 获取特定测试用例运行的失败详情和重复次数。 | `test_case_run_id` |
| `list_test_case_run_attachments` | 列出测试用例运行的附件。每个附件都包含一个临时下载 URL。 | `test_case_run_id` |
| `list_test_case_events` | 列出测试用例的状态更改，例如将其静音或跳过。 | `test_case_id` |
| `update_test_case` | 更新测试用例的状态或不稳定分类。更改可以将事件分派到配置的 webhook 端点，包括外部服务。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | 列出测试运行的选择性测试目标结果。 | `test_run_id` |
| `get_coverage` | 获取项目在某个提交或分支的最新完整提交处的代码覆盖率及其目标。如果没有 `git_commit_sha` 或 `branch`，则读取默认分支。 | `account_handle`, `project_handle` |
| `list_coverage_files` | 列出在某个提交或分支的最新完整提交处由代码覆盖率测量的文件及其行覆盖率。支持 `search`、排序和分页。 | `account_handle`, `project_handle` |
| `get_coverage_file` | 获取文件在某个提交或分支的最新完整提交处的代码覆盖率及其函数。设置 `include_lines` 以获取每行的执行计数。 | `account_handle`, `project_handle`, `path` |

代码覆盖率工具适用于启用了代码覆盖率的账户。

#### Bundle

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_bundles` | 列出项目的 bundle（应用二进制文件）。可按 `git_branch` 和 `tags` 过滤（所有标签必须精确匹配）。 | `account_handle`, `project_handle` |
| `get_bundle` | 获取特定 bundle 的详细信息，包括自定义标签。 | `bundle_id` |
| `get_bundle_artifact_tree` | 以按路径排序的平面列表形式获取 bundle 的完整工件树。 | `bundle_id` |

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

使用无状态 `2026-07-28` Model Context Protocol 生命周期的客户端可以调用 `events/list` 来发现事件及其负载模式：

| 事件 | 发送时机 | 订阅过滤器 |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | 测试用例从非不稳定变为不稳定。 | `account_handle`, `project_handle` |
| `build.failed` | 本地或持续集成的 Xcode、Gradle 或 Bazel 构建以失败结束。 | `account_handle`, `project_handle` |
| `test_run.failed` | 本地或持续集成测试运行以失败结束，包括合并的分片运行或放弃的运行。 | `account_handle`, `project_handle` |
| `ci_job.failed` | Tuist 运行器作业以失败完成。 | `account_handle` |

要订阅，客户端需调用 `events/subscribe`，传入事件名称、上述 `arguments` 中列出的句柄，以及包含 `https://` 回调 URL 和 `whsec_` 签名密钥的 `webhook` 交付配置。项目事件需要账户成员身份以及对相应测试或构建数据的读取权限；运行器作业事件需要账户成员身份和运行器读取权限。已声明的 [`auth.md`](https://workos.com/auth-md) 访问令牌、已声明的账户令牌和浏览器授权授予可以创建订阅；当相关凭据不再有效时，交付将停止。每个用户最多可以保留 25 个活跃订阅。Tuist 在保存订阅之前会向回调发送验证质询。回调必须返回一个包含相同 `challenge` 值的对象。订阅默认持续七天，可以通过再次订阅来刷新，并在用户的访问权限或凭据被移除时停止交付。可选的 `ttlMs` 限制在一小时到 30 天之间。Tuist 会重试超时的回调，并在至少三次连续超时（跨越五分钟）后取消订阅；恢复回调后请重新订阅。

当事件发生时，Tuist 会将其资源标识符和仪表板 URL 发送到回调。构建和测试运行失败还包括 `is_ci` 和 `git_branch`，因此客户端可以忽略本地失败或按分支过滤。构建事件包括 `build_system`；运行器作业事件包括 `workflow_job_id` 和 `workflow_run_id`。请求包含订阅标识符和 [Standard Webhooks](https://www.standardwebhooks.com/) 签名标头，以便客户端验证其来源。Tuist 会重试失败的交付，因此客户端应使用稳定的 `eventId` 来丢弃重复项。负载省略了测试名称、日志和失败消息；客户端可以通过上述工具获取这些详细信息，并决定是否通知团队或开始调试。客户端可以使用 `events/unsubscribe` 停止交付。

### 提示

| 提示 | 描述 |
|--------|-------------|
| `fix_flaky_test` | 指导你通过分析失败模式、识别根本原因并应用针对性修正来修复不稳定测试。 |
| `compare_builds` | 指导你通过比较构建来识别性能回归、缓存更改和构建问题。对 Xcode、Gradle、Bazel 和 Cargo 项目使用原生工具。Cargo 比较保留部分编译器覆盖率，并区分估计的编译器工作与经过的时间节省。 |
| `compare_test_runs` | 指导你通过比较两次测试运行来识别回归、新失败和不稳定测试。 |
| `compare_bundles` | 指导你通过比较两个 bundle 来识别工件树中的大小变化。 |
| `compare_test_case` | 指导你通过比较测试用例在两个分支或时间段内的行为。 |
| `compare_generations` | 指导你通过比较两次生成运行来识别性能回归和模块缓存更改。 |
| `compare_cache_runs` | 指导你通过比较两次缓存运行来识别缓存有效性更改和目标级回归。 |
| `integrate_gradle_project` | 指导你将 Tuist 集成到现有的 Gradle 项目中。包括独立的工具和 Gradle 身份验证、账户发现、项目创建、远程缓存策略、构建洞察以及回读验证。 |
| `integrate_bazel_project` | 指导你创建或选择 Bazel 项目、对命令行进行身份验证、配置远程缓存和构建洞察，并通过 Tuist 构建数据验证集成。 |
| `integrate_xcode_project` | 指导你将 Tuist 集成到现有的 Xcode 项目中。支持 Xcode 缓存、构建洞察、测试洞察和测试分片。 |
| `ask_tuist` | 使用公开材料作为上下文，并以聚焦的实现和测试证据作为当前行为的事实来源来回答 Tuist 问题。它需要 `question` 并引用修订版本固定的证据。 |

项目数据提示接受 `account_handle` 和 `project_handle` 以将调查范围限定在特定项目。比较提示还接受 `base` 和 `head` 参数以指定要比较的两个项（通过 ID、仪表板 URL 或分支名称）。`ask_tuist` 接受 `question` 而不是项目参数。`integrate_gradle_project` 还接受 `features`，即要应用的 Gradle 集成的逗号分隔列表：`remote_cache`、`build_insights`、`test_insights`、`flaky_tests` 和 `test_sharding`。`integrate_bazel_project` 接受可选的 `server_url` 用于自托管或本地安装。`integrate_xcode_project` 接受带有 `xcode_cache`、`build_insights`、`test_insights` 和 `test_sharding` 的 `features`。

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
| `test_insights` | 配置 `tuist inspect test`、方案测试后操作以及用于持续集成测试运行的结果 bundle 生成。 |
| `test_sharding` | 添加带有 `TUIST_SHARD_INDEX` 的 Xcode 或生成项目的分片规划和分片执行工作流。 |

当省略 `features` 时，提示会要求代理澄清用户想要哪些集成，或在编辑 Xcode 项目之前从请求中推断出最小的有用集合。
