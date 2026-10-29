---
{
  "title": "模型上下文协议 (MCP)",
  "titleTemplate": ":title · 智能体编码 · 功能 · 指南 · Tuist",
  "description": "通过 Tuist 的 MCP 端点，让 AI 智能体能够访问测试洞察等信息。"
}
---
# 模型上下文协议

[模型上下文协议（MCP）](https://modelcontextprotocol.io/docs/getting-started/intro)是一项开放标准，允许人工智能代理与外部服务和数据源进行交互。它使 [Claude](https://claude.ai/)、[Claude Code](https://docs.anthropic.com/en/docs/claude-code)、[Codex](https://developers.openai.com/codex/) 等应用以及 [Zed](https://zed.dev)、[Cursor](https://www.cursor.com) 或 [Visual Studio Code](https://code.visualstudio.com) 等编辑器能够与 Tuist 互操作。

Tuist 在 `https://tuist.dev/mcp` 托管服务器端模型上下文协议端点。通过将客户端连接到该端点，代理可以访问你的 Tuist 项目数据，包括测试洞察、不稳定测试分析等。大多数工具为只读，且作用域限于已认证的 Tuist 项目数据。账户设置工具可以在已认证用户具备所需权限时列出账户、创建组织、创建项目，并将现有用户添加到组织中。每个工具都会公布注释，说明其是否为只读、是否可能导致难以撤销的更改，以及是否可以更改公共互联网状态。账户设置工具需要用户认证。它们不适用于项目令牌或普通账户令牌。当用户在浏览器中授权客户端或声明 `auth.md` 注册时，Tuist 仅在该模型上下文协议端点上将该凭据与用户关联，以便设置工具完成请求的工作流。

Tuist 实现了 [2026-07-28 协议](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)。请求是无状态的：客户端在每次请求中发送其协议元数据，并可以直接调用工具而无需初始化。`server/discover` 返回服务器的身份、能力、支持的版本和说明。不存在会话标识符或独立的事件流。使用 2025-06-18 或 2025-03-26 初始化流程的客户端仍然受支持；它们也无需服务器会话即可运行。

## 模型上下文协议与技能对比

模型上下文协议工具与<.localized_link href="/guides/features/agentic-coding/skills">技能</.localized_link>在功能上可能存在重叠。鉴于目前两者存在重叠，请为每个工作流选择一种方法并保持一致使用，而不是在同一流程中混合使用两者。

对于支持插件安装的客户端，请使用<.localized_link href="/guides/features/agentic-coding/plugins">Tuist 插件</.localized_link>来同时安装两者。

## 配置

将 `https://tuist.dev/mcp` 添加为客户端中的远程模型上下文协议服务器。服务器的初始化说明和公开服务器卡片以内联方式描述了带有动态客户端注册的 OAuth 2.0 以及标准浏览器授权流程，无需代理获取或遵循外部认证文档。这些服务器范围的说明保持了工作流指导的通用性：工具认证不会对本地命令行工具或构建系统集成进行认证，代理应通过相关的 Tuist 工具验证请求的更改。特定于构建系统的设置和认证检查记录在集成指南和提示中。Tuist 仍然分别在 `https://tuist.dev/auth.md` 发布 [开放授权](https://oauth.net/2/) 发现元数据和当前的 [auth.md 协议](https://workos.com/auth-md)。

该端点接受无状态的 `2026-07-28` 模型上下文协议请求生命周期（包括 `server/discover`），同时也支持较旧的基于会话的生命周期。现有客户端可以继续使用其当前的连接方法。

支持模型上下文协议事件的客户端可以订阅项目事件。有关可用事件和交付要求，请参阅[事件](#events)。

已经支持远程浏览器认证的客户端可以继续在浏览器中进行认证。支持 `auth.md` 的客户端和代理可以匿名注册、提供受信任的提供者身份断言，或启动服务认证的电子邮件声明。注册会返回一个由 Tuist 签名的身份断言，代理会在标准令牌端点将其交换为一小时有效的访问令牌。Tuist 发布其公钥签名密钥，并支持标准令牌撤销和提供者安全事件交付。

未经认证的代理应读取模型上下文协议端点返回的 `WWW-Authenticate` 标头，获取受保护资源元数据，获取授权服务器元数据，并遵循其 `agent_auth.skill` URL。Tuist 还在未授权响应正文中返回相同的本地 `auth_md` URL，以便由语言模型驱动的客户端能够在不依赖原生客户端集成的情况下发现该流程。部署本地文档是端点名称、请求体、声明轮询和断言交换的真实来源。

在代理启动电子邮件声明之前，必须要求用户确认其 Tuist 账户的电子邮件地址。不得从提供者配置文件、Git 配置、环境变量或会话元数据中推断该地址。

该端点使用 `mcp` 范围组。匿名的预声明凭据可以发现能力并阅读公开集成指南，但不会被视为已登录用户。在浏览器授权或声明之后，该凭据具有用户作用域，并且每个工具应用的授权检查与控制面板相同。详情请参阅<.localized_link href="/guides/server/authentication#scope-groups">范围组文档</.localized_link>。

工具解析到已认证用户已经可以读取的项目。Xcode 和 Gradle 构建工具接受构建 UUID 或控制面板 URL。UUID 必须唯一标识一个项目；如果它出现在多个项目中，工具将返回未找到，而不是选择另一个项目的报告。项目范围的控制面板和 API 读取仍然可用。报告的参与者标识符是未经验证的标签，而非凭据或额外的访问权限。

Tuist 运营人员调查客户账户时，会通过 Tuist 的内部运营工具进行，该工具会记录每次调用；直接连接到此端点获得的访问权限不会超出用户自身的成员资格范围。

<details>
<summary>Claude Code</summary>

运行：

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

当无头 Claude Code 客户端未向模型暴露失败的原生服务器连接时，要求代理在搜索托管文档或编辑项目之前，检查所配置端点的未经身份验证的 [超文本传输协议](https://developer.mozilla.org/en-US/docs/Web/HTTP) 响应。即使浏览器身份验证不可用，该响应也会将模型指向部署本地的 `auth.md` 文档。

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

出现提示时在浏览器中完成 [开放授权](https://oauth.net/2/)。

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

将 `auth` 设置为 `false` 可防止适配器的浏览器身份验证处理程序隐藏 Tuist 的未授权响应。无头代理随后可以读取返回的 `auth_md` URL，并遵循 Tuist 的注册、身份断言交换和声明轮询流程。将交换后的访问令牌配置为承载令牌，或让代理直接进行经过身份验证的模型上下文协议调用。

如果你更喜欢浏览器身份验证，请将 `auth` 设置为 `"oauth"`。对于该流程，在身份验证完成期间，使用 Pi 的 [远程过程调用模式](https://pi.dev/docs/latest/rpc) 保持一个进程存活：

```bash
pi --mode rpc
```

不要将挂起的浏览器身份验证拆分到单独的 `pi --print` 调用中，因为拥有回调状态的进程已退出。

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

使用 **Command Palette → MCP: Add Server**，然后配置具有以下设置的 [超文本传输协议](https://developer.mozilla.org/en-US/docs/Web/HTTP) 服务器：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

打开 **Agent panel → Settings → Add Custom Server**，然后设置：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

如果你的代理支持 `auth.md`，它可以匿名启动而无需打开浏览器。当提供者身份已链接时，受信任的提供者身份也可以在不打开浏览器的情况下完成。对于服务身份验证的电子邮件、匿名声明或首次提供者链接，代理会向你显示 Tuist 验证链接和六位代码。打开链接，登录，然后在 Tuist 页面上输入代理的代码。切勿将代码发送回代理。Tuist 的授权服务器元数据直接指向部署自己的 `/auth.md`，其中包含确切的请求和轮询结构。

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


## 能力

### 工具

以下工具可通过 Tuist 模型上下文协议服务器使用：

每个工具都发布人类可读的描述以及明确的输入和输出架构。成功的调用返回符合 advertised 输出架构的结构化内容，以及为尚未消费结构化内容的客户端序列化为文本的相同结果。

接受单个记录标识符（如 `build_run_id`、`test_run_id`、`test_case_id`、`bundle_id`、`run_id`、`generation_id` 或 `cache_run_id`）的工具也接受该记录的 Tuist 控制面板 URL。直接从浏览器粘贴 URL，而不是从中提取标识符。

#### 文档与社区搜索

此只读工具通过驱动文档网站的同一搜索引擎，搜索 Tuist 的文档、[应用程序编程接口](https://en.wikipedia.org/wiki/API)参考、GitHub 发布、社区论坛和 GitHub 问题。发布结果包括产品、版本、发布日期和预发布状态。默认情况下搜索稳定版本，可以使用 `include_prereleases` 包含预发布版本。该工具仅在托管于 `https://tuist.dev/mcp` 的 Tuist 服务器上可用。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `search_tuist` | 搜索公开的 Tuist 文档、应用程序编程接口参考、GitHub 发布、社区讨论和 GitHub 问题。可选择限制为一个 `source`（`docs`、`api_reference`、`releases`、`forum`、`issues`）。 | `query` |

#### 基于源码的回答

这些只读工具允许代理使用与托管服务器一起部署的确切公共 Tuist 源代码修订版作为事实来源，以回答依赖于当前行为的问题。它们仅在 `https://tuist.dev/mcp` 上可用。

兼容的客户端在初始化期间会收到关于工具源代码修订版、链接和结果限制的事实性描述，以及内联 OAuth 身份验证信息。这些描述不规定回答风格或验证工作流程。用户可以直接提问，而无需先调用 `ask_tuist` 提示；该提示仍可用于显式的基于源码的工作流程。

每个操作都有固定的并发、持续时间、遍历、读取字节数和响应大小限制。搜索和列表结果包括 `truncated` 和 `truncation_reason` 字段。当结果被截断时，请缩小路径、文件模式或搜索词的范围，而不是将结果视为详尽无遗。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `search_tuist_code` | 通过搜索源文件来回答有关当前行为、默认值、配置、功能开关、错误处理或未记录细节的问题。结果包括周围的行、固定到修订版的源链接以及扫描统计信息。 | `pattern` |
| `list_tuist_files` | 在相关路径未知时，发现源子系统或附近的测试。列表具有有限的深度和结果数量。 | 无 |
| `read_tuist_file` | 在找到相关路径后，检查实现文件、调用站点或测试中的特定行范围。截断的响应提供 `next_start_line` 以便继续。 | `path` |

#### 项目

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_accounts` | 列出经过身份验证的用户可用的个人和组织账户句柄，包括每个账户是否可以创建项目。 | 无 |
| `get_organization` | 获取组织的成员目录。待处理的邀请需要与控制面板相同的管理员权限；邀请接受令牌永远不会返回。 | `account_handle` |
| `create_organization` | 为经过身份验证的用户创建 Tuist 组织。 | `handle` |
| `create_project` | 在经过身份验证的用户可以访问的账户下创建 Tuist 项目。 | `account_handle`, `project_handle` |
| `add_organization_member` | 将现有的 Tuist 用户添加到组织或更新现有成员的角色。接受 `user`（默认）、`admin` 或 `viewer`，其中查看者可以读取控制面板和运行记录，但不能更改任何内容。 | `organization_handle`, `email` |
| `invite_organization_member` | 邀请电子邮件地址加入组织，无论该地址是否属于现有的 Tuist 用户。Tuist 会发送一封包含接受链接的电子邮件，该链接在 14 天后过期；当服务器无法发送电子邮件时，`email_sent` 为 `false`，必须从控制面板复制链接。接受 `user`（默认）、`admin` 或 `viewer`。需要组织管理员权限。 | `organization_handle`, `email` |
| `cancel_organization_invitation` | 取消待处理的组织邀请，使其链接不再可被接受。需要组织管理员权限。 | `organization_handle`, `email` |
| `list_projects` | 列出经过身份验证的用户可访问的所有项目。 | 无 |
| `get_project` | 获取项目的配置和连接的仓库 URL。 | `account_handle`, `project_handle` |
| `connect_project_repository` | 将项目链接到账户的 GitHub App 安装可以访问的 GitHub 仓库。项目采用仓库的默认分支。需要项目管理员权限。 | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | 移除项目与其 GitHub 仓库的链接。需要项目管理员权限。 | `account_handle`, `project_handle` |

#### 账户令牌

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_account_tokens` | 列出账户令牌元数据，而不暴露令牌值。 | `account_handle` |
| `get_account_token` | 获取账户令牌元数据，而不暴露其值。 | `account_handle`, `token_id` |
| `list_project_tokens` | 列出项目令牌元数据，而不暴露令牌值。 | `account_handle`, `project_handle` |

#### 持续集成运行器

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_runner_jobs` | 列出账户的持续集成运行器作业。 | `account_handle` |
| `get_runner_job` | 获取一个持续集成运行器作业。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | 列出为持续集成运行器作业记录的步骤。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | 列出为持续集成运行器作业记录的机器指标。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | 列出持续集成运行器作业捕获的最多 500 行日志。 | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | 列出账户的持续集成工作流汇总。 | `account_handle` |
| `list_runner_profiles` | 列出账户的持续集成运行器配置文件，以及每个配置文件的 `runs-on` 标签。 | `account_handle` |
| `get_runner_catalog` | 列出运行器配置文件可用的机器规格和 Xcode 版本。 | `account_handle` |
| `create_runner_profile` | 创建具有平台、机器规格以及在 macOS 上的 Xcode 版本的运行器配置文件。可选择设置哪些分支保存其缓存卷。需要账户管理权限或 `account:runners:write` 作用域。 | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | 更改运行器配置文件的机器规格、Xcode 版本或哪些分支保存其自定义缓存卷更改。省略的字段保留其值。需要账户管理权限或 `account:runners:write` 作用域。 | `account_handle`, `profile_name` |
| `delete_runner_profile` | 在用户确认后删除运行器配置文件。默认配置文件无法删除。需要账户管理权限或 `account:runners:write` 作用域。 | `account_handle`, `profile_name` |

运行器卷工具公开与卷控制面板相同的数据。读取工具需要运行器访问权限；清除需要账户管理权限或 `account:runners:write` 作用域，以及用户确认。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_runner_volumes` | 按名称和仓库筛选，对卷进行排序和分页。 | `account_handle` |
| `get_runner_volume` | 仓库、平台、容量、已用空间和最后使用时间。 | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | 分页的作业和工作流引用、缓存状态、命中结果和挂载时间。 | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | 由作业挂载的卷。 | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | 存储序列、作业运行、命中率和趋势。可选 `volume_id`、`start` 和 `end`（ISO 8601）；默认为七天，最多 90 天。 | `account_handle` |
| `clear_runner_volume` | 清除保存的内容。正在运行的作业保留其私有副本但无法保存；后续作业从空状态开始。 | `account_handle`, `volume_id` |

列表接受 `page` 和 `page_size`（最多 100）。卷清单还接受 `name` 和 `repository`（精确匹配，使用 AND 组合）、`sort_by`（`volume`、`repository`、`used_space`、`capacity`、`last_used`）和 `sort_order`（`asc`、`desc`）。未知的测量值和命中结果保持为 `null`。缓存状态描述是否保存了卷更改，而非作业成功与否。

#### Webhook

Webhook 工具使用与控制面板相同的仅管理员权限。交付尝试包含为端点记录的请求和响应数据，但不包含端点签名密钥。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_webhook_endpoints` | 列出账户的 Webhook 端点。 | `account_handle` |
| `get_webhook_endpoint` | 获取一个 Webhook 端点。 | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | 列出端点的交付尝试。 | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | 获取一次交付尝试。 | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode 构建

用于 Xcode、Gradle、Bazel、Mix 和 Cargo 的构建详情工具公开现有的 `custom_metadata: {tags, values}` 结构，包括报告的基础设施观测数据。值保持为字符串，并保留不熟悉的键。例如，`tuist.cpu.available_processors` 描述运行时可用的逻辑处理器，而 `tuist.gradle.max_workers` 是 Gradle 工作线程限制，`tuist.jvm.max_heap_bytes` 是 JVM 堆限制，而非主机内存。这些是不可信的客户端观测数据，而非经过验证的运行器身份。缺失的观测数据保持缺失；导入的日志和较旧的客户端可能没有基础设施元数据。一旦元数据等待协调的客户端/协议更新。

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_xcode_builds` | 列出项目的 Xcode 构建运行。 | `account_handle`, `project_handle` |
| `get_xcode_build` | 获取特定 Xcode 构建运行的详细信息，包括包含原始 `.xcactivitylog` 的归档文件的临时下载 URL。 | `build_run_id` |
| `list_xcode_build_targets` | 列出特定 Xcode 构建运行的构建目标。 | `build_run_id` |
| `list_xcode_build_files` | 列出特定 Xcode 构建运行的已编译文件。 | `build_run_id` |
| `list_xcode_build_steps` | 列出记录的构建步骤，包含耗时和结果，但不包含日志文本。 | `build_run_id` |
| `get_xcode_build_step` | 获取一个记录的构建步骤，包括其日志和截断标志。 | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | 列出特定构建运行的构建问题（警告和错误）。 | `build_run_id` |
| `list_xcode_build_cache_tasks` | 列出特定 Xcode 构建运行的可缓存任务（缓存命中/未命中）。 | `build_run_id` |
| `list_xcode_build_cas_outputs` | 列出特定 Xcode 构建运行的 [内容寻址存储](https://en.wikipedia.org/wiki/Content-addressable_storage) 输出。 | `build_run_id` |

`list_xcode_build_steps` 默认返回每页 20 个步骤（通过 `page_size` 最多 100 个），并提供 `page` 和 `pagination_metadata` 用于导航。使用 `search` 匹配标题、项目或目标，或筛选确切的 `project`、`target`、`category`（例如 `swiftCompilation`）和 `status`（`success` 或 `failure`）。按 `duration_ms` 排序以首先显示最慢的步骤（默认），或按 `start_ms` 排序以显示时间顺序。步骤 ID 用于打破平局，并作为十进制字符串返回以保留其完整的 64 位精度。ID 的作用域限于单个构建，不应跨构建匹配。

可选的 `start_ms` 和 `end_ms` 选择与从构建开始起以毫秒为单位的时间范围重叠的步骤；结束时间是独占的。这两个工具都接受构建 UUID 或控制面板 URL 作为 `build_run_id`。将返回的步骤 `id` 原样作为 `step_id` 传递以检索其日志。每个步骤的日志最多保留 64 KiB，`log_truncated` 指示省略的输出。

处理 Xcode 构建时默认会收集步骤。记录的步骤数据保留 90 天。列表响应包括 `availability`：当存在记录的步骤时为 `available`，即使过滤器不匹配任何内容；当构建仍在处理且尚无步骤时为 `processing`；或者当步骤未记录或已过期时为 `unavailable`。

HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` 和 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` 提供相同的操作，具有相同的过滤器和分页。两者都需要对构建所属项目的读取权限。

#### Gradle 构建

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | 返回完整的身份验证、项目设置、Gradle 插件、缓存策略和两次构建验证工作流。代理在编辑现有的 Android 或 Gradle 项目之前应调用此接口。 | 无 |
| `list_gradle_builds` | 列出项目的 Gradle 构建运行，包括自定义元数据。使用可选的 `tag` 参数按自定义标签进行过滤。 | `account_handle`, `project_handle` |
| `get_gradle_build` | 获取构建元数据和任务/缓存计数。 | `build_run_id` |
| `list_gradle_build_tasks` | 列出任务结果、复合构建身份、可缓存性和增量状态。 | `build_run_id` |
| `list_gradle_build_steps` | 列出定时任务、配置和转换，支持搜索、元数据和重叠时间过滤器。 | `build_run_id` |
| `get_gradle_build_step` | 通过不透明 ID 检查记录的步骤元数据；不提供每个步骤的日志。 | `build_run_id`, `step_id` |

Gradle 和 Bazel 步骤列表默认返回 20 个结果（最多 100 个），支持 `search`、确切的 `project`、`target`、`category` 和 `status`、重叠的 `start_ms` / `end_ms` 过滤器（结束时间独占），以及 `duration_ms` 或 `start_ms` 排序。原样传递返回的 ID；它们的作用域限于其构建。列表公开 `time_origin` 和 `coverage`。较旧的 Gradle 报告使用 `first_recorded_timestamp`，因为未上传构建开始时间。Bazel 配置文件公开所有记录的间隔，覆盖范围为 `trace_profile`，时间原点为 `profile_start`。较旧的构建回退到保留的 BEP 摘要。源记录在 90 天后过期。Bazel 详情在发布时包含经过清理的操作日志；Gradle 详情 `log` 为空。`compare_builds` 提示使用此覆盖范围来区分完整的 Bazel 跟踪和保留的摘要，并在检查更广泛的调用输出之前，引导代理查看步骤详情以获取操作结果和日志。

如果在列出步骤和获取步骤之间到达完整的配置文件，则从保留的摘要返回的 Bazel 步骤 ID 仍然可读。步骤数据已过期的索引配置文件报告为不可用。Gradle 步骤列表包括持续时间为零的缓存和跳过操作。

#### Bazel 调用

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | 返回身份验证、项目设置、Bazel 配置和验证工作流。 | 无 |
| `list_bazel_invocations` | 列出已完成的 [Bazel 构建事件协议](https://bazel.build/remote/bep) 调用，包含构建指标、有界执行时间线、关键路径诊断以及项目的相关远程缓存总数。 | `account_handle`, `project_handle` |
| `get_bazel_invocation` | 获取一个已完成的 Bazel 调用，包含构建指标、有界执行时间线、关键路径诊断以及相关的远程缓存总数。 | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | 列出记录的 Bazel 配置文件间隔，包含过滤器和明确的覆盖范围。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | 检查记录的 Bazel 步骤及其发布的操作结果和经过清理的日志。 | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | 按执行顺序列出为 Bazel 调用捕获的经过清理的测试日志。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | 获取为 Bazel 调用捕获的一个经过清理的测试日志。 | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | 列出原始的 Bazel 远程缓存观测数据，包括其操作、端点和观测时间，可选择缩小到特定调用、结果或操作。 | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | 获取一个原始的 Bazel 远程缓存观测数据。 | `account_handle`, `project_handle`, `cache_event_id` |

#### Cargo 构建

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_cargo_builds` | 列出项目的 Cargo 构建，按最新顺序排列。可按 `git_branch`、`status`、`is_ci` 或 `command` 过滤。单独的测试运行可通过测试工具获取，不在此构建列表中提供。 | `account_handle`, `project_handle` |
| `get_cargo_build` | 获取构建元数据和聚合缓存计数，包括命中次数、任务未命中次数和命中率。 | `account_handle`, `project_handle`, `build_id` |

#### Mix 构建

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_mix_builds` | 列出项目的 Mix（Elixir）编译构建，按最新顺序排列，包含自定义元数据。可按 `git_branch`、`status`、`is_ci` 或 `mix_env` 过滤。 | `account_handle`, `project_handle` |
| `get_mix_build` | 获取构建元数据、诊断计数和依赖缓存摘要。 | `account_handle`, `project_handle`, `build_id` |

#### Once 运行

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_once_runs` | 列出项目的 Once 运行，按最新顺序排列。可按 `kind`（`build`、`test` 或 `generic`）、`status`、`is_ci` 或 `git_branch` 过滤。尚未完成的运行状态为 `in_progress`。 | `account_handle`, `project_handle` |
| `get_once_run` | 获取一次运行，包含其操作总数、缓存摘要，对于测试运行还包括测试总数。 | `account_handle`, `project_handle`, `run_id` |

Cargo 构建、Mix 构建和 Once 运行的 ID 在项目内是唯一的。通过 HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`、`.../mix/builds` 和 `.../once/runs` 提供相同的读取功能，每个端点都支持通过 ID 获取详细信息。

#### 任务、操作、模块和文件

这些项目范围的工具检查跨运行的持久构建身份。首先使用 `list_build_entities`，然后将返回的稳定 `id` 与相同的 `kind` 一起传递给 `get_build_entity` 或 `list_build_entity_history`，同时提供 `account_handle` 和 `project_handle`。不需要构建或调用标识符。

| 工具 | 描述 | 必需参数 |
| --- | --- | --- |
| `list_build_entities` | 列出在项目构建中看到的某一类任务、模块、操作或文件。 | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | 获取一个构建实体，包含其原生身份和所选周期的分析数据。 | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | 列出一个构建实体的记录执行、编译或缓存事件，按最新顺序排列。 | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | 工具链 | 历史列表 |
| --- | --- | --- |
| `bazel_actions` | Bazel 操作 | BEP 报告的操作执行 |
| `gradle_tasks` | Gradle 任务 | 任务执行 |
| `xcode_modules` | Xcode 模块 | 编译和模块缓存事件 |
| `once_actions` | Once 操作 | 执行 |
| `mix_files` | Mix 编译文件 | 编译 |
| `mix_modules` | Mix 编译模块 | 编译 |

这些工具正在逐步推出，仅返回已启用它们的项目的数据；对于其他项目，它们会返回错误而不是空结果。只有使用其构建工具链的项目才支持某种类型。这些工具接受有界的 `start_at`/`end_at` 过滤器、`environment`（`any`、`ci` 或 `local`）以及精确的 `branch`。`list_build_entities` 接受 `q`；`list_build_entity_history` 支持不透明的 `after`/`before` 游标。未知的时间或缓存观测数据保持不可用，而不是变为零或未命中。历史记录引用记录的父级和原生执行，以便使用现有的运行工具进行下钻分析。

`get_build_entity` 指标包括 `duration_samples`，即具有记录时间的观测数量：真实的零持续时间计入计数，缺少时间不计入。此计数可能低于观测计数；不可用的持续时间统计信息保持为 null。

Xcode 模块的持续时间来自构建日志中测量的目标编译。模块缓存解析和没有编译工作的目标不提供持续时间样本。编译观测引用 Xcode 构建；缓存事件引用生成或缓存命令。

Bazel 操作通过目标标签、助记符和配置的主要输出来识别，在不依赖输入相关缓存摘要的情况下保持单独的操作和配置 distinct。历史记录 BEP 报告的执行，而不是缓存查找或跟踪配置文件阶段。完整的执行覆盖需要 `--build_event_publish_all_actions`；工件交付是尽力而为，因此缺失的观测并不是没有工作运行的证据。较旧的没有稳定身份或执行开始的 Kura 负载仍然被接受但未索引。缺少结束时间测量保持不可用，真实的零持续时间计入计数。

Mix 模块的持续时间测量包含文件的编译，而不是独立测量的模块工作。当客户端报告目标映射时，Once 操作使用声明的目标/能力/索引槽位；仅诊断标签不是稳定的身份。现有客户端和运行级别工具保持不变地得到支持。

分析读取具有有限的内存和执行时间。如果查询超过这些限制，工具将返回错误而不是虚构一个空结果。

新的观测在部署后被索引；此功能不会回填现有的运行遥测数据。在 <.localized_link href="/guides/server/data-retention">数据保留策略</.localized_link> 下，身份元数据的寿命长于单个观测。

#### 测试

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_test_runs` | 列出项目的测试运行。`query` 字段为 `git_branch`、`scheme` 和 `status`：`field:"value"` 精确匹配，`field~"value"` 匹配不区分大小写的子字符串，前导 `-` 否定任一运算符。例如，`-git_branch~"gh-readonly-queue"` 排除合并队列分支。空格分隔的查询过滤器和显式参数以 AND 语义组合。 | `account_handle`, `project_handle` |
| `get_test_run` | 获取测试运行的详细指标，包括其结果包（`.xcresult`）和会话档案的临时下载 URL。 | `test_run_id` |
| `list_test_module_runs` | 列出特定测试运行的测试模块运行。 | `test_run_id` |
| `list_test_suite_runs` | 列出特定测试运行的测试套件运行，可选按模块过滤。 | `test_run_id` |
| `list_test_cases` | 列出项目的测试用例（支持如 `flaky` 等过滤器）。 | `account_handle`, `project_handle` |
| `get_test_case` | 获取测试用例的详细指标，包括可靠性率、不稳定率和运行次数。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | 列出测试用例运行，可选按测试用例或测试运行过滤。 | `account_handle`, `project_handle` |
| `get_test_case_run` | 获取特定测试用例运行的失败详情和重复次数。 | `test_case_run_id` |
| `list_test_case_run_attachments` | 列出测试用例运行的附件。每个附件都包含一个临时下载 URL。 | `test_case_run_id` |
| `list_test_case_events` | 列出测试用例的状态更改，例如将其静音或跳过。 | `test_case_id` |
| `update_test_case` | 更新测试用例的状态或不稳定分类。更改可以将事件分派到配置的 webhook 端点，包括外部服务。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | 列出测试运行的选择性测试目标结果。 | `test_run_id` |
| `get_coverage` | 获取项目的代码覆盖率及其目标，在某个提交或分支的最新完整提交处。如果没有 `git_commit_sha` 或 `branch`，则读取默认分支。 | `account_handle`, `project_handle` |
| `list_coverage_files` | 列出某个提交的代码覆盖率测量的文件及其行覆盖率，在某个提交或分支的最新完整提交处。支持 `search`、排序和分页。 | `account_handle`, `project_handle` |
| `get_coverage_file` | 获取文件的代码覆盖率及其函数，在某个提交或分支的最新完整提交处。设置 `include_lines` 以获取每行的执行计数。 | `account_handle`, `project_handle`, `path` |

代码覆盖率工具适用于启用了代码覆盖率的账户。

#### Bundle

| 工具 | 描述 | 必需参数 |
|------|-------------|---------------------|
| `list_bundles` | 列出项目的 bundle（应用二进制文件）。 | `account_handle`, `project_handle` |
| `get_bundle` | 获取特定 bundle 的详细信息。 | `bundle_id` |
| `get_bundle_artifact_tree` | 获取 bundle 的完整工件树，作为按路径排序的平面列表。 | `bundle_id` |

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
| `test_case.marked_flaky` | 测试用例从稳定变为不稳定。 | `account_handle`, `project_handle` |
| `build.failed` | 本地或持续集成的 Xcode、Gradle 或 Bazel 构建以失败结束。 | `account_handle`, `project_handle` |
| `test_run.failed` | 本地或持续集成测试运行以失败结束，包括合并的分片运行或放弃的运行。 | `account_handle`, `project_handle` |
| `ci_job.failed` | Tuist 运行器作业以失败完成。 | `account_handle` |

要订阅，客户端使用事件名称、上述 `arguments` 中列出的句柄以及包含 `https://` 回调 URL 和 `whsec_` 签名密钥的 `webhook` 交付来调用 `events/subscribe`。项目事件需要账户成员身份以及对相应测试或构建数据的读取权限；运行器作业事件需要账户成员身份和运行器读取权限。已声明的 [`auth.md`](https://workos.com/auth-md) 访问令牌、已声明的账户令牌和浏览器授权授予可以创建订阅；当相关凭据不再有效时，交付停止。每个用户最多可以保留 25 个活跃订阅。Tuist 在保存订阅之前向回调发送验证质询。回调必须返回包含相同 `challenge` 值的对象。订阅默认持续七天，可以通过再次订阅来刷新，并在用户的访问权限或凭据被移除时停止交付。可选的 `ttlMs` 限制在一小时到 30 天之间。Tuist 会重试超时的回调，并在至少三次连续超时（跨越五分钟）后取消订阅；恢复回调后请重新订阅。

当事件发生时，Tuist 将其资源标识符和仪表板 URL 发送到回调。构建和测试运行失败还包括 `is_ci` 和 `git_branch`，因此客户端可以忽略本地失败或按分支过滤。构建事件包括 `build_system`；运行器作业事件包括 `workflow_job_id` 和 `workflow_run_id`。请求包含订阅标识符和 [Standard Webhooks](https://www.standardwebhooks.com/) 签名标头，以便客户端验证其来源。Tuist 会重试失败的交付，因此客户端应使用稳定的 `eventId` 来丢弃重复项。负载省略了测试名称、日志和失败消息；客户端可以通过上述工具获取这些详细信息，并决定是否通知团队或开始调试。客户端可以使用 `events/unsubscribe` 停止交付。

### 提示

| 提示 | 描述 |
|--------|-------------|
| `fix_flaky_test` | 通过分析失败模式、识别根本原因并应用针对性修复，指导你解决不稳定测试。 |
| `compare_builds` | 指导你对比两次构建运行，以识别性能回归、缓存变化和构建问题。适用于 Xcode 和 Gradle 项目。 |
| `compare_test_runs` | 指导你对比两次测试运行，以识别回归、新出现的失败和不稳定测试。 |
| `compare_bundles` | 指导你对比两个制品包，以识别整个制品树中的大小变化。 |
| `compare_test_case` | 指导你对比测试用例在两个分支或时间段内的行为。 |
| `compare_generations` | 指导你对比两次生成运行，以识别性能回归和模块缓存变化。 |
| `compare_cache_runs` | 指导你对比两次缓存运行，以识别缓存有效性变化和目标级回归。 |
| `integrate_gradle_project` | 指导你将 Tuist 集成到现有的 Gradle 项目中。包括独立的工具和 Gradle 身份验证、账户发现、项目创建、远程缓存策略、构建洞察以及回读验证。 |
| `integrate_bazel_project` | 指导你创建或选择 Bazel 项目、对命令行进行身份验证、配置远程缓存和构建洞察，并通过 Tuist 构建数据验证集成。 |
| `integrate_xcode_project` | 指导你将 Tuist 集成到现有的 Xcode 项目中。支持 Xcode 缓存、构建洞察、测试洞察和测试分片。 |
| `ask_tuist` | 使用公开材料作为上下文，并以聚焦的实现和测试证据作为当前行为的真实来源，回答 Tuist 相关问题。它需要 `question` 并引用修订版固定的证据。 |

项目数据提示接受 `account_handle` 和 `project_handle`，以便将调查范围限定在特定项目。比较提示还接受 `base` 和 `head` 参数，以指定要比较的两个项目（通过 ID、仪表板 URL 或分支名称）。`ask_tuist` 接受 `question` 而非项目参数。`integrate_gradle_project` 还接受 `features`，这是一个逗号分隔的 Gradle 集成列表：`remote_cache`、`build_insights`、`test_insights`、`flaky_tests` 和 `test_sharding`。`integrate_bazel_project` 接受可选的 `server_url`，用于自托管或本地安装。`integrate_xcode_project` 接受包含 `xcode_cache`、`build_insights`、`test_insights` 和 `test_sharding` 的 `features`。

#### Gradle 集成提示功能

`integrate_gradle_project` 提示和 `get_gradle_integration_guide` 工具记录了完整的设置工作流。服务器的初始化说明中也引用了该工具，这使得不枚举提示的代理也能发现它。

| 功能 | 代理配置的内容 |
|---------|---------------------------|
| `remote_cache` | 启用 Gradle 的构建缓存，配置 Tuist 远程缓存上传策略，并建议仅从具有本地只读使用权的持续集成运行器进行上传。 |
| `build_insights` | 应用 Tuist Gradle 插件，并在需要时配置构建分析上传行为。 |
| `test_insights` | 应用 Tuist Gradle 插件，以便自动上传 Gradle `Test` 任务结果。 |
| `flaky_tests` | 指导设置不稳定测试检测、可选的 Gradle Test Retry 插件用法以及测试隔离配置。 |
| `test_sharding` | 添加用于 `tuistPrepareTestShards` 的持续集成工作流、分片矩阵生成以及基于 `TUIST_SHARD_INDEX` 的测试执行。 |

当省略 `features` 时，提示会要求代理澄清用户想要哪些集成，或在编辑 Gradle 项目之前从请求中推断出最小的有用集合。

#### Xcode 集成提示功能

`integrate_xcode_project` 提示记录了 Tuist 支持的每项 Xcode 集成：

| 功能 | 代理配置的内容 |
|---------|---------------------------|
| `xcode_cache` | 配置 `tuist setup cache`、生成项目缓存设置、手动 Xcode 缓存构建设置，以及仅限于持续集成运行器的上传策略。 |
| `build_insights` | 通过 `tuist setup insights` 配置 `tuist inspect build`、`tuist xcodebuild`、`-resultBundlePath` 以及可选的机器指标。 |
| `test_insights` | 配置 `tuist inspect test`、方案测试后操作以及持续集成测试运行的结果包生成。 |
| `test_sharding` | 添加带有 `TUIST_SHARD_INDEX` 的 Xcode 或生成项目分片规划和分片执行工作流。 |

当省略 `features` 时，提示会要求代理澄清用户想要哪些集成，或在编辑 Xcode 项目之前从请求中推断出最小的有用集合。
