---
{
  "title": "Claude",
  "titleTemplate": ":title · 샌드박스 · 기능 · 가이드 · Tuist",
  "description": "Linux 또는 macOS에서 Tuist 샌드박스로 Claude Managed Agents 세션과 Claude Code 클라우드 세션(claude.ai, 데스크톱 및 모바일 앱, claude --cloud)을 실행합니다."
}
---
# Claude {#claude}

> [!IMPORTANT]
> **초대 전용**
>
> Tuist 샌드박스(Linux 및 macOS)는 현재 초대 전용입니다. 계정 액세스를 요청하려면 [문의](mailto:contact@tuist.dev)하거나 [커뮤니티 Slack](https://slack.tuist.dev)에서 메시지를 보내세요.

Anthropic은 Claude의 에이전트 루프를 실행하며, *셀프 호스팅 환경*에서 Claude 도구가 실행될 위치를 결정합니다. 이를 Tuist에 연결하면 해당 환경의 모든 세션이 Linux 또는 macOS에서 자체 Tuist <.localized_link href="/guides/features/sandboxes">샌드박스</.localized_link>를 갖게 됩니다. Tuist는 이러한 환경에 필요한 워커와 러너를 실행하므로 별도로 호스팅할 필요가 없습니다.

Claude 제품별로 한 가지씩, 두 가지 유형의 환경이 있습니다:

- **[Claude Managed Agents](#managed-agents)**: Claude API 또는 Tuist의 agent-sessions API로 시작하는 세션입니다. [Claude Console](https://platform.claude.com/environments)에서 환경(`env_…`)을 생성하며, 각 세션은 Linux 또는 macOS를 선택할 수 있습니다.
- **[Claude Code](#claude-code)**: 개발자가 claude.ai, Claude 데스크톱 및 모바일 앱, 그리고 `claude --cloud`에서 시작하는 클라우드 세션입니다. Claude Team 또는 Enterprise 소유자는 claude.ai 관리자 설정에서 플랫폼별로 하나씩 환경(`ccpool_…`)을 생성하며, 개발자는 환경을 선택하여 Linux 또는 macOS를.pick합니다.

두 가지 모두 계정 관리자가 Tuist API를 통해 연결합니다. `tuist auth login`로 인증한 후 다음을 수행하세요:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### 환경 연결 {#managed-agents-connect}

계정의 **Settings → Integrations → Claude**에서 연결하세요. 양식에는 셀프 호스팅 환경과 Tuist가 세션을 시작할 때 사용하는 자격 증명이 필요합니다:

1. **환경을 생성합니다.** Claude Console의 [Environments](https://platform.claude.com/environments) 페이지에서 셀프 호스팅 환경을 생성하고, 열어 **Generate environment key**를 클릭하세요. Anthropic은 Console에서만 환경 키를 생성합니다.
2. 양식 상단의 선택기(아래 참조)로 **자격 증명을 선택**하세요.
3. **환경 ID와 키를 붙여넣고** 환경 샌드박스의 플랫폼과 셰이프를 선택하세요.

Tuist는 정보를 저장하기 전에 자격 증명으로 환경을 가져오므로, 잘못된 자격 증명, ID 또는 워크스페이스는 양식에서 실패합니다. 키는 암호화되어 저장되며 다시 표시되지 않습니다. 1분 이내에 Tuist는 환경의 세션 제공을 시작합니다. 셰이프는 <.localized_link href="/guides/features/sandboxes#platforms">Linux and macOS</.localized_link>를 참조하세요.

#### API 키 사용 {#managed-agents-connect-api-key}

기본값이며 샌드박스를 빠르게 체험할 수 있는 방법입니다. 환경의 워크스페이스에서 개발자 역할이 있는 API 키를 붙여넣으세요. 통합 기능은 API 키를 사용하는 환경을 표시합니다. 이에 의존하기 전에 대신 연합 신원으로 연결하여 Tuist가 장기 유효 키를 보유하지 않도록 하세요.

#### 연합 신원 사용 {#managed-agents-connect-federated}

Tuist는 Anthropic의 [Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation)으로 인증하므로 Anthropic API 키를 제공할 필요가 없습니다. Anthropic 조직에서 관리자 역할이 필요합니다.

1. **Tuist를 신뢰합니다.** 양식에는 계정의 발급자 URL과 주제 접두사가 표시됩니다. Claude Console에서 [Workload identity](https://platform.claude.com/settings/workload-identity-federation)를 열고, **Connect workload**를 클릭한 후, **Custom OIDC**를 선택하고 범위 `workspace:developer`와 함께 입력하세요. 마법사가 생성한 서비스 계정을 환경의 워크스페이스에 추가하세요.
2. **ID를 입력합니다.** 조직 ID는 **Settings → Organization** 아래에, 워크스페이스 ID는 **Settings → Workspaces** 아래에 있습니다. Connect workload가 완료되면 서비스 계정과 연합 규칙 ID를 표시하며, Workload identity의 규칙 페이지에서도 다시 확인할 수 있습니다. 이들 중 어느 것도 비밀이 아닙니다. Anthropic이 Tuist의 토큰을 거부하면 Console의 [authentication history](https://platform.claude.com/settings/workload-identity-federation?tab=history)에서 이유를 확인할 수 있습니다.

#### API 사용 {#managed-agents-connect-api}

자동화에서 연결하려면 [Claude Console](https://platform.claude.com/environments)에서 셀프 호스팅 환경을 생성하고 키를 생성한 후 둘 다 Tuist로 전송하세요:

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

Tuist의 API를 통해 세션을 시작하려면 네 개의 연합 ID([Connect without an API key](#managed-agents-federation) 참조) 또는 `anthropic_api_key`도 함께 전송하세요. `"platform": "darwin"`를 전달하지 않으면 환경은 Linux에서 실행됩니다. `vcpus`, `memory_mb` 및 `workspace_gb`는 샌드박스의 셰이프를 변경합니다.

### 세션 시작 {#managed-agents-sessions}

세션이 다른 플랫폼을 요청하지 않는 한 각 세션은 환경의 플랫폼에서 실행됩니다.

**Claude API 사용** 시, 평소대로 환경 ID로 세션을 생성하고 세션 메타데이터에서 `tuist_platform`를 `macos` 또는 `linux`로 설정하세요:

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

`repository_url` 및 선택적으로 `repository_ref`(브랜치 또는 커밋)는 에이전트의 첫 번째 턴 전에 Tuist가 공개 리포지토리를 샌드박스로 클론하도록 합니다.

**Tuist의 agent-sessions API 사용** 시, Tuist가 에이전트와 세션을 생성해주며 Tuist 계정에 연결된 비공개 GitHub 리포지토리를 클론합니다:

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

계정에 여러 환경이 있는 경우 `agent_environment_id`를 전달하세요. `GET /agent-sessions/{id}/events`로 세션을 추적하고, `POST /agent-sessions/{id}/messages`로 응답하며, `POST /agent-sessions/{id}/archive`로 종료할 수 있습니다.

리포지토리는 Linux에서 `/workspace`, macOS에서 `/Users/runner/work`로 체크아웃됩니다. 세션의 샌드박스는 에이전트가 턴을 마치면 일시 중지되고 다음 메시지에서 재개됩니다.

> [!WARNING]
> 환경을 소유한 Claude 워크스페이스에서 세션을 생성할 수 있는 사람은 누구나 귀하의 Tuist 계정에서 세션을 실행할 수 있으며, 세션 메타데이터로 macOS를 요청할 수 있습니다. 해당 워크스페이스에 대한 액세스를 적절히 제한하세요.

### API 키 없이 연결 {#managed-agents-federation}

대시보드에서 이를 설정해줍니다. API를 통해 Tuist도 동일하게 작동합니다. 모든 계정은 Tuist에서 자체 OpenID Connect 발급자 `https://tuist.dev/oidc/accounts/<account id>`를 가지며, Anthropic에 대한 각 호출마다 단기 토큰에 서명하여 몇 분 동안 유효한 Anthropic 액세스 토큰으로 교환합니다. 귀하의 발급자를 신뢰하는 연합 규칙은 Tuist가 다른 계정을 위해 서명한 토큰을 절대 허용하지 않습니다.

- 모든 에이전트 환경 응답에는 `federation_issuer_url` 및 `federation_subject`(`account:123:agent-environment:456`)가 포함됩니다. Console의 Custom OIDC 마법사에서 발급자 URL과 해당 정확한 주제를 사용하여 이 환경만 허용하거나, 계정의 모든 환경을 허용하려면 `account:123:*`를 사용하세요. 대시보드의 설정 확인은 접두사만 허용하는 주제 `account:123:setup`를 사용합니다. 범위 `workspace:developer`를 사용하세요.
- 조직, 워크스페이스, 서비스 계정 및 규칙 ID를 `anthropic_organization_id`, `anthropic_workspace_id`, `anthropic_service_account_id` 및 `anthropic_federation_rule_id`로 생성 시 또는 `PATCH /agent-environments/{id}`와 함께 전송하세요. 환경에 ID와 API 키가 모두 있는 경우 Tuist는 연합을 사용합니다.

> [!NOTE]
> Anthropic은 공개 호스트네임에서 HTTPS 포트 443을 통해 발급자의 키를 가져옵니다. 자체 호스팅 Tuist 서버가 인터넷에서 접근할 수 없는 경우, Console에서 **인라인** JWKS 소스를 선택하고 서버가 `<issuer>/jwks.json`에서 제공하는 키 세트를 붙여넣으세요. Tuist의 서명 키가 변경될 때마다 다시 붙여넣어야 하며, 이는 서버의 `TUIST_SECRET_KEY_TOKENS`(또는 설정되지 않은 경우 `TUIST_SECRET_KEY_BASE`)가 변경될 때 발생합니다.

## Claude Code {#claude-code}

Claude Code 클라우드 세션은 개발자가 [claude.ai/code](https://claude.ai/code), Claude 데스크톱 및 모바일 앱, 그리고 `claude --cloud`에서 시작하는 세션입니다. 세션이 실행될 위치는 환경에 따라 결정되므로, 제공하려는 각 플랫폼마다 하나의 환경을 연결하세요.

### 환경 연결 {#claude-code-connect}

1. Claude 조직 소유자는 [Cloud environments](https://claude.ai/admin-settings/cloud-environments) 관리자 페이지에서 **Allow self-hosted environments**를 활성화합니다. 이는 Team 또는 Enterprise 플랜이 필요하며, Anthropic의 [self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments) 가이드를 참조하세요.
2. 같은 페이지에서 각 플랫폼마다 개발자가 볼 이름(예: **Tuist Linux** 및 **Tuist macOS**)으로 자체 호스팅 환경을 생성하세요. 각 환경의 `ccpool_…` ID와 한 번만 표시되는 환경 키를 복사하세요.
3. 각 환경을 Tuist 계정에 연결할 때 `kind`를 `claude_code`로 설정하고 플랫폼을 지정하세요:

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

   `"platform": "linux"`와 다른 환경의 ID 및 키를 사용하여 반복하세요.

1분 이내에 환경이 세션을 받을 준비가 됩니다. 유휴 세션은 샌드박스를 30분 동안 실행한 후 일시 중지하며, 세션의 다음 메시지는 동일한 샌드박스를 재개합니다. `max_idle_seconds`(최대 3600)로 대기 시간을 변경하세요.

### Linux 또는 macOS 선택 {#claude-code-choose}

개발자는 클라우드 세션을 시작할 때 환경과 함께 플랫폼을 선택합니다:

- **claude.ai, 데스크톱 및 모바일 앱:** 새 세션의 환경 선택기에서 **Tuist Linux** 또는 **Tuist macOS**를 선택하세요.
- **Claude Code CLI:** `claude`에서 `/remote-env`를 실행하고 이름으로 환경을 선택하세요. 그러면 `claude --cloud "<task>"`가 해당 환경에서 실행됩니다. 단일 세션용으로 하나를 선택하려면 ID를 전달하세요: `claude --cloud "<task>" --environment ccpool_...`.
- **전체 팀 또는 리포지토리:** Claude Code [settings](https://code.claude.com/docs/en/settings)에서 기본 환경의 ID를 설정하세요. 예를 들어 리포지토리의 `.claude/settings.json`에 설정할 수 있습니다:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

이러한 환경의 세션은 조직의 Claude Code 사용량을 평소대로 사용하며, 해당 샌드박스는 Tuist 계정에 포함됩니다.

### 더 빠른 세션 시작 및 빌드 {#claude-code-caching}

- **Tuist 캐시:** 세션은 `TUIST_URL`를 받으며, 계정에 같은 랙에 캐시가 있는 경우 `TUIST_CACHE_ENDPOINT`도 받습니다. 세션 내의 Tuist CLI와 `tuist_ex` Mix 작업은 세션의_identity token_으로 자체 로그인합니다. 인증 가이드의 <.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code sessions</.localized_link>을 참조하세요.
- **캐시된 체크아웃:** 계정의 Tuist GitHub 앱이 세션의 리포지토리를 읽을 수 있으면, 새 세션은 Tuist 러너가 사용하는 것과 동일한 캐시된 체크아웃에서 시작되므로 클론 대신 누락된 커밋만 가져옵니다. 세션이 종료되면 기본 브랜치의 최신 커밋 객체를 반환하여, Tuist에서 CI를 실행하지 않는 리포지토리라도 캐시된 체크아웃을 최신 상태로 유지합니다. GitHub가 기본 브랜치에 대해 보고하는 커밋만 이를 업데이트하며, 세션 자체의 브랜치는 업데이트하지 않습니다. 이를 중지하려면 샌드박스를 비활성화하거나 앱을 제거하세요.
- **macOS:** Mac은 각 VM에서 실행되는 Claude Code 빌드 세션을 공유하므로, 새 세션은 이를 다운로드하지 않습니다.

## 모든 Claude Code 세션에서 Mac 사용 {#remote-mac}

Anthropic 호스팅 환경의 클라우드 세션과 같이 Linux에서 실행되는 Claude Code 세션은 <.localized_link href="/guides/features/sandboxes#coding-agents">Build on a Mac from a coding agent</.localized_link>에 설명된 대로 Tuist macOS 샌드박스에서 Apple 플랫폼 코드를 빌드하고 테스트할 수 있습니다. **Tuist macOS** 환경과 달리, 세션은 자체 환경을 유지합니다.

**Tuist Linux** 환경에서는 설정할 것이 없습니다. Tuist CLI와 Tuist MCP 서버가 이미 설치되어 있으며 세션의 identity로 로그인합니다.

Anthropic 호스팅 환경의 클라우드 세션의 경우:

1. Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP server</.localized_link>를 세션에서 사용할 수 있게 하세요: claude.ai에서 `https://tuist.dev/mcp`를 커넥터로 추가하고 세션에서 활성화하거나, 리포지토리의 커밋된 `.mcp.json`에 선언하세요.
2. 환경의 [setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts)에 Tuist CLI를 설치하세요. 예를 들어 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`를 사용할 수 있습니다.
3. `account:sandboxes:write` 범위를 가진 <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>을 생성하고, 이를 환경의 [environment variables](https://code.claude.com/docs/en/cloud-environments#set-environment-variables)에 `TUIST_TOKEN`로 추가하세요. 환경을 사용하는 모든 사람이 이를 읽을 수 있으므로 다른 범위는 부여하지 마세요.
4. 환경이 Tuist에 도달할 수 있도록 하세요. Anthropic의 기본 **Trusted** 네트워크 액세스에는 `tuist.dev`가 포함되지 않으므로, **Custom**을 선택하고 기본 도메인을 유지한 채 `tuist.dev`를 **Allowed domains**에 추가하세요. CLI는 `tuist.dev`를 통해 세션 파일을 Mac에 업로드하므로 다른 도메인은 필요하지 않습니다.

Claude는 작업이 완료되면 Mac을 삭제합니다. 남겨진 Mac은 유휴 상태일 때 일시 중지되며, 14일 동안 일시 중지된 후 삭제됩니다. 이렇게 생성된 Mac은 다른 샌드박스처럼 Tuist 계정에 포함됩니다.
