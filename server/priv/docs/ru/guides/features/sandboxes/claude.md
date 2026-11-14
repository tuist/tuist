---
{
  "title": "Claude",
  "titleTemplate": ":title · Песочницы · Возможности · Руководства · Tuist",
  "description": "Запускайте сессии Claude Managed Agents и облачные сессии Claude Code (claude.ai, десктопные и мобильные приложения, а также claude --cloud) в песочницах Tuist на Linux или macOS."
}
---
# Claude {#claude}

> [!IMPORTANT]
> **Только по приглашениям**
>
> Песочницы Tuist, как для Linux, так и для macOS, сейчас доступны только по приглашениям. [Свяжитесь с нами](mailto:contact@tuist.dev) или напишите нам в [Slack-сообществе](https://slack.tuist.dev), чтобы запросить доступ для вашего аккаунта.

Anthropic управляет агентным циклом Claude, а *самостоятельно размещаемая среда* определяет, где запускаются инструменты Claude. Подключите такую среду к Tuist, и каждая сессия в ней получит собственную <.localized_link href="/guides/features/sandboxes">песочницу</.localized_link> Tuist на Linux или macOS. Tuist запускает воркеры и раннеры, необходимые этим средам, поэтому вам не нужно ничего размещать самостоятельно.

Существует два типа сред, по одной для каждого продукта Claude:

- **[Claude Managed Agents](#managed-agents)**: сессии, которые вы запускаете через API Claude или API agent-sessions от Tuist. Вы создаете среду (`env_…`) в [Claude Console](https://platform.claude.com/environments), и каждая сессия может выбирать между Linux и macOS.
- **[Claude Code](#claude-code)**: облачные сессии, которые разработчики запускают из claude.ai, десктопных и мобильных приложений Claude, а также через `claude --cloud`. Владелец команды или предприятия Claude создает среды (`ccpool_…`) в настройках администратора claude.ai, по одной для каждой платформы, а разработчики выбирают Linux или macOS, выбирая соответствующую среду.

Оба типа подключаются через API Tuist администратором аккаунта. Выполните аутентификацию с помощью `tuist auth login`, затем:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### Подключение среды {#managed-agents-connect}

Подключитесь через раздел **Settings → Integrations → Claude** вашего аккаунта. Форма запрашивает самостоятельно размещаемую среду и учетные данные, с которыми Tuist запускает свои сессии:

1. **Создайте среду.** В Claude Console создайте самостоятельно размещаемую среду на странице [Environments](https://platform.claude.com/environments), откройте её и нажмите **Generate environment key**. Anthropic генерирует ключи среды только в Console.
2. **Выберите учетные данные** с помощью селектора в верхней части формы (см. ниже).
3. **Вставьте ID среды и ключ** и выберите платформу и конфигурацию песочниц этой среды.

Tuist проверяет среду с использованием учетных данных перед сохранением, поэтому неверные учетные данные, ID или рабочее пространство приведут к ошибке в форме. Ключи хранятся в зашифрованном виде и больше никогда не отображаются. В течение минуты Tuist начинает обслуживать сессии этой среды. См. <.localized_link href="/guides/features/sandboxes#platforms">Linux и macOS</.localized_link> для описания конфигураций.

#### С использованием API-ключа {#managed-agents-connect-api-key}

Это вариант по умолчанию и самый быстрый способ попробовать песочницы. Вставьте API-ключ с ролью разработчика в рабочем пространстве среды. Интеграция помечает среды, использующие API-ключ; прежде чем полагаться на такой ключ, подключите среду через федеративную идентификацию, чтобы Tuist не хранил долгоживущий ключ.

#### С использованием федеративной идентификации {#managed-agents-connect-federated}

Tuist выполняет аутентификацию через [Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation) от Anthropic, поэтому вам не нужно предоставлять ему API-ключ Anthropic. Вам необходима роль администратора в вашей организации Anthropic.

1. **Доверьтесь Tuist.** Форма показывает URL эмитента и префикс субъекта вашего аккаунта. В Claude Console откройте раздел [Workload identity](https://platform.claude.com/settings/workload-identity-federation), нажмите **Connect workload**, выберите **Custom OIDC** и введите эти данные со скоупом `workspace:developer`. Добавьте сервисный аккаунт, созданный мастером настройки, в рабочее пространство среды.
2. **Введите ID.** ID организации находится в разделе **Settings → Organization**, а ID рабочего пространства — в **Settings → Workspaces**. После завершения подключения рабочего пространства отображаются ID сервисного аккаунта и правила федерации, а страница правила в разделе Workload identity показывает их снова. Ни один из них не является секретом. Если Anthropic отклоняет токен Tuist, причина отображается в [журнале аутентификации](https://platform.claude.com/settings/workload-identity-federation?tab=history) Console.

#### Через API {#managed-agents-connect-api}

Чтобы подключиться из автоматизации, создайте самостоятельно размещаемую среду в [Claude Console](https://platform.claude.com/environments), сгенерируйте её ключ и отправьте оба значения в Tuist:

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

Чтобы запускать сессии через API Tuist, также отправьте либо четыре ID федерации (см. [Подключение без API-ключа](#managed-agents-federation)), либо `anthropic_api_key`. Среда работает на Linux, если вы не передадите `"platform": "darwin"`; параметры `vcpus`, `memory_mb` и `workspace_gb` изменяют конфигурацию её песочниц.

### Запуск сессии {#managed-agents-sessions}

Каждая сессия работает на платформе среды, если только сессия не запрашивает другую.

**Через API Claude** создайте сессию как обычно, указав ID среды, и установите для `tuist_platform` в метаданных сессии значение `macos` или `linux`:

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

`repository_url` и, опционально, `repository_ref` (ветка или коммит) заставляют Tuist клонировать публичный репозиторий в песочницу перед первым ходом агента.

**Через API agent-sessions от Tuist** Tuist создает агента и сессию за вас, а также клонирует приватные репозитории GitHub, подключенные к вашему аккаунту Tuist:

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

Если в аккаунте более одной среды, передайте `agent_environment_id`. Вы можете отслеживать сессию через `GET /agent-sessions/{id}/events`, отвечать через `POST /agent-sessions/{id}/messages` и завершать её через `POST /agent-sessions/{id}/archive`.

Репозиторий извлекается в `/workspace` на Linux и в `/Users/runner/work` на macOS. Песочница сессии приостанавливается после завершения хода агента и возобновляется при следующем сообщении.

> [!WARNING]
> Любой, кто может создавать сессии в рабочем пространстве Claude, владеющем средой, может запускать сессии в вашем аккаунте Tuist и запрашивать macOS через метаданные сессии. Ограничьте доступ к этому рабочему пространству соответствующим образом.

### Подключение без API-ключа {#managed-agents-federation}

Дашборд настраивает это за вас. Через API Tuist работает аналогично: у каждого аккаунта есть собственный эмитент OpenID Connect в Tuist, `https://tuist.dev/oidc/accounts/<account id>`, который подписывает короткоживущий токен для каждого вызова к Anthropic, обменивая его на токен доступа Anthropic, действующий несколько минут. Правило федерации, доверяющее вашему эмитенту, никогда не принимает токены, подписанные Tuist для других аккаунтов.

- Каждый ответ от агентной среды включает `federation_issuer_url` и `federation_subject` (`account:123:agent-environment:456`). В мастере Custom OIDC в Console используйте URL эмитента и либо этот точный субъект, чтобы разрешить доступ только этой среде, либо `account:123:*`, чтобы разрешить доступ всем средам аккаунта. Проверки настройки дашборда используют субъект `account:123:setup`, который принимается только по префиксу. Используйте скоуп `workspace:developer`.
- Отправьте ID организации, рабочего пространства, сервисного аккаунта и правила как `anthropic_organization_id`, `anthropic_workspace_id`, `anthropic_service_account_id` и `anthropic_federation_rule_id` при создании или через `PATCH /agent-environments/{id}`. Если у среды есть и ID, и API-ключ, Tuist использует федерацию.

> [!NOTE]
> Anthropic получает ключи эмитента по HTTPS на порту 443 с публичного хоста. Если ваш самостоятельно размещенный сервер Tuist недоступен из интернета, выберите источник JWKS **inline** в Console и вставьте набор ключей, который ваш сервер отдает по адресу `<issuer>/jwks.json`. Повторяйте эту операцию при каждом изменении ключа подписи Tuist, что происходит при изменении `TUIST_SECRET_KEY_TOKENS` сервера (или, если он не установлен, `TUIST_SECRET_KEY_BASE`).

## Claude Code {#claude-code}

Облачные сессии Claude Code — это те, которые разработчики запускают с [claude.ai/code](https://claude.ai/code), через десктопные и мобильные приложения Claude, а также с помощью `claude --cloud`. Они выбирают место запуска сессии через среду, поэтому подключите по одной среде для каждой платформы, которую хотите предложить.

### Подключение сред {#claude-code-connect}

1. Владелец организации Claude включает опцию **Allow self-hosted environments** на странице администрирования [Cloud environments](https://claude.ai/admin-settings/cloud-environments). Для этого требуется план Team или Enterprise; см. руководство Anthropic по [self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments).
2. На той же странице создайте самостоятельно размещенную среду для каждой платформы с именем, которое увидят разработчики, например **Tuist Linux** и **Tuist macOS**. Скопируйте ID каждой среды `ccpool_…` и ее ключ среды, который отображается только один раз.
3. Подключите каждую среду к своему аккаунту Tuist, установив для `kind` значение `claude_code` и указав платформу:

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

   Повторите то же самое с `"platform": "linux"` и ID и ключом другой среды.

В течение минуты среды будут готовы принимать сессии. Неактивная сессия держит свою песочницу запущенной 30 минут, затем приостанавливает ее; следующее сообщение сессии возобновляет работу той же песочницы. Измените время ожидания с помощью `max_idle_seconds` (до 3600).

### Выбор Linux или macOS {#claude-code-choose}

Разработчики выбирают среду и, соответственно, платформу при запуске облачной сессии:

- **claude.ai, десктопные и мобильные приложения:** выберите **Tuist Linux** или **Tuist macOS** в селекторе среды при создании новой сессии.
- **Claude Code CLI:** выполните `/remote-env` в `claude` и выберите среду по имени. Затем на ней выполняется `claude --cloud "<task>"`. Чтобы выбрать среду для одной сессии, передайте ее ID: `claude --cloud "<task>" --environment ccpool_...`.
- **Вся команда или репозиторий:** установите ID среды по умолчанию в [settings](https://code.claude.com/docs/en/settings) Claude Code, например в файле `.claude/settings.json` репозитория:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

Сессии в этих средах используют квоты Claude Code вашей организации как обычно, а их песочницы учитываются в вашем аккаунте Tuist.

### Более быстрый запуск сессий и сборок {#claude-code-caching}

- **Кэш Tuist:** сессии получают `TUIST_URL` и, если у вашего аккаунта есть кэш в той же стойке, `TUIST_CACHE_ENDPOINT`. CLI Tuist и задачи Mix `tuist_ex` в сессии входят в систему самостоятельно, используя токен идентичности сессии. См. раздел <.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code sessions</.localized_link> в руководстве по аутентификации.
- **Кэшированные извлечения:** когда GitHub-приложение Tuist вашего аккаунта может читать репозиторий сессии, новая сессия начинается с того же кэшированного извлечения, которое используют ваши раннеры Tuist, поэтому она загружает только отсутствующие коммиты вместо полного клонирования. По завершении сессия возвращает объекты последнего коммита ветки по умолчанию, что поддерживает актуальность кэшированного извлечения даже для репозиториев, не использующих CI на Tuist. Обновление происходит только по коммиту, который GitHub сообщает для ветки по умолчанию; собственные ветки сессии никогда не вызывают обновление. Отключите песочницы или удалите приложение, чтобы остановить этот процесс.
- **macOS:** Mac разделяет сессии сборки Claude Code, запускаемые с каждой ВМ, поэтому новой сессии не нужно скачивать их заново.

## Использование Mac из любой сессии Claude Code {#remote-mac}

Сессии Claude Code, работающие на Linux, такие как облачные сессии в среде, размещенной Anthropic, все еще могут собирать и тестировать код для платформ Apple в песочнице Tuist macOS, как описано в разделе <.localized_link href="/guides/features/sandboxes#coding-agents">Build on a Mac from a coding agent</.localized_link>. В отличие от среды **Tuist macOS**, сессия сохраняет свою собственную среду.

В среде **Tuist Linux** ничего настраивать не нужно: CLI Tuist и сервер Tuist MCP уже установлены и входят в систему с использованием идентичности сессии.

Для облачных сессий в среде, размещенной Anthropic:

1. Сделайте сервер Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP server</.localized_link> доступным для сессий: добавьте `https://tuist.dev/mcp` как коннектор в claude.ai и включите его для сессии или объявите его в закоммиченном файле `.mcp.json` репозитория.
2. Установите CLI Tuist в [setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts) среды, например с помощью `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`.
3. Создайте <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> со скоупом `account:sandboxes:write` и добавьте его в [environment variables](https://code.claude.com/docs/en/cloud-environments#set-environment-variables) среды как `TUIST_TOKEN`. Все пользователи среды могут его читать, поэтому не назначайте ему других скоупов.
4. Разрешите среде доступ к Tuist. Стандартный сетевой доступ Anthropic **Trusted** не включает `tuist.dev`, поэтому выберите **Custom**, оставьте домены по умолчанию и добавьте `tuist.dev` в **Allowed domains**. CLI загружает файлы сессии на Mac через `tuist.dev`, поэтому другие домены не требуются.

Claude удаляет Mac после завершения задачи. Оставленный Mac приостанавливается при бездействии и удаляется после 14 дней приостановки. Созданные таким образом Mac учитываются в вашем аккаунте Tuist так же, как и любые другие песочницы.
