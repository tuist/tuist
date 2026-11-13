---
{
  "title": "Claude",
  "titleTemplate": ":title · Sandboxes · Features · Guides · Tuist",
  "description": "在 Tuist Sandboxes（Linux 或 macOS）上运行 Claude Managed Agents 会话和 Claude Code 云端会话（claude.ai、桌面和移动应用，以及 claude --cloud）。"
}
---
# Claude {#claude}

> [!IMPORTANT]
> **仅限邀请**
>
> Tuist Sandbox（包括 Linux 和 macOS）目前仅限邀请使用。[联系我们](mailto:contact@tuist.dev)或在[社区 Slack](https://slack.tuist.dev)中留言，为你的账户申请访问权限。

Anthropic 运行 Claude 的代理循环，而*自托管环境*决定 Claude 的工具在哪里运行。将一个环境连接到 Tuist，其中的每个会话都会获得自己的 Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>，可在 Linux 或 macOS 上运行。Tuist 会运行这些环境所需的工作器和 runner，因此你无需自行托管任何内容。

有两种类型的环境，每种 Claude 产品对应一种：

- **[Claude Managed Agents](#managed-agents)**：你通过 Claude API 或 Tuist 的 agent-sessions API 启动的会话。你在[Claude Console](https://platform.claude.com/environments)中创建环境（`env_…`），每个会话可以选择 Linux 或 macOS。
- **[Claude Code](#claude-code)**：开发者从 claude.ai、Claude 桌面和移动应用以及`claude --cloud`启动的云会话。Claude Team 或 Enterprise 的所有者在 claude.ai 管理设置中为每个平台创建一个环境（`ccpool_…`），开发者通过选择环境来选择 Linux 或 macOS。

两者均由账户管理员通过 Tuist API 进行连接。使用`tuist auth login`进行身份验证，然后：

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### 连接环境{#managed-agents-connect}

从你账户的**Settings → Integrations → Claude**进行连接。表单会要求提供自托管环境以及 Tuist 用于启动会话的凭据：

1. **创建环境。** 在 Claude Console 的[Environments](https://platform.claude.com/environments)页面上创建自托管环境，打开它并点击**Generate environment key**。Anthropic 仅在 Console 中生成环境密钥。
2. 使用表单顶部的选择器**选择凭据**（见下文）。
3. **粘贴环境 ID 和密钥**，并选择环境 sandbox 的平台和规格。

Tuist 在保存任何内容之前会使用凭据获取环境，因此错误的凭据、ID 或工作区会在表单中导致失败。它以加密方式存储密钥，且不再显示。在一分钟内，Tuist 开始为该环境的会话提供服务。有关规格，请参阅<.localized_link href="/guides/features/sandboxes#platforms">Linux 和 macOS</.localized_link>。

#### 使用 API 密钥{#managed-agents-connect-api-key}

这是默认选项，也是尝试 sandbox 的最快方法。粘贴一个在环境工作区中具有 developer 角色的 API 密钥。集成会标记使用 API 密钥的环境；在依赖它之前，请改用联合身份进行连接，这样 Tuist 就不会持有长期有效的密钥。

#### 使用联合身份{#managed-agents-connect-federated}

Tuist 使用 Anthropic 的[Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation)进行身份验证，因此你无需向其提供 Anthropic API 密钥。你需要在 Anthropic 组织中拥有 admin 角色。

1. **信任 Tuist。** 表单会显示你账户的颁发者 URL 和主体前缀。在 Claude Console 中，打开[Workload identity](https://platform.claude.com/settings/workload-identity-federation)，点击**Connect workload**，选择**Custom OIDC**，并使用范围`workspace:developer`输入它们。将向导创建的服务账户添加到环境的工作区。
2. **输入 ID。** 组织 ID 位于**Settings → Organization**下，工作区 ID 位于**Settings → Workspaces**下。连接工作负载完成后会显示服务账户和联合规则 ID，Workload identity 中的规则页面也会再次显示它们。这些都不是秘密。如果 Anthropic 拒绝 Tuist 的令牌，Console 的[authentication history](https://platform.claude.com/settings/workload-identity-federation?tab=history)会显示原因。

#### 使用 API{#managed-agents-connect-api}

要从自动化流程进行连接，请在[Claude Console](https://platform.claude.com/environments)中创建自托管环境，生成其密钥，并将两者发送给 Tuist：

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

要通过 Tuist 的 API 启动会话，还需发送四个联合 ID（参见[不使用 API 密钥进行连接](#managed-agents-federation)）或`anthropic_api_key`。除非你传递`"platform": "darwin"`，否则环境将在 Linux 上运行；`vcpus`、`memory_mb`和`workspace_gb`会更改其 sandbox 的规格。

### 启动会话{#managed-agents-sessions}

除非会话请求其他平台，否则每个会话都在环境的平台上运行。

**使用 Claude API**时，像往常一样使用环境 ID 创建会话，并将会话元数据中的`tuist_platform`设置为`macos`或`linux`：

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

`repository_url`以及可选的`repository_ref`（分支或提交）会使 Tuist 在代理的第一轮操作之前将公共仓库克隆到 sandbox 中。

**使用 Tuist 的 agent-sessions API**时，Tuist 会为你创建代理和会话，并克隆连接到你的 Tuist 账户的私有 GitHub 仓库：

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

当账户有多个环境时，请传递`agent_environment_id`。你可以使用`GET /agent-sessions/{id}/events`跟踪会话，使用`POST /agent-sessions/{id}/messages`回复，并使用`POST /agent-sessions/{id}/archive`结束会话。

仓库在 Linux 上检出到`/workspace`，在 macOS 上检出到`/Users/runner/work`。会话的 sandbox 会在代理完成一轮操作后暂停，并在收到下一条消息时恢复。

> [!WARNING]
> 任何能在拥有该环境的 Claude 工作区中创建会话的人，都可以在你的 Tuist 账户上运行会话，并可以通过会话元数据请求 macOS。请相应地限制对该工作区的访问。

### 不使用 API 密钥进行连接{#managed-agents-federation}

仪表板会为你设置此项。通过 API，Tuist 的工作方式相同：每个账户在 Tuist 都有自己的 OpenID Connect 颁发者`https://tuist.dev/oidc/accounts/<account id>`，并为每次对 Anthropic 的调用签署一个短期令牌，然后将其交换为持续几分钟的 Anthropic 访问令牌。信任你颁发者的联合规则绝不会接受 Tuist 为其他账户签署的令牌。

- 每个代理环境响应都包含`federation_issuer_url`和`federation_subject`（`account:123:agent-environment:456`）。在 Console 的 Custom OIDC 向导中，使用颁发者 URL 以及该确切主体以仅允许此环境，或使用`account:123:*`以允许该账户的所有环境。仪表板的设置检查使用主体`account:123:setup`，仅前缀允许。使用范围`workspace:developer`。
- 在创建时或通过`PATCH /agent-environments/{id}`发送组织、工作区、服务账户和规则 ID，分别为`anthropic_organization_id`、`anthropic_workspace_id`、`anthropic_service_account_id`和`anthropic_federation_rule_id`。当环境同时具有 ID 和 API 密钥时，Tuist 会使用联合身份。

> [!NOTE]
> Anthropic 通过 HTTPS 从公共主机名的 443 端口获取颁发者的密钥。如果你的自托管 Tuist 服务器无法从互联网访问，请在 Console 中选择**inline** JWKS 源，并粘贴你的服务器在`<issuer>/jwks.json`提供的密钥集。每当 Tuist 的签名密钥更改时（即服务器的`TUIST_SECRET_KEY_TOKENS`或在其未设置时的`TUIST_SECRET_KEY_BASE`发生更改时），请重新粘贴。

## Claude Code {#claude-code}

Claude Code 云会话是开发者从[claude.ai/code](https://claude.ai/code)、Claude 桌面和移动应用以及`claude --cloud`启动的会话。他们通过环境选择会话运行的位置，因此你需要为你希望提供的每个平台连接一个环境。

### 连接环境{#claude-code-connect}

1. Claude 组织所有者在[Cloud environments](https://claude.ai/admin-settings/cloud-environments)管理页面上启用**Allow self-hosted environments**。这需要 Team 或 Enterprise 计划；请参阅 Anthropic 的[self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments)指南。
2. 在同一页面上，为每个平台创建一个自托管环境，使用开发者将看到的名称，例如**Tuist Linux**和**Tuist macOS**。复制每个环境的`ccpool_…` ID 及其环境密钥，该密钥仅显示一次。
3. 将每个环境连接到你的 Tuist 账户，将`kind`设置为`claude_code`并指定其平台：

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

   对另一个环境的 ID 和密钥重复此操作，并将`"platform": "linux"`设置为相应值。

一分钟内，环境即可接受会话。空闲会话会保持其 sandbox 运行 30 分钟，然后暂停；会话的下一条消息会恢复同一个 sandbox。可以通过`max_idle_seconds`更改等待时间（最多 3600 秒）。

### 选择 Linux 或 macOS {#claude-code-choose}

开发者在启动云会话时选择环境，从而选择平台：

- **claude.ai、桌面和移动应用：** 在新会话的环境选择器中选择**Tuist Linux**或**Tuist macOS**。
- **Claude Code CLI：** 在`claude`中运行`/remote-env`并按名称选择环境。`claude --cloud "<task>"`随后将在该环境中运行。要为单个会话选择一个环境，请传递其 ID：`claude --cloud "<task>" --environment ccpool_...`。
- **整个团队或仓库：** 在 Claude Code [settings](https://code.claude.com/docs/en/settings)中设置默认环境的 ID，例如在仓库的`.claude/settings.json`中：

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

这些环境中的会话照常使用你组织的 Claude Code 用量，其 sandboxes 计入你的 Tuist 账户。

### 更快的会话启动和构建{#claude-code-caching}

- **Tuist 缓存：** 会话会获得`TUIST_URL`，并且当你的账户在同一机架中有缓存时，还会获得`TUIST_CACHE_ENDPOINT`。会话中的 Tuist CLI 和`tuist_ex` Mix 任务会使用会话的身份令牌自行登录。请参阅身份验证指南中的<.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code sessions</.localized_link>。
- **缓存的检出：** 当你账户的 Tuist GitHub 应用可以读取会话的仓库时，新会话会从 Tuist runners 使用的相同缓存检出开始，因此它只获取缺少的提交而不是进行克隆。当会话结束时，它会返回默认分支最新提交的对象，这使得即使对于不在 Tuist 上运行 CI 的仓库，缓存检出也能保持最新。只有 GitHub 报告的默认分支提交才会更新它；会话自己的分支永远不会更新它。禁用 sandboxes 或卸载应用以停止此功能。
- **macOS：** Mac 与每个 VM 共享 Claude Code 构建会话的运行结果，因此新会话无需下载它。

## 在任何 Claude Code 会话中使用 Mac {#remote-mac}

在 Linux 上运行的 Claude Code 会话（例如 Anthropic 托管环境中的云会话）仍然可以在 Tuist macOS sandbox 上构建和测试 Apple 平台代码，如<.localized_link href="/guides/features/sandboxes#coding-agents">Build on a Mac from a coding agent</.localized_link>中所述。与**Tuist macOS**环境不同，该会话保留其自身的环境。

在**Tuist Linux**环境中无需任何设置：Tuist CLI 和 Tuist MCP 服务器已安装并使用会话的身份登录。

对于 Anthropic 托管环境中的云会话：

1. 使 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP server</.localized_link>可供会话使用：在 claude.ai 中将`https://tuist.dev/mcp`添加为连接器并为会话启用它，或在仓库提交的`.mcp.json`中声明它。
2. 在环境的[setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts)中安装 Tuist CLI，例如使用`curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`。
3. 创建一个具有`account:sandboxes:write`范围的<.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>，并将其作为`TUIST_TOKEN`添加到环境的[environment variables](https://code.claude.com/docs/en/cloud-environments#set-environment-variables)中。使用该环境的每个人都可以读取它，因此不要赋予它其他范围。
4. 允许环境访问 Tuist。Anthropic 默认的**Trusted**网络访问不包括`tuist.dev`，因此请选择**Custom**，保留默认域名，并将`tuist.dev`添加到**Allowed domains**。CLI 通过`tuist.dev`将会话的文件上传到 Mac，因此不需要其他域名。

任务完成后，Claude 会删除 Mac。遗留的 Mac 在空闲时暂停，并在暂停 14 天后删除。以这种方式创建的 Mac 像其他 sandbox 一样计入你的 Tuist 账户。
