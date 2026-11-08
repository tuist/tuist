---
{
  "title": "Claude",
  "titleTemplate": ":title · 샌드박스 · 기능 · 가이드 · Tuist",
  "description": "Linux 또는 macOS에서 실행되는 Tuist 샌드박스로 Claude Managed Agents 세션과 Claude Code 클라우드 세션(claude.ai, 데스크톱 및 모바일 앱, 그리고 claude --cloud)을 실행하세요."
}
---
# Claude {#claude}

> [!IMPORTANT]
> **초대 전용**
>
> Tuist 샌드박스(Linux 및 macOS)는 현재 초대 전용입니다. 계정에 대한 액세스를 요청하려면 [문의](mailto:contact@tuist.dev)하거나 [커뮤니티 Slack](https://slack.tuist.dev)에서 메시지를 보내세요.

Anthropic은 Claude의 에이전트 루프를 실행하며, *자체 호스팅 환경*이 Claude 도구의 실행 위치를 결정합니다. 이를 Tuist에 연결하면 해당 환경의 모든 세션이 Linux 또는 macOS에서 자체 Tuist <.localized_link href="/guides/features/sandboxes">샌드박스</.localized_link>를 갖게 됩니다. Tuist는 이러한 환경에 필요한 워커와 러너를 실행하므로 별도로 호스팅할 필요가 없습니다.

Claude 제품별로 두 가지 유형의 환경이 있습니다:

- **[Claude Managed Agents](#managed-agents)**: Claude API 또는 Tuist의 agent-sessions API로 시작하는 세션입니다. [Claude Console](https://platform.claude.com/environments)에서 환경(`env_…`)을 생성하며, 각 세션은 Linux 또는 macOS를 선택할 수 있습니다.
- **[Claude Code](#claude-code)**: 개발자가 claude.ai, Claude 데스크톱 및 모바일 앱, 그리고 `claude --cloud`에서 시작하는 클라우드 세션입니다. Claude Team 또는 Enterprise 소유자는 claude.ai 관리자 설정에서 플랫폼별 환경(`ccpool_…`)을 생성하며, 개발자는 환경을 선택하여 Linux 또는 macOS를 선택합니다.

두 환경 모두 계정 관리자가 Tuist API를 통해 연결합니다. `tuist auth login`로 인증한 후 다음을 수행하세요:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### 환경 연결 {#managed-agents-connect}

1. [Claude Console](https://platform.claude.com/environments)에서 **Create environment**를 클릭하고, **Hosting** 아래에서 **Self-hosted**를 선택하세요. 환경을 열고 **Generate environment key**를 클릭한 후 환경의 `env_…` ID와 키를 복사하세요. 자세한 내용은 Anthropic의 [자체 호스팅 샌드박스](https://platform.claude.com/docs/en/managed-agents/self-hosted-sandboxes) 가이드를 참조하세요.
2. Tuist 계정에 연결하세요:

   ```bash
   curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
     -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
     -d '{
       "anthropic_environment_id": "env_...",
       "environment_key": "<environment key>",
       "anthropic_api_key": "<Anthropic API key>"
     }'
   ```

   `anthropic_api_key`는 선택 사항입니다. 아래 설명대로 Tuist의 API를 통해 세션을 시작할 수 있습니다. Tuist는 두 키를 암호화하여 저장하며 절대 반환하지 않습니다.

1분 이내에 Tuist가 환경의 세션 제공을 시작합니다. `"platform": "darwin"`를 전달하지 않으면 환경은 Linux에서 실행됩니다. 샌드박스 구성을 변경하려면 `vcpus`, `memory_mb` 및 `workspace_gb`를 전달할 수도 있습니다. 자세한 내용은 <.localized_link href="/guides/features/sandboxes#platforms">Linux 및 macOS</.localized_link>를 참조하세요.

### 세션 시작 {#managed-agents-sessions}

세션에서 다른 플랫폼을 요청하지 않는 한, 각 세션은 환경의 플랫폼에서 실행됩니다.

**Claude API 사용** 시, 평소대로 환경 ID로 세션을 생성하고 세션 메타데이터의 `tuist_platform`를 `macos` 또는 `linux`로 설정하세요:

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

`repository_url` 및 선택적으로 `repository_ref`(브랜치 또는 커밋)를 지정하면 에이전트의 첫 번째 턴 전에 Tuist가 공개 리포지토리를 샌드박스로 클론합니다.

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

리포지토리는 Linux에서는 `/workspace`, macOS에서는 `/Users/runner/work`에 체크아웃됩니다. 세션의 샌드박스는 에이전트가 턴을 완료한 후 일시 중지되며 다음 메시지에서 다시 시작됩니다.

> [!WARNING]
> 해당 환경을 소유한 Claude 워크스페이스에서 세션을 생성할 수 있는 사람은 누구나 귀하의 Tuist 계정에서 세션을 실행할 수 있으며, 세션 메타데이터를 통해 macOS를 요청할 수 있습니다. 해당 워크스페이스에 대한 액세스를 적절히 제한하세요.

## Claude Code {#claude-code}

Claude Code 클라우드 세션은 개발자가 [claude.ai/code](https://claude.ai/code), Claude 데스크톱 및 모바일 앱, 그리고 `claude --cloud`에서 시작하는 세션입니다. 세션이 실행될 위치는 환경에 따라 결정되므로, 제공하려는 플랫폼마다 하나의 환경을 연결하세요.

### 환경 연결 {#claude-code-connect}

1. Claude 조직 소유자는 [Cloud environments](https://claude.ai/admin-settings/cloud-environments) 관리자 페이지에서 **Allow self-hosted environments**를 활성화합니다. 이는 Team 또는 Enterprise 플랜이 필요하며, 자세한 내용은 Anthropic의 [자체 호스팅 환경](https://code.claude.com/docs/en/self-hosted-environments) 가이드를 참조하세요.
2. 동일한 페이지에서 개발자가 볼 이름(예: **Tuist Linux** 및 **Tuist macOS**)으로 각 플랫폼별 자체 호스팅 환경을 생성하세요. 각 환경의 `ccpool_…` ID와 한 번만 표시되는 환경 키를 복사하세요.
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

   다른 환경의 ID와 키를 사용하여 `"platform": "linux"`로 반복하세요.

1분 이내에 환경이 세션을 받을 준비가 됩니다. 유휴 세션은 샌드박스를 30분 동안 실행한 후 일시 중지하며, 세션의 다음 메시지는 동일한 샌드박스를 다시 시작합니다. `max_idle_seconds`(최대 3600)로 대기 시간을 변경할 수 있습니다.

### Linux 또는 macOS 선택 {#claude-code-choose}

개발자는 클라우드 세션을 시작할 때 환경과 함께 플랫폼을 선택합니다:

- **claude.ai, 데스크톱 및 모바일 앱:** 새 세션의 환경 선택기에서 **Tuist Linux** 또는 **Tuist macOS**를 선택하세요.
- **Claude Code CLI:** `claude`에서 `/remote-env`를 실행하고 이름으로 환경을 선택하세요. 그러면 `claude --cloud "<task>"`가 해당 환경에서 실행됩니다. 단일 세션용으로 하나를 선택하려면 ID를 전달하세요: `claude --cloud "<task>" --environment ccpool_...`.
- **전체 팀 또는 리포지토리:** Claude Code [설정](https://code.claude.com/docs/en/settings)에서 기본 환경의 ID를 설정하세요. 예를 들어 리포지토리의 `.claude/settings.json`에 설정할 수 있습니다:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

이러한 환경의 세션은 평소대로 조직의 Claude Code 사용량을 사용하며, 해당 샌드박스는 Tuist 계정에 반영됩니다.
