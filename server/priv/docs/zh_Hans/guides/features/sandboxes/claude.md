---
{
  "title": "Claude",
  "titleTemplate": ":title · 沙盒 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 沙盒（Linux 或 macOS）上运行 Claude Managed Agents 会话和 Claude Code 云端会话（claude.ai、桌面和移动应用，以及 claude --cloud）。"
}
---
# Claude {#claude}

> [!IMPORTANT]
> **仅限邀请**
>
> Tuist Sandboxes（包括 Linux 和 macOS）目前仅限邀请使用。[联系我们](mailto:contact@tuist.dev)或在[社区 Slack](https://slack.tuist.dev)中与我们取得联系，以请求为你的账户开通访问权限。

Anthropic 运行 Claude 的代理循环，而*自托管环境*决定 Claude 的工具在哪里运行。将其连接到 Tuist，其中的每个会话都会获得自己的 Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>，可在 Linux 或 macOS 上运行。Tuist 会运行这些环境所需的工作器和运行器，因此你无需托管任何内容。

有两种类型的环境，每种 Claude 产品对应一种：

- **[Claude Managed Agents](#managed-agents)**：你通过 Claude API 或 Tuist 的 agent-sessions API 启动的会话。你在 [Claude Console](https://platform.claude.com/environments) 中创建环境（`env_…`），每个会话可以选择 Linux 或 macOS。
- **[Claude Code](#claude-code)**：开发人员从 claude.ai、Claude 桌面和移动应用以及`claude --cloud`启动的云会话。Claude Team 或 Enterprise 所有者在 claude.ai 管理设置中为每个平台创建一个环境（`ccpool_…`），开发人员通过选择环境来选择 Linux 或 macOS。

两者均由账户管理员通过 Tuist API 进行连接。使用`tuist auth login`进行身份验证，然后：

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### 连接环境{#managed-agents-connect}

从你账户的**Settings → Integrations → Claude**进行连接。表单要求提供自托管环境以及 Tuist 用于启动会话的凭据：

1. **创建环境。** 在 Claude Console 的[Environments](https://platform.claude.com/environments)页面上创建自托管环境，打开它并点击**Generate environment key**。Anthropic 仅在 Console 中生成环境密钥。
2. 使用表单顶部的选择器**选择凭据**（见下文）。
3. **粘贴环境 ID 和密钥**，并选择环境沙箱的平台和规格。

Tuist 在保存任何内容之前会使用凭据获取环境，因此错误的凭据、ID 或工作区会在表单中失败。它以加密方式存储密钥，且不再显示。在一分钟内，Tuist 开始为该环境的会话提供服务。有关规格，请参阅<.localized_link href="/guides/features/sandboxes#platforms">Linux 和 macOS</.localized_link>。

#### 使用 API 密钥{#managed-agents-connect-api-key}

这是默认选项，也是尝试沙箱的最快方法。粘贴具有环境工作区中开发者角色的 API 密钥。集成会标记使用 API 密钥的环境；在依赖此类密钥之前，请改用联合身份进行连接，这样 Tuist 就不会持有长期有效的密钥。

#### 使用联合身份{#managed-agents-connect-federated}

Tuist 使用 Anthropic 的[Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation)进行身份验证，因此你无需向其提供 Anthropic API 密钥。你需要在 Anthropic 组织中拥有管理员角色。

1. **信任 Tuist。** 表单会显示你账户的颁发者 URL 和主体前缀。在 Claude Console 中，打开[Workload identity](https://platform.claude.com/settings/workload-identity-federation)，点击**Connect workload**，选择**Custom OIDC**，并使用范围`workspace:developer`输入它们。将向导创建的服务账户添加到环境的工作区。
2. **输入 ID。** 组织 ID 位于**Settings → Organization**下，工作区 ID 位于**Settings → Workspaces**下。连接工作负载完成后会显示服务账户和联合规则 ID，Workload identity 中的规则页面也会再次显示它们。它们都不是秘密。如果 Anthropic 拒绝 Tuist 的令牌，Console 的[authentication history](https://platform.claude.com/settings/workload-identity-federation?tab=history)会显示原因。

#### 使用 API {#managed-agents-connect-api}

要从自动化进行连接，请在[Claude Console](https://platform.claude.com/environments)中创建自托管环境，生成其密钥，然后将两者发送给 Tuist：

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

要通过 Tuist 的 API 启动会话，还需发送四个联合 ID（参见[不使用 API 密钥进行连接](#managed-agents-federation)）或`anthropic_api_key`。除非你传递`"platform": "darwin"`，否则环境将在 Linux 上运行；`vcpus`、`memory_mb`和`workspace_gb`会更改其沙箱的规格，而`xcode_version`会更改其 macOS 沙箱的[Xcode](#xcode)。

### 启动会话{#managed-agents-sessions}

除非会话请求其他平台，否则每个会话都在环境的平台上运行。

**使用 Claude API**时，照常使用环境 ID 创建会话，并将会话元数据中的`tuist_platform`设置为`macos`或`linux`：

```bash
curl https://api.anthropic.com/v1/sessions \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01" \
  -H "content-type: application/json" \
  -d '{
    "agent": "agent_...",
    "environment_id": "env_...",
    "metadata": {
      "tuist_platform": "macos",
      "repository_url": "https://github.com/my-org/my-app"
    }
  }'
```

`repository_url`和可选的`repository_ref`（分支或提交）会使 Tuist 在代理的第一轮操作之前将公共存储库克隆到沙箱中。

**使用 Tuist 的 agent-sessions API**时，Tuist 会为你创建代理和会话，并克隆连接到你的 Tuist 账户的私有 GitHub 存储库：

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-sessions" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "prompt": "Fix the failing snapshot tests",
    "platform": "darwin",
    "repository_url": "https://github.com/my-org/my-app",
    "repository_ref": "main"
  }'
```

当账户有多个环境时，传递`agent_environment_id`。你可以使用`GET /agent-sessions/{id}/events`跟踪会话，使用`POST /agent-sessions/{id}/messages`回复，并使用`POST /agent-sessions/{id}/archive`结束会话。

存储库在 Linux 上的`/workspace`和 macOS 上的`/Users/runner/work`中签出。会话的沙箱在代理完成一轮操作后暂停，并在下一条消息时恢复。

### 选择会话的 Xcode {#managed-agents-xcode}

会话的 Mac 在 Claude 运行任何工具之前启动，因此 Claude 无法选择自己的 Xcode。由创建会话的人选择它，选择方式与选择 macOS 相同。Tuist 使用第一个已设置的选项：

1. Tuist 的 agent-sessions API 中的`xcode_version`，位于`platform`旁边。如果你创建的会话使用了 Tuist 不提供的版本，则会被拒绝，并列出你可选择的版本。
2. 使用 Claude API 创建会话时，会话元数据中的`tuist_xcode_version`：

   ```json
   "metadata": { "tuist_platform": "macos", "tuist_xcode_version": "26.1.1" }
   ```

3. 当会话在环境的平台上运行时，使用环境的`xcode_version`。
4. 默认 Xcode。

不带平台的 Xcode 表示需要 macOS。需要注意的事项：

- **会话保留其 Xcode。** 其沙箱只启动一次，后续的消息或更改的元数据不会改变它。如需使用其他 Xcode，请使用新会话。
- **Tuist 在第一轮操作到达时检查元数据。** 如果`tuist_xcode_version`指定的 Xcode 是 Tuist 不提供的，Tuist 会在不启动沙箱的情况下停止该轮操作，并记录你可选择的版本。使用 Tuist 的 agent-sessions API 可在创建会话时获取错误信息。
- **在 macOS 环境中，Tuist 会等待而不是猜测。** 如果 Tuist 无法读取新会话的元数据，它会暂停该轮操作并重试，而不是启动环境的 Xcode。

> [!WARNING]
> 任何能在拥有该环境的 Claude 工作区中创建会话的人，都可以在你的 Tuist 账户上运行会话，并通过会话元数据请求 macOS 及其 Xcode。请相应地限制对该工作区的访问权限。

### 无需 API 密钥即可连接 {#managed-agents-federation}

仪表板会为你完成此设置。通过 API，Tuist 的工作方式相同：每个账户在 Tuist 都有自己的 OpenID Connect 颁发者`https://tuist.dev/oidc/accounts/<account id>`，并为每次调用 Anthropic 签署一个短期令牌，然后将其交换为有效期几分钟的 Anthropic 访问令牌。信任你颁发者的联合规则绝不会接受 Tuist 为其他账户签署的令牌。

- 每个代理环境响应都包含`federation_issuer_url`和`federation_subject`（`account:123:agent-environment:456`）。在控制台的自定义 OIDC 向导中，使用颁发者 URL 以及该确切的主题以仅允许此环境，或使用`account:123:*`以允许该账户的所有环境。仪表板的设置检查使用主题`account:123:setup`，仅前缀匹配即可允许。使用范围`workspace:developer`。
- 在创建时或通过`PATCH /agent-environments/{id}`发送组织、工作区、服务账户和规则 ID，分别为`anthropic_organization_id`、`anthropic_workspace_id`、`anthropic_service_account_id`和`anthropic_federation_rule_id`。当环境同时具有这些 ID 和 API 密钥时，Tuist 会使用联合身份验证。

> [!NOTE]
> Anthropic 通过 HTTPS 从公共主机名的 443 端口获取颁发者的密钥。如果你的自托管 Tuist 服务器无法从互联网访问，请在控制台中选择**内联** JWKS 源，并粘贴你的服务器在`<issuer>/jwks.json`提供的密钥集。每当 Tuist 的签名密钥更改时（即服务器的`TUIST_SECRET_KEY_TOKENS`更改时，或者在其未设置时`TUIST_SECRET_KEY_BASE`更改时），请再次粘贴。

## Claude Code {#claude-code}

Claude Code 云会话是开发者从[claude.ai/code](https://claude.ai/code)、Claude 桌面和移动应用以及`claude --cloud`启动的会话。它们通过环境选择会话运行的位置，因此你需要为想要提供的每个平台连接一个环境。

### 连接环境 {#claude-code-connect}

1. Claude 组织所有者在[Cloud environments](https://claude.ai/admin-settings/cloud-environments)管理页面上开启**Allow self-hosted environments**。这需要 Team 或 Enterprise 计划；请参阅 Anthropic 的[self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments)指南。
2. 在同一页面上，为每个平台创建一个自托管环境，使用开发者将看到的名称，例如**Tuist Linux**和**Tuist macOS**。复制每个环境的`ccpool_…` ID 及其环境密钥，该密钥仅显示一次。
3. 将每个环境连接到你的 Tuist 账户，将`kind`设置为`claude_code`及其平台：

   ```bash
   curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
     -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
     -d '{
       "kind": "claude_code",
       "platform": "darwin",
       "name": "Tuist macOS",
       "anthropic_environment_id": "ccpool_...",
       "environment_key": "<environment key>"
     }'
   ```

   对另一个环境的 ID 和密钥重复上述操作，并将`"platform": "linux"`设置为相应值。

一分钟内，环境即可接受会话。空闲会话会保持其沙箱运行 30 分钟，然后暂停；会话的下一条消息会恢复同一沙箱。使用`max_idle_seconds`更改等待时间（最多 3600 秒）。

### 选择 Linux 或 macOS {#claude-code-choose}

开发者在启动云会话时选择环境，从而选择平台：

- **claude.ai、桌面和移动应用：** 在新会话的环境选择器中选择**Tuist Linux**或**Tuist macOS**。
- **Claude Code CLI：** 在`claude`中运行`/remote-env`并按名称选择环境。`claude --cloud "<task>"`随后将在该环境上运行。要为单个会话选择一个环境，请传递其 ID：`claude --cloud "<task>" --environment ccpool_...`。
- **整个团队或存储库：** 在 Claude Code [settings](https://code.claude.com/docs/en/settings)中设置默认环境的 ID，例如在存储库的`.claude/settings.json`中：

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

这些环境中的会话照常使用你组织的 Claude Code 用量，其沙箱计入你的 Tuist 账户。

### 选择 Xcode {#xcode}

每个 macOS 环境启动一个<.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>，除非你使用`xcode_version`连接它（例如`"xcode_version": "26.1.1"`），否则为默认版本。要提供多个版本，请为每个版本连接一个环境并以该版本命名，例如**Tuist macOS · Xcode 26.1.1**。开发者然后通过选择环境来选择 Xcode。

要将环境切换到另一个 Xcode，请更新它：

```bash
curl -X PATCH "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments/<id>" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{ "xcode_version": "27.0" }'
```

新会话将获得新的 Xcode，而已有沙箱的会话将保留其现有的 Xcode。`null`恢复为默认值。这同样适用于 Managed Agents 环境，其会话也可以[自行选择](#managed-agents-xcode)。

### 更快的会话启动和构建 {#claude-code-caching}

- **Tuist 缓存：** 会话获得`TUIST_URL`，并且当你的账户在同一机架中有缓存时，还会获得`TUIST_CACHE_ENDPOINT`。会话中的 Tuist CLI 和`tuist_ex` Mix 任务会使用会话的身份令牌自动登录。请参阅身份验证指南中的<.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code sessions</.localized_link>。
- **缓存的检出：** 当你账户的 Tuist GitHub 应用可以读取会话的存储库时，新会话会从 Tuist 运行器使用的相同缓存检出开始，因此它只获取缺少的提交而不是克隆。当会话结束时，它会返回默认分支最新提交的对象，这使得即使对于不在 Tuist 上运行 CI 的存储库，缓存检出也能保持最新。只有 GitHub 报告的默认分支的提交才会更新它；会话自己的分支永远不会更新它。禁用沙箱或卸载应用以停止此行为。
- **macOS：** Mac 与每个 VM 共享 Claude Code 构建会话的运行结果，因此新会话无需下载它。

## 在任何 Claude Code 会话中使用 Mac {#remote-mac}

在 Linux 上运行的 Claude Code 会话（例如 Anthropic 托管环境中的云会话）仍然可以在 Tuist macOS 沙箱上构建和测试 Apple 平台代码，如<.localized_link href="/guides/features/sandboxes#coding-agents">Build on a Mac from a coding agent</.localized_link>中所述。与**Tuist macOS**环境不同，会话保留其自身的环境。

在**Tuist Linux**环境中无需设置：Tuist CLI 和 Tuist MCP 服务器已安装并使用会话的身份登录。

对于 Anthropic 托管环境中的云会话：

1. 使 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP server</.localized_link>可用于会话：在 claude.ai 中将`https://tuist.dev/mcp`添加为连接器并为会话启用它，或在存储库提交的`.mcp.json`中声明它。
2. 在环境的[setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts)中安装 Tuist CLI，例如使用`curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`。
3. 创建一个具有`account:sandboxes:write`范围的<.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>，并将其作为`TUIST_TOKEN`添加到环境的[environment variables](https://code.claude.com/docs/en/cloud-environments#set-environment-variables)中。使用该环境的每个人都可以读取它，因此除非他们也可能使用你的缓存，否则不要赋予其他范围：Mac 上的命令仅在令牌允许的范围内获得<.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">cache access</.localized_link>，因此添加`ci`以便 Mac 上的构建可以读写你的缓存。
4. 让环境能够访问 Tuist。Anthropic 默认的**Trusted**网络访问不包含`tuist.dev`，因此选择**Custom**，保留默认域名，并将`tuist.dev`添加到**Allowed domains**。CLI 通过`tuist.dev`将会话的文件上传到 Mac，因此不需要其他域名。

Mac 上已安装 Tuist CLI，并在项目通过 mise 固定版本时运行该版本；Tuist 4.218.0 及更高版本会在每个命令中自动登录到你账户的缓存。

### 预置 Mac {#remote-mac-snapshots}

**Tuist Linux**环境可以提前准备这些 Mac。通过 API 设置其 macOS 设置脚本（在`PATCH /api/accounts/{account}/sandboxes/agent-environments/{id}`上使用`macos_setup_script`），例如：

```bash
mise install
tuist install
tuist generate --no-open
xcodebuild build -workspace App.xcworkspace -scheme App -destination 'platform=iOS Simulator,name=iPhone 17'
```

当 Claude 为连接到你的某个 Tuist 项目的存储库创建 Mac 时，`create_sandbox`会获取该存储库，并且 Mac 会从该存储库针对其 Xcode 的快照启动：默认分支被克隆到`~/work/<name>`，脚本已在其中运行，且构建产物已就位。首次`tuist sandbox sync`仅发送与该提交不同的文件，因此 Xcode 仅重新构建发生变化的部分。存储库和 Xcode 的首台 Mac 以空白状态启动，并在空闲 Mac 上为其构建快照，耗时最多一小时，以供后续 Mac 使用。更改脚本、Xcode 或镜像会重新构建它。快照保留镜像中的模拟器并丢弃脚本创建的模拟器，并且每台此类 Mac 在运行后立即开始启动镜像中最新的 Pro iPhone（Xcode 27.2 上的 iPhone 18 Pro），因此在首次构建结束时即可就绪；也在脚本中为该模拟器构建，以便会话中针对它的构建复用快照中的内容。

任务完成后，Claude 会删除 Mac。遗留的 Mac 在空闲时会暂停，并在暂停 14 天后被删除。以这种方式创建的 Mac 像其他沙箱一样计入你的 Tuist 账户。
