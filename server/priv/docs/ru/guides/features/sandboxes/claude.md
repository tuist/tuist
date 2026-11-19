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
> Песочницы Tuist для Linux и macOS сейчас доступны только по приглашениям. [Напишите нам](mailto:contact@tuist.dev) или обратитесь в [Slack-сообщество](https://slack.tuist.dev), чтобы запросить доступ для вашего аккаунта.

Anthropic запускает агентный цикл Claude, а *собственная среда выполнения* определяет, где работают инструменты Claude. Подключите такую среду к Tuist, и каждая сессия в ней получит собственную <.localized_link href="/guides/features/sandboxes">песочницу</.localized_link> Tuist на Linux или macOS. Tuist запускает необходимые воркеры и раннеры, поэтому вам не нужно ничего хостить самостоятельно.

Есть два типа сред — по одной для каждого продукта Claude:

- **[Claude Managed Agents](#managed-agents)**: сессии, которые вы запускаете через API Claude или API agent-sessions от Tuist. Вы создаёте среду (`env_…`) в [Claude Console](https://platform.claude.com/environments), и для каждой сессии можно выбрать Linux или macOS.
- **[Claude Code](#claude-code)**: облачные сессии, которые разработчики запускают из claude.ai, десктопного и мобильного приложений Claude, а также через `claude --cloud`. Владелец организации Claude Team или Enterprise создаёт среды (`ccpool_…`) в настройках администратора claude.ai — по одной для каждой платформы, а разработчики выбирают Linux или macOS, выбирая соответствующую среду.

Оба типа подключаются через API Tuist администратором аккаунта. Выполните аутентификацию с помощью `tuist auth login`, затем:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### Подключение среды {#managed-agents-connect}

Подключитесь через раздел аккаунта **Settings → Integrations → Claude**. Форма запрашивает собственную среду выполнения и учётные данные, с которыми Tuist будет запускать сессии:

1. **Создайте среду.** В Claude Console перейдите на страницу [Environments](https://platform.claude.com/environments), создайте собственную среду, откройте её и нажмите **Generate environment key**. Anthropic генерирует ключи среды только в Console.
2. **Выберите учётные данные** с помощью селектора в верхней части формы (см. ниже).
3. **Вставьте ID среды и ключ** и выберите платформу и конфигурацию песочниц этой среды.

Tuist проверяет среду с указанными учётными данными до сохранения, поэтому неверные учётные данные, ID или рабочее пространство приведут к ошибке в форме. Ключи хранятся в зашифрованном виде и больше не отображаются. В течение минуты Tuist начинает обслуживать сессии этой среды. Конфигурации описаны в разделе <.localized_link href="/guides/features/sandboxes#platforms">Linux and macOS</.localized_link>.

#### С использованием API-ключа {#managed-agents-connect-api-key}

Это вариант по умолчанию и самый быстрый способ попробовать песочницы. Вставьте API-ключ с ролью разработчика в рабочем пространстве среды. Интеграция помечает среды, использующие API-ключ; прежде чем полагаться на такой ключ, подключите среду через федеративную идентификацию, чтобы Tuist не хранил долгоживущий ключ.

#### С использованием федеративной идентификации {#managed-agents-connect-federated}

Tuist аутентифицируется через [Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation) от Anthropic, поэтому вам не нужно передавать ему API-ключ Anthropic. Вам потребуется роль администратора в вашей организации Anthropic.

1. **Доверьтесь Tuist.** Форма показывает URL эмитента и префикс субъекта вашего аккаунта. В Claude Console откройте [Workload identity](https://platform.claude.com/settings/workload-identity-federation), нажмите **Connect workload**, выберите **Custom OIDC** и укажите их со скоупом `workspace:developer`. Добавьте сервисный аккаунт, созданный мастером настройки, в рабочее пространство среды.
2. **Укажите ID.** ID организации находится в разделе **Settings → Organization**, а ID рабочего пространства — в **Settings → Workspaces**. После завершения подключения рабочей нагрузки отображаются ID сервисного аккаунта и правила федерации, а страница правила в разделе Workload identity показывает их повторно. Ни один из них не является секретом. Если Anthropic отклоняет токен Tuist, причина отображается в [журнале аутентификации](https://platform.claude.com/settings/workload-identity-federation?tab=history) Console.

#### Через API {#managed-agents-connect-api}

Чтобы подключить среду из автоматизации, создайте собственную среду в [Claude Console](https://platform.claude.com/environments), сгенерируйте её ключ и отправьте оба значения в Tuist:

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

Чтобы запускать сессии через API Tuist, также передайте либо четыре ID федерации (см. [Подключение без API-ключа](#managed-agents-federation)), либо `anthropic_api_key`. Среда работает на Linux, если вы не передали `"platform": "darwin"`; параметры `vcpus`, `memory_mb` и `workspace_gb` изменяют конфигурацию её песочниц, а `xcode_version` — версию [Xcode](#xcode) для macOS-песочниц.

### Запуск сессии {#managed-agents-sessions}

Каждая сессия выполняется на платформе среды, если сессия явно не запрашивает другую.

**Через API Claude** создайте сессию как обычно, указав ID среды, и установите в метаданных сессии параметр `tuist_platform` в значение `macos` или `linux`:

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

**Через API agent-sessions от Tuist** Tuist сам создаёт агента и сессию, а также клонирует приватные GitHub-репозитории, подключённые к вашему аккаунту Tuist:

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

Если в аккаунте несколько сред, передайте `agent_environment_id`. Вы можете отслеживать сессию через `GET /agent-sessions/{id}/events`, отвечать на сообщения через `POST /agent-sessions/{id}/messages` и завершать её через `POST /agent-sessions/{id}/archive`.

Репозиторий клонируется в `/workspace` на Linux и в `/Users/runner/work` на macOS. Песочница сессии приостанавливается после завершения хода агента и возобновляется при следующем сообщении.

### Выбор версии Xcode для сессии {#managed-agents-xcode}

macOS-машина сессии загружается до того, как Claude запустит любой инструмент, поэтому Claude не может самостоятельно выбрать Xcode. Тот, кто создаёт сессию, выбирает версию так же, как выбирает macOS. Tuist использует первый из следующих параметров, который задан:

1. `xcode_version` в API agent-sessions от Tuist рядом с `platform`. Если указана версия, которую Tuist не предоставляет, при создании сессии будет отказ с перечнем доступных версий.
2. `tuist_xcode_version` в метаданных сессии, когда вы создаёте сессию через API Claude:

   ```json
   "metadata": { "tuist_platform": "macos", "tuist_xcode_version": "26.1.1" }
   ```

3. `xcode_version` среды, когда сессия выполняется на платформе этой среды.
4. Версия Xcode по умолчанию.

Если Xcode указан без платформы, подразумевается macOS. Несколько важных моментов:

- **Сессия сохраняет выбранную версию Xcode.** Её песочница загружается один раз, и последующие сообщения или изменения метаданных не меняют версию. Для другой версии Xcode используйте новую сессию.
- **Tuist проверяет метаданные при поступлении первого хода.** Если `tuist_xcode_version` указывает версию Xcode, которую Tuist не предоставляет, Tuist останавливает этот ход, не запуская песочницу, и логирует доступные версии. Чтобы получить ошибку сразу при создании сессии, используйте API agent-sessions от Tuist.
- **В среде macOS Tuist ожидает данные, а не делает предположений.** Если Tuist не может прочитать метаданные новой сессии, он приостанавливает ход и повторяет попытку вместо загрузки Xcode среды.

> [!WARNING]
> Любой пользователь, который может создавать сессии в рабочем пространстве Claude, владеющем средой, может запускать сессии от вашего аккаунта Tuist и запрашивать macOS и её версию Xcode через метаданные сессии. Ограничьте доступ к этому рабочему пространству соответствующим образом.

### Подключение без API-ключа {#managed-agents-federation}

Панель управления настраивает это за вас. Через API Tuist работает аналогично: у каждого аккаунта есть собственный эмитент OpenID Connect в Tuist, `https://tuist.dev/oidc/accounts/<account id>`, который подписывает краткосрочный токен для каждого вызова к Anthropic и обменивает его на токен доступа Anthropic, действующий несколько минут. Правило федерации, доверяющее вашему эмитенту, никогда не принимает токены, подписанные Tuist для других аккаунтов.

- Каждый ответ от среды агента включает `federation_issuer_url` и `federation_subject` (`account:123:agent-environment:456`). В мастере Custom OIDC консоли используйте URL эмитента и либо этот точный subject, чтобы разрешить доступ только этой среде, либо `account:123:*`, чтобы разрешить доступ всем средам аккаунта. Проверки настройки панели управления используют subject `account:123:setup`, который допускает только префикс. Используйте область видимости `workspace:developer`.
- Отправляйте идентификаторы организации, рабочего пространства, сервисного аккаунта и правила как `anthropic_organization_id`, `anthropic_workspace_id`, `anthropic_service_account_id` и `anthropic_federation_rule_id` при создании или через `PATCH /agent-environments/{id}`. Если у среды есть и идентификаторы, и API-ключ, Tuist использует федерацию.

> [!NOTE]
> Anthropic получает ключи эмитента по HTTPS на порту 443 с публичного хоста. Если ваш самостоятельно размещённый сервер Tuist недоступен из интернета, выберите источник JWKS **inline** в консоли и вставьте набор ключей, который ваш сервер отдаёт по адресу `<issuer>/jwks.json`. Повторяйте эту операцию при каждом изменении ключа подписи Tuist, что происходит при изменении `TUIST_SECRET_KEY_TOKENS` сервера (или, если он не задан, `TUIST_SECRET_KEY_BASE`).

## Claude Code {#claude-code}

Облачные сессии Claude Code — это те, которые разработчики запускают с [claude.ai/code](https://claude.ai/code), из настольных и мобильных приложений Claude и через `claude --cloud`. Они выбирают место выполнения сессии через среду, поэтому подключите по одной среде для каждой платформы, которую хотите предложить.

### Подключение сред {#claude-code-connect}

1. Владелец организации Claude включает опцию **Allow self-hosted environments** на странице администрирования [Cloud environments](https://claude.ai/admin-settings/cloud-environments). Для этого требуется план Team или Enterprise; см. руководство Anthropic по [self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments).
2. На той же странице создайте самостоятельно размещённую среду для каждой платформы с именем, которое увидят разработчики, например **Tuist Linux** и **Tuist macOS**. Скопируйте ID каждой среды `ccpool_…` и её ключ среды, который показывается только один раз.
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

В течение минуты среды будут готовы принимать сессии. Неактивная сессия держит свою песочницу запущенной 30 минут, затем приостанавливает её; следующее сообщение сессии возобновляет работу той же песочницы. Измените время ожидания через `max_idle_seconds` (до 3600).

### Выбор Linux или macOS {#claude-code-choose}

Разработчики выбирают среду и, соответственно, платформу при запуске облачной сессии:

- **claude.ai, настольные и мобильные приложения:** выберите **Tuist Linux** или **Tuist macOS** в селекторе среды новой сессии.
- **Claude Code CLI:** выполните `/remote-env` в `claude` и выберите среду по имени. Затем `claude --cloud "<task>"` будет выполняться в ней. Чтобы выбрать среду для одной сессии, передайте её ID: `claude --cloud "<task>" --environment ccpool_...`.
- **Вся команда или репозиторий:** установите ID среды по умолчанию в [settings](https://code.claude.com/docs/en/settings) Claude Code, например в `.claude/settings.json` репозитория:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

Сессии в этих средах используют квоты Claude Code вашей организации как обычно, а их песочницы учитываются в лимитах вашего аккаунта Tuist.

### Выбор версии Xcode {#xcode}

Каждая среда macOS загружает одну версию <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>, по умолчанию, если вы не подключили её с указанием `xcode_version`, например `"xcode_version": "26.1.1"`. Чтобы предложить несколько версий, подключите отдельную среду для каждой и назовите их соответственно, например **Tuist macOS · Xcode 26.1.1**. Разработчики затем выбирают Xcode, выбирая среду.

Чтобы перевести среду на другую версию Xcode, обновите её:

```bash
curl -X PATCH "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments/<id>" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{ "xcode_version": "27.0" }'
```

Новые сессии получают новую версию Xcode, а сессии, у которых уже есть песочница, сохраняют свою. `null` возвращает к версии по умолчанию. То же самое относится к средам Managed Agents, сессии которых также могут [выбирать свою версию](#managed-agents-xcode).

### Быстрый запуск сессий и сборок {#claude-code-caching}

- **Кэш Tuist:** сессии получают `TUIST_URL` и, если у вашего аккаунта есть кэш в том же стойке, `TUIST_CACHE_ENDPOINT`. CLI Tuist и задачи Mix `tuist_ex` в сессии самостоятельно входят в систему, используя токен идентичности сессии. См. раздел <.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code sessions</.localized_link> в руководстве по аутентификации.
- **Кэшированные клоны:** когда приложение Tuist GitHub вашего аккаунта может читать репозиторий сессии, новая сессия начинается с того же кэшированного клона, который используют ваши раннеры Tuist, поэтому она загружает только отсутствующие коммиты вместо полного клонирования. По завершении сессия возвращает объекты последнего коммита ветки по умолчанию, что поддерживает актуальность кэшированного клона даже для репозиториев, не использующих CI на Tuist. Обновление происходит только по коммиту, который GitHub сообщает для ветки по умолчанию; собственные ветки сессии никогда не обновляют кэш. Отключите песочницы или удалите приложение, чтобы остановить это.
- **macOS:** Mac разделяет сборки сессий Claude Code, запускаемые с каждой ВМ, поэтому новая сессия не загружает их заново.

## Использование Mac из любой сессии Claude Code {#remote-mac}

Сессии Claude Code, работающие на Linux, такие как облачные сессии в среде, размещённой Anthropic, всё ещё могут собирать и тестировать код для платформ Apple в песочнице macOS Tuist, как описано в разделе <.localized_link href="/guides/features/sandboxes#coding-agents">Build on a Mac from a coding agent</.localized_link>. В отличие от среды **Tuist macOS**, сессия сохраняет свою собственную среду.

В среде **Tuist Linux** ничего настраивать не нужно: CLI Tuist и сервер Tuist MCP уже установлены и входят в систему с использованием идентичности сессии.

Для облачных сессий в среде, размещённой Anthropic:

1. Сделайте сервер Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP server</.localized_link> доступным для сессий: добавьте `https://tuist.dev/mcp` как коннектор в claude.ai и включите его для сессии или объявите его в закоммиченном файле `.mcp.json` репозитория.
2. Установите CLI Tuist в [setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts) среды, например с помощью `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`.
3. Создайте <.localized_link href="/guides/server/authentication#account-tokens">токен аккаунта</.localized_link> с областью доступа `account:sandboxes:write` и добавьте его в [переменные окружения](https://code.claude.com/docs/en/cloud-environments#set-environment-variables) среды как `TUIST_TOKEN`. Любой пользователь среды может прочитать этот токен, поэтому не назначайте ему других областей доступа, если только этим пользователям не разрешено использовать ваш кэш: команды на Mac получают доступ к <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">кэшу</.localized_link> только в пределах прав токена, поэтому добавьте `ci`, чтобы сборки на Mac могли читать и записывать данные в ваш кэш.
4. Разрешите среде обращаться к Tuist. Стандартный сетевой доступ Anthropic с настройкой **Trusted** не включает `tuist.dev`, поэтому выберите **Custom**, оставьте домены по умолчанию и добавьте `tuist.dev` в раздел **Allowed domains**. CLI загружает файлы сессии на Mac через `tuist.dev`, поэтому другие домены не требуются.

После первой синхронизации Claude выполняет `mise install` в корневой директории репозитория на Mac для установки закрепленной версии Tuist проекта; начиная с Tuist 4.218.0, каждая команда самостоятельно входит в кэш вашего аккаунта.

Claude удаляет Mac после завершения задачи. Оставшийся без дела Mac переходит в режим паузы и удаляется после 14 дней простоя. Маки, созданные таким образом, учитываются в вашем аккаунте Tuist так же, как и любые другие песочницы.
