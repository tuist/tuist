---
{
  "title": "Claude",
  "titleTemplate": ":title · Песочницы · Возможности · Руководства · Tuist",
  "description": "Запускайте сессии Claude Managed Agents и облачные сессии Claude Code (claude.ai, настольные и мобильные приложения, а также claude --cloud) в песочницах Tuist на Linux или macOS."
}
---
# Claude {#claude}

> [!IMPORTANT]
> **Только по приглашениям**
>
> Песочницы Tuist для Linux и macOS сейчас доступны только по приглашениям. [Свяжитесь с нами](mailto:contact@tuist.dev) или напишите нам в [Slack-сообществе](https://slack.tuist.dev), чтобы запросить доступ к вашему аккаунту.

Anthropic запускает цикл агента Claude, а *самостоятельно размещаемая среда* определяет, где работают инструменты Claude. Подключите такую среду к Tuist, и каждая сессия в ней получит собственную <.localized_link href="/guides/features/sandboxes">песочницу</.localized_link> Tuist на Linux или macOS. Tuist запускает необходимые воркеры и раннеры, поэтому вам не нужно ничего хостить самостоятельно.

Есть два типа сред — по одной для каждого продукта Claude:

- **[Claude Managed Agents](#managed-agents)**: сессии, которые вы запускаете через API Claude или API agent-sessions от Tuist. Вы создаёте среду (`env_…`) в [Claude Console](https://platform.claude.com/environments), и каждая сессия может выбрать Linux или macOS.
- **[Claude Code](#claude-code)**: облачные сессии, которые разработчики запускают с claude.ai, из десктопных и мобильных приложений Claude, а также через `claude --cloud`. Владелец организации Claude Team или Enterprise создаёт среды (`ccpool_…`) в настройках администратора claude.ai — по одной для каждой платформы, а разработчики выбирают Linux или macOS, выбирая соответствующую среду.

Обе среды подключаются через API Tuist администратором аккаунта. Выполните аутентификацию с помощью `tuist auth login`, затем:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### Подключение среды {#managed-agents-connect}

1. В [Claude Console](https://platform.claude.com/environments) нажмите **Create environment** и в разделе **Hosting** выберите **Self-hosted**. Откройте среду, нажмите **Generate environment key** и скопируйте ID среды `env_…` и ключ. Подробности см. в руководстве Anthropic по [самостоятельно размещаемым песочницам](https://platform.claude.com/docs/en/managed-agents/self-hosted-sandboxes).
2. Подключите её к своему аккаунту Tuist:

   ```bash
   curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
     -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
     -d '{
       "anthropic_environment_id": "env_...",
       "environment_key": "<environment key>",
       "anthropic_api_key": "<Anthropic API key>"
     }'
   ```

   `anthropic_api_key` необязателен. Он позволяет запускать сессии через API Tuist, как описано ниже. Tuist хранит оба ключа в зашифрованном виде и никогда не возвращает их.

В течение минуты Tuist начнёт обслуживать сессии этой среды. Среда работает на Linux, если вы не передадите `"platform": "darwin"`. Также можно передать `vcpus`, `memory_mb` и `workspace_gb`, чтобы изменить конфигурацию песочниц; см. <.localized_link href="/guides/features/sandboxes#platforms">Linux и macOS</.localized_link>.

### Запуск сессии {#managed-agents-sessions}

Каждая сессия работает на платформе среды, если сессия явно не запрашивает другую.

**Через API Claude** создайте сессию как обычно, указав ID среды, и установите `tuist_platform` в метаданных сессии в значение `macos` или `linux`:

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

`repository_url` и, опционально, `repository_ref` (ветка или коммит) заставляют Tuist клонировать публичный репозиторий в песочницу до первого хода агента.

**Через API agent-sessions от Tuist** Tuist сам создаёт агента и сессию, а также клонирует приватные репозитории GitHub, подключённые к вашему аккаунту Tuist:

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

Если у аккаунта больше одной среды, передайте `agent_environment_id`. Вы можете отслеживать сессию через `GET /agent-sessions/{id}/events`, отвечать через `POST /agent-sessions/{id}/messages` и завершать её через `POST /agent-sessions/{id}/archive`.

Репозиторий проверяется в `/workspace` на Linux и в `/Users/runner/work` на macOS. Песочница сессии приостанавливается после завершения хода агента и возобновляется при следующем сообщении.

> [!WARNING]
> Любой, кто может создавать сессии в рабочем пространстве Claude, владеющем средой, может запускать сессии в вашем аккаунте Tuist и запрашивать macOS через метаданные сессии. Ограничьте доступ к этому рабочему пространству соответствующим образом.

## Claude Code {#claude-code}

Облачные сессии Claude Code — это те, которые разработчики запускают с [claude.ai/code](https://claude.ai/code), из десктопных и мобильных приложений Claude, а также через `claude --cloud`. Они выбирают, где будет работать сессия, через среду, поэтому подключите по одной среде для каждой платформы, которую хотите предложить.

### Подключение сред {#claude-code-connect}

1. Владелец организации Claude включает **Allow self-hosted environments** на странице администрирования [Cloud environments](https://claude.ai/admin-settings/cloud-environments). Для этого нужен план Team или Enterprise; см. руководство Anthropic по [самостоятельно размещаемым средам](https://code.claude.com/docs/en/self-hosted-environments).
2. На той же странице создайте самостоятельно размещаемую среду для каждой платформы с именем, которое увидят разработчики, например **Tuist Linux** и **Tuist macOS**. Скопируйте ID каждой среды `ccpool_…` и её ключ среды, который показывается только один раз.
3. Подключите каждую среду к своему аккаунту Tuist, установив `kind` в значение `claude_code` и указав платформу:

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

   Повторите с `"platform": "linux"` и ID и ключом другой среды.

В течение минуты среды будут готовы принимать сессии. Неактивная сессия держит свою песочницу запущенной 30 минут, затем приостанавливает её; следующее сообщение сессии возобновляет ту же песочницу. Измените время ожидания через `max_idle_seconds` (до 3600).

### Выбор Linux или macOS {#claude-code-choose}

Разработчики выбирают среду, а вместе с ней и платформу, при запуске облачной сессии:

- **claude.ai, десктопные и мобильные приложения:** выберите **Tuist Linux** или **Tuist macOS** в выборе среды при создании новой сессии.
- **Claude Code CLI:** выполните `/remote-env` в `claude` и выберите среду по имени. Затем `claude --cloud "<task>"` будет работать в ней. Чтобы выбрать среду для одной сессии, передайте её ID: `claude --cloud "<task>" --environment ccpool_...`.
- **Для всей команды или репозитория:** установите ID среды по умолчанию в [настройках](https://code.claude.com/docs/en/settings) Claude Code, например в `.claude/settings.json` репозитория:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

Сессии в этих средах используют квоты Claude Code вашей организации как обычно, а их песочницы учитываются в вашем аккаунте Tuist.
