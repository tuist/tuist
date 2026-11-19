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
> Песочницы Tuist, как для Linux, так и для macOS, сейчас доступны только по приглашениям. [Напишите нам](mailto:contact@tuist.dev) или обратитесь в [Slack-сообщество](https://slack.tuist.dev), чтобы запросить доступ для вашего аккаунта.

Anthropic управляет циклом работы агента Claude, а *самостоятельно размещаемая среда* определяет, где запускаются инструменты Claude. Подключите такую среду к Tuist, и каждая сессия в ней получит собственную <.localized_link href="/guides/features/sandboxes">песочницу</.localized_link> Tuist на Linux или macOS. Tuist запускает необходимые воркеры и раннеры для этих сред, поэтому вам не нужно ничего хостить самостоятельно.

Существует два типа сред — по одной для каждого продукта Claude:

- **[Claude Managed Agents](#managed-agents)**: сессии, которые вы запускаете через API Claude или API агентских сессий Tuist. Вы создаете среду (`env_…`) в [Claude Console](https://platform.claude.com/environments), и каждая сессия может выбирать Linux или macOS.
- **[Claude Code](#claude-code)**: облачные сессии, которые разработчики запускают из claude.ai, десктопных и мобильных приложений Claude, а также через `claude --cloud`. Владелец команды или предприятия Claude создает среды (`ccpool_…`) в настройках администратора claude.ai — по одной для каждой платформы, а разработчики выбирают Linux или macOS, выбирая соответствующую среду.

Оба типа подключаются через API Tuist администратором аккаунта. Выполните аутентификацию с помощью `tuist auth login`, затем:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### Подключение среды {#managed-agents-connect}

Подключите через раздел вашего аккаунта **Settings → Integrations → Claude**. Форма запрашивает самостоятельно размещаемую среду и учетные данные, с которыми Tuist будет запускать сессии:

1. **Создайте среду.** В Claude Console создайте самостоятельно размещаемую среду на странице [Environments](https://platform.claude.com/environments), откройте её и нажмите **Generate environment key**. Anthropic генерирует ключи среды только в Console.
2. **Выберите учетные данные** с помощью селектора в верхней части формы (см. ниже).
3. **Вставьте ID среды и ключ** и выберите платформу и конфигурацию песочниц этой среды.

Tuist получает информацию о среде с использованием учетных данных перед сохранением, поэтому неверные учетные данные, ID или рабочее пространство приведут к ошибке в форме. Ключи хранятся в зашифрованном виде и больше не отображаются. В течение минуты Tuist начинает обслуживать сессии этой среды. См. <.localized_link href="/guides/features/sandboxes#platforms">Linux и macOS</.localized_link> для описания доступных конфигураций.

#### С использованием API-ключа {#managed-agents-connect-api-key}

Это вариант по умолчанию и самый быстрый способ попробовать песочницы. Вставьте API-ключ с ролью разработчика в рабочем пространстве среды. Интеграция помечает среды, использующие API-ключ; прежде чем полагаться на такой ключ, подключите среду через федеративную идентичность, чтобы Tuist не хранил долгоживущий ключ.

#### С использованием федеративной идентичности {#managed-agents-connect-federated}

Tuist аутентифицируется через [Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation) от Anthropic, поэтому вам не нужно передавать ему API-ключ Anthropic. Вам потребуется роль администратора в вашей организации Anthropic.

1. **Доверьтесь Tuist.** Форма показывает URL эмитента и префикс субъекта вашего аккаунта. В Claude Console откройте [Workload identity](https://platform.claude.com/settings/workload-identity-federation), нажмите **Connect workload**, выберите **Custom OIDC** и введите эти данные со скоупом `workspace:developer`. Добавьте сервисный аккаунт, созданный мастером настройки, в рабочее пространство среды.
2. **Введите ID.** ID организации находится в разделе **Settings → Organization**, а ID рабочего пространства — в **Settings → Workspaces**. После завершения подключения рабочей нагрузки отображаются ID сервисного аккаунта и правила федерации, а страница правила в Workload identity показывает их снова. Ни один из них не является секретом. Если Anthropic отклоняет токен Tuist, причина отображается в [журнале аутентификации](https://platform.claude.com/settings/workload-identity-federation?tab=history) Console.

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

Для запуска сессий через API Tuist также отправьте либо четыре ID федерации (см. [Подключение без API-ключа](#managed-agents-federation)), либо `anthropic_api_key`. Среда работает на Linux, если вы не передадите `"platform": "darwin"`; `vcpus`, `memory_mb` и `workspace_gb` изменяют конфигурацию её песочниц, а `xcode_version` — версию [Xcode](#xcode) для её macOS-песочниц.

### Запуск сессии {#managed-agents-sessions}

Каждая сессия выполняется на платформе среды, если сессия не запрашивает другую.

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

**Через API агентских сессий Tuist** Tuist создает агента и сессию за вас, а также клонирует приватные репозитории GitHub, подключенные к вашему аккаунту Tuist:

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

Если у аккаунта более одной среды, передайте `agent_environment_id`. Вы можете отслеживать сессию через `GET /agent-sessions/{id}/events`, отвечать через `POST /agent-sessions/{id}/messages` и завершать её через `POST /agent-sessions/{id}/archive`.

Репозиторий проверяется в `/workspace` на Linux и в `/Users/runner/work` на macOS. Песочница сессии приостанавливается после завершения хода агента и возобновляется при следующем сообщении.

### Выбор версии Xcode для сессии {#managed-agents-xcode}

Mac сессии загружается до того, как Claude запустит любой инструмент, поэтому Claude не может выбрать свою версию Xcode. Тот, кто создает сессию, выбирает её так же, как выбирает macOS. Tuist использует первый из следующих установленных параметров:

1. `xcode_version` в API агентских сессий Tuist, рядом с `platform`. Версия, которую Tuist не предлагает, будет отклонена при создании сессии, с перечнем доступных для выбора версий.
2. `tuist_xcode_version` в метаданных сессии, когда вы создаете сессию через API Claude:

   ```json
   "metadata": { "tuist_platform": "macos", "tuist_xcode_version": "26.1.1" }
   ```

3. `xcode_version` среды, когда сессия выполняется на платформе этой среды.
4. Версия Xcode по умолчанию.

Xcode без указания платформы подразумевает macOS. Несколько важных моментов:

- **Сессия сохраняет свою версию Xcode.** Её песочница загружается один раз, и последующие сообщения или измененные метаданные не меняют её. Для другой версии Xcode используйте новую сессию.
- **Tuist проверяет метаданные при поступлении первого хода.** Если `tuist_xcode_version` указывает на версию Xcode, которую Tuist не предлагает, Tuist останавливает этот ход без запуска песочницы и логирует доступные для выбора версии. Используйте API агентских сессий Tuist, чтобы получить ошибку при создании сессии.
- **В среде macOS Tuist ожидает, а не угадывает.** Если Tuist не может прочитать метаданные новой сессии, он приостанавливает ход и повторяет попытку вместо загрузки Xcode среды.

> [!WARNING]
> Любой, кто может создавать сессии в рабочем пространстве Claude, которому принадлежит среда, может запускать сессии от имени вашего аккаунта Tuist и запрашивать macOS и её версию Xcode через метаданные сессии. Ограничьте доступ к этому рабочему пространству соответствующим образом.

### Подключение без API-ключа {#managed-agents-federation}

Панель управления настраивает это за вас. Через API Tuist работает аналогично: у каждого аккаунта есть собственный эмитент OpenID Connect в Tuist, `https://tuist.dev/oidc/accounts/<account id>`, который подписывает краткосрочный токен для каждого вызова к Anthropic, обменивая его на токен доступа Anthropic, действующий несколько минут. Правило федерации, доверяющее вашему эмитенту, никогда не принимает токены, подписанные Tuist для других аккаунтов.

- Каждый ответ среды агента включает `federation_issuer_url` и `federation_subject` (`account:123:agent-environment:456`). В мастере Custom OIDC консоли используйте URL эмитента и либо точное значение субъекта, чтобы разрешить доступ только этой среде, либо `account:123:*`, чтобы разрешить доступ ко всем средам аккаунта. Проверки настройки панели управления используют субъект `account:123:setup`, который допускается только по префиксу. Используйте область видимости `workspace:developer`.
- Передавайте идентификаторы организации, рабочего пространства, сервисного аккаунта и правила как `anthropic_organization_id`, `anthropic_workspace_id`, `anthropic_service_account_id` и `anthropic_federation_rule_id` при создании или через `PATCH /agent-environments/{id}`. Если у среды есть как идентификаторы, так и API-ключ, Tuist использует федерацию.

> [!NOTE]
> Anthropic получает ключи эмитента по HTTPS через порт 443 с публичного хоста. Если ваш самостоятельно размещенный сервер Tuist недоступен из интернета, выберите источник JWKS **inline** в консоли и вставьте набор ключей, который ваш сервер отдает по адресу `<issuer>/jwks.json`. Повторяйте эту операцию при каждом изменении ключа подписи Tuist, что происходит при изменении `TUIST_SECRET_KEY_TOKENS` сервера (или, если он не установлен, `TUIST_SECRET_KEY_BASE`).

## Claude Code {#claude-code}

Облачные сессии Claude Code — это те, которые разработчики запускают с [claude.ai/code](https://claude.ai/code), из настольных и мобильных приложений Claude, а также через `claude --cloud`. Они выбирают место выполнения сессии через среду, поэтому подключите по одной среде для каждой платформы, которую хотите предложить.

### Подключение сред {#claude-code-connect}

1. Владелец организации Claude включает опцию **Allow self-hosted environments** на странице администрирования [Cloud environments](https://claude.ai/admin-settings/cloud-environments). Для этого требуется план Team или Enterprise; см. руководство Anthropic по [self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments).
2. На той же странице создайте самостоятельно размещенную среду для каждой платформы с именем, которое увидят разработчики, например **Tuist Linux** и **Tuist macOS**. Скопируйте ID `ccpool_…` каждой среды и её ключ среды, который показывается только один раз.
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

В течение минуты среды будут готовы принимать сессии. Неактивная сессия поддерживает работу своей песочницы в течение 30 минут, затем приостанавливает её; следующее сообщение сессии возобновляет работу той же песочницы. Измените время ожидания через `max_idle_seconds` (до 3600).

### Выбор Linux или macOS {#claude-code-choose}

Разработчики выбирают среду, а вместе с ней и платформу, при запуске облачной сессии:

- **claude.ai, настольные и мобильные приложения:** выберите **Tuist Linux** или **Tuist macOS** в селекторе среды новой сессии.
- **Claude Code CLI:** выполните `/remote-env` в `claude` и выберите среду по имени. Затем `claude --cloud "<task>"` будет выполняться в ней. Чтобы выбрать среду для одной сессии, передайте её ID: `claude --cloud "<task>" --environment ccpool_...`.
- **Вся команда или репозиторий:** установите ID среды по умолчанию в [settings](https://code.claude.com/docs/en/settings) Claude Code, например в `.claude/settings.json` репозитория:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

Сессии в этих средах используют квоты Claude Code вашей организации как обычно, а их песочницы учитываются в лимитах вашего аккаунта Tuist.

### Выбор версии Xcode {#xcode}

Каждая среда macOS загружает одну версию <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>, по умолчанию, если вы не подключили её с указанием `xcode_version`, например `"xcode_version": "26.1.1"`. Чтобы предложить несколько версий, подключите отдельную среду для каждой и назовите их соответственно, например **Tuist macOS · Xcode 26.1.1**. Разработчики затем выбирают версию Xcode, выбирая среду.

Чтобы перевести среду на другую версию Xcode, обновите её:

```bash
curl -X PATCH "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments/<id>" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{ "xcode_version": "27.0" }'
```

Новые сессии получают новую версию Xcode, а сессии, у которых уже есть песочница, сохраняют свою. `null` возвращает к значению по умолчанию. То же самое относится к средам Managed Agents, сессии которых также могут [выбирать свою версию](#managed-agents-xcode).

### Более быстрый запуск сессий и сборок {#claude-code-caching}

- **Кэш Tuist:** сессии получают `TUIST_URL` и, если у вашего аккаунта есть кэш в той же стойке, `TUIST_CACHE_ENDPOINT`. CLI Tuist и задачи Mix `tuist_ex` в сессии самостоятельно входят в систему, используя токен идентичности сессии. См. раздел <.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code sessions</.localized_link> в руководстве по аутентификации.
- **Кэшированные проверки:** когда приложение Tuist GitHub вашего аккаунта может читать репозиторий сессии, новая сессия начинается с той же кэшированной проверки, которую используют раннеры Tuist, поэтому она загружает только отсутствующие коммиты вместо полного клонирования. По завершении сессии она возвращает объекты последнего коммита ветки по умолчанию, что поддерживает актуальность кэшированной проверки даже для репозиториев, не запускающих CI на Tuist. Обновление происходит только по коммиту, который GitHub сообщает для ветки по умолчанию; собственные ветки сессии никогда не вызывают обновление. Отключите песочницы или удалите приложение, чтобы остановить этот процесс.
- **macOS:** Mac разделяет сборки сеансов Claude Code с каждой ВМ, поэтому новая сессия не загружает их заново.

## Использование Mac из любой сессии Claude Code {#remote-mac}

Сессии Claude Code, работающие на Linux, такие как облачные сессии в среде, размещенной Anthropic, все еще могут собирать и тестировать код для платформ Apple в песочнице Tuist macOS, как описано в разделе <.localized_link href="/guides/features/sandboxes#coding-agents">Build on a Mac from a coding agent</.localized_link>. В отличие от среды **Tuist macOS**, сессия сохраняет свою собственную среду.

В среде **Tuist Linux** ничего настраивать не нужно: CLI Tuist и сервер Tuist MCP уже установлены и входят в систему с использованием идентичности сессии.

Для облачных сессий в среде, размещенной Anthropic:

1. Сделайте <.localized_link href="/guides/features/agentic-coding/mcp">MCP server</.localized_link> Tuist доступным для сессий: добавьте `https://tuist.dev/mcp` как коннектор в claude.ai и включите его для сессии или объявите его в закоммиченном файле `.mcp.json` репозитория.
2. Установите CLI Tuist в [setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts) среды, например с помощью `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`.
3. Создайте <.localized_link href="/guides/server/authentication#account-tokens">токен аккаунта</.localized_link> с областью доступа `account:sandboxes:write` и добавьте его в [переменные окружения](https://code.claude.com/docs/en/cloud-environments#set-environment-variables) среды как `TUIST_TOKEN`. Любой, кто использует эту среду, может прочитать токен, поэтому не назначайте ему другие области доступа, если только эти пользователи не должны также иметь доступ к вашему кэшу: команды на Mac получают <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">доступ к кэшу</.localized_link> только в пределах прав токена, поэтому добавьте `ci`, чтобы сборки на Mac могли читать и записывать ваш кэш.
4. Разрешите среде доступ к Tuist. Стандартный сетевой доступ Anthropic с уровнем **Trusted** не включает `tuist.dev`, поэтому выберите **Custom**, оставьте домены по умолчанию и добавьте `tuist.dev` в **Allowed domains**. CLI загружает файлы сессии на Mac через `tuist.dev`, поэтому другие домены не требуются.

После первой синхронизации Claude выполняет `mise install` в корневой директории репозитория на Mac, чтобы установить закрепленную версию Tuist проекта; начиная с Tuist 4.218.0, каждая команда самостоятельно входит в кэш вашего аккаунта.

### Готовые Mac {#remote-mac-snapshots}

Среда **Tuist Linux** может подготовить эти Mac заранее. Настройте скрипт настройки macOS через API (`macos_setup_script` в `PATCH /api/accounts/{account}/sandboxes/agent-environments/{id}`), например:

```bash
mise install
tuist install
tuist generate --no-open
xcodebuild build -workspace App.xcworkspace -scheme App -destination 'platform=iOS Simulator,name=iPhone 17'
```

Когда Claude создает Mac для репозитория, подключенного к одному из ваших проектов Tuist, `create_sandbox` получает репозиторий, и Mac загружается из снимка этого репозитория для соответствующей версии Xcode: ветка по умолчанию клонируется в `~/work/<name>`, там выполняется скрипт, и продукты сборки готовы. Первый вызов `tuist sandbox sync` отправляет только файлы, отличающиеся от этого коммита, поэтому Xcode пересобирает только измененные части. Первый Mac для репозитория и версии Xcode загружается без предварительной подготовки, а его снимок строится на простаивающем Mac (до часа) для последующих Mac. Изменение скрипта, версии Xcode или образа приводит к повторной сборке.

Claude удаляет Mac после завершения задачи. Оставшийся без дела Mac приостанавливается и удаляется после 14 дней простоя. Созданные таким образом Mac учитываются в вашем аккаунте Tuist так же, как и любые другие песочницы.
