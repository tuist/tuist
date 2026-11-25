---
{
  "title": "Claude",
  "titleTemplate": ":title · Песочницы · Возможности · Руководства · Tuist",
  "description": "Запускайте сессии Claude Managed Agents и облачные сессии Claude Code (claude.ai, десктопные и мобильные приложения, а также claude --cloud) в песочницах Tuist на Linux или macOS."
}
---
# Claude {#claude}

> [!IMPORTANT]
> **Только по приглашению**
>
> Песочницы Tuist для Linux и macOS сейчас доступны только по приглашению. [Напишите нам](mailto:contact@tuist.dev) или обратитесь в [Slack-сообщество](https://slack.tuist.dev), чтобы запросить доступ к вашему аккаунту.

Anthropic управляет циклом агента Claude, а *среда с самостоятельным размещением* определяет, где запускаются инструменты Claude. Подключите такую среду к Tuist, и каждая сессия в ней получит собственную <.localized_link href="/guides/features/sandboxes">песочницу</.localized_link> Tuist на Linux или macOS. Туист запускает необходимые воркеры и раннеры, поэтому вам не нужно ничего хостить самостоятельно.

Есть два типа сред — по одной для каждого продукта Claude:

- **[Claude Managed Agents](#managed-agents)**: сессии, которые вы запускаете через API Claude или API агент-сессий Tuist. Вы создаёте среду (`env_…`) в [Claude Console](https://platform.claude.com/environments), и каждая сессия может выбрать Linux или macOS.
- **[Claude Code](#claude-code)**: облачные сессии, которые разработчики запускают из claude.ai, десктопных и мобильных приложений Claude, а также `claude --cloud`. Владелец команды или Enterprise-аккаунта Claude создаёт среды (`ccpool_…`) в админ-настройках claude.ai — по одной для каждой платформы, а разработчики выбирают Linux или macOS, выбирая соответствующую среду.

Обе среды подключаются через API Tuist администратором аккаунта. Выполните аутентификацию с помощью `tuist auth login`, затем:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### Подключение среды {#managed-agents-connect}

Подключитесь через раздел аккаунта **Settings → Integrations → Claude**. Форма запрашивает среду с самостоятельным размещением и учётные данные, с которыми Tuist будет запускать сессии:

1. **Создайте среду.** В Claude Console перейдите на страницу [Environments](https://platform.claude.com/environments), создайте среду с самостоятельным размещением, откройте её и нажмите **Generate environment key**. Anthropic генерирует ключи среды только в Console.
2. **Выберите учётные данные** с помощью селектора в верхней части формы (см. ниже).
3. **Вставьте ID среды и ключ** и выберите платформу и конфигурацию песочниц этой среды.

Tuist проверяет среду с указанными учётными данными до сохранения, поэтому неверные учётные данные, ID или рабочее пространство приведут к ошибке в форме. Ключи хранятся в зашифрованном виде и больше не отображаются. В течение минуты Tuist начинает обслуживать сессии этой среды. Доступные конфигурации см. в разделе <.localized_link href="/guides/features/sandboxes#platforms">Linux и macOS</.localized_link>.

#### С использованием API-ключа {#managed-agents-connect-api-key}

Это вариант по умолчанию и самый быстрый способ попробовать песочницы. Вставьте API-ключ с ролью разработчика в рабочем пространстве среды. Интеграция помечает среды, использующие API-ключ; прежде чем полагаться на такой ключ, подключите среду через федеративную идентификацию, чтобы Tuist не хранил долгоживущий ключ.

#### С федеративной идентификацией {#managed-agents-connect-federated}

Tuist выполняет аутентификацию через [Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation) от Anthropic, поэтому вам не нужно передавать ему API-ключ Anthropic. Требуется роль администратора в вашей организации Anthropic.

1. **Доверьтесь Tuist.** Форма показывает URL эмитента вашего аккаунта и префикс субъекта. В Claude Console откройте [Workload identity](https://platform.claude.com/settings/workload-identity-federation), нажмите **Connect workload**, выберите **Custom OIDC** и укажите их со скоупом `workspace:developer`. Добавьте сервисный аккаунт, созданный мастером настройки, в рабочее пространство среды.
2. **Укажите ID.** ID организации находится в разделе **Settings → Organization**, а ID рабочего пространства — в **Settings → Workspaces**. После завершения подключения рабочего пространства отображаются ID сервисного аккаунта и правила федерации; их также можно увидеть на странице правила в разделе Workload identity. Ни один из них не является секретом. Если Anthropic отклоняет токен Tuist, причина будет указана в [журнале аутентификации](https://platform.claude.com/settings/workload-identity-federation?tab=history) Console.

#### Через API {#managed-agents-connect-api}

Чтобы подключить среду из автоматизации, создайте среду с самостоятельным размещением в [Claude Console](https://platform.claude.com/environments), сгенерируйте её ключ и отправьте оба значения в Tuist:

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

Чтобы запускать сессии через API Tuist, также отправьте либо четыре ID федерации (см. [Подключение без API-ключа](#managed-agents-federation)), либо `anthropic_api_key`. Среда работает на Linux, если вы не передадите `"platform": "darwin"`; параметры `vcpus`, `memory_mb` и `workspace_gb` изменяют конфигурацию её песочниц, а `xcode_version` задаёт [Xcode](#xcode) для её macOS-песочниц.

### Запуск сессии {#managed-agents-sessions}

Каждая сессия выполняется на платформе среды, если сессия явно не запрашивает другую.

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

`repository_url` и, опционально, `repository_ref` (ветка или коммит) заставляют Tuist клонировать публичный репозиторий в песочницу перед первым ходом агента.

**Через API агент-сессий Tuist** Tuist сам создаёт агента и сессию, а также клонирует приватные GitHub-репозитории, подключённые к вашему аккаунту Tuist:

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

Если у аккаунта несколько сред, передайте `agent_environment_id`. За состоянием сессии можно следить через `GET /agent-sessions/{id}/events`, отвечать через `POST /agent-sessions/{id}/messages` и завершать её через `POST /agent-sessions/{id}/archive`.

Репозиторий извлекается в `/workspace` на Linux и в `/Users/runner/work` на macOS. Песочница сессии приостанавливается после завершения хода агента и возобновляется при следующем сообщении.

### Выбор Xcode для сессии {#managed-agents-xcode}

Mac сессии загружается до того, как Claude запустит любой инструмент, поэтому Claude не может выбрать свой Xcode. Тот, кто создаёт сессию, выбирает его так же, как выбирает macOS. Tuist использует первое из следующих установленных значений:

1. `xcode_version` в API агент-сессий Tuist рядом с `platform`. Версия, которую Tuist не предлагает, будет отклонена при создании сессии, с перечнем доступных версий.
2. `tuist_xcode_version` в метаданных сессии при создании сессии через API Claude:

   ```json
   "metadata": { "tuist_platform": "macos", "tuist_xcode_version": "26.1.1" }
   ```

3. `xcode_version` среды, когда сессия выполняется на платформе этой среды.
4. Xcode по умолчанию.

Xcode без указания платформы подразумевает macOS. Важные моменты:

- **Сессия сохраняет выбранный Xcode.** Её песочница загружается один раз, и последующие сообщения или изменения метаданных не меняют её. Для другого Xcode используйте новую сессию.
- **Tuist проверяет метаданные при поступлении первого хода.** Если `tuist_xcode_version` указывает версию Xcode, которую Tuist не предлагает, Tuist останавливает этот ход, не запуская песочницу, и логирует доступные версии. Используйте API агент-сессий Tuist, чтобы получить ошибку сразу при создании сессии.
- **В среде macOS Tuist ожидает, а не угадывает.** Если Tuist не может прочитать метаданные новой сессии, он приостанавливает ход и повторяет попытку вместо загрузки Xcode среды.

> [!WARNING]
> Любой, кто может создавать сессии в рабочем пространстве Claude, владеющем средой, может запускать сессии от вашего аккаунта Tuist и запрашивать macOS и её Xcode через метаданные сессии. Ограничьте доступ к этому рабочему пространству соответствующим образом.

### Подключение без API-ключа {#managed-agents-federation}

Панель управления настраивает это за вас. Через API Tuist работает так же: у каждого аккаунта есть собственный эмитент OpenID Connect в Tuist, `https://tuist.dev/oidc/accounts/<account id>`, который подписывает краткосрочный токен для каждого запроса к Anthropic, обменивая его на токен доступа Anthropic, действующий несколько минут. Правило федерации, доверяющее вашему эмитенту, никогда не принимает токены, подписанные Tuist для других аккаунтов.

- Каждый ответ среды агента включает `federation_issuer_url` и `federation_subject` (`account:123:agent-environment:456`). В мастере Custom OIDC консоли используйте URL эмитента и либо этот точный субъект, чтобы разрешить доступ только этой среде, либо `account:123:*`, чтобы разрешить доступ ко всем средам аккаунта. Проверки настройки панели управления используют субъект `account:123:setup`, который принимается только по префиксу. Используйте область видимости `workspace:developer`.
- Передавайте идентификаторы организации, рабочего пространства, сервисного аккаунта и правила как `anthropic_organization_id`, `anthropic_workspace_id`, `anthropic_service_account_id` и `anthropic_federation_rule_id` при создании или через `PATCH /agent-environments/{id}`. Если у среды есть и идентификаторы, и API-ключ, Tuist использует федерацию.

> [!NOTE]
> Anthropic получает ключи эмитента по HTTPS на порту 443 с публичного хоста. Если ваш самостоятельно размещённый сервер Tuist недоступен из интернета, выберите источник JWKS **inline** в консоли и вставьте набор ключей, который ваш сервер отдаёт по адресу `<issuer>/jwks.json`. Повторяйте это при каждом изменении ключа подписи Tuist, что происходит при изменении `TUIST_SECRET_KEY_TOKENS` сервера (или, если он не установлен, `TUIST_SECRET_KEY_BASE`).

## Claude Code {#claude-code}

Облачные сессии Claude Code — это те, которые разработчики запускают с [claude.ai/code](https://claude.ai/code), настольных и мобильных приложений Claude, а также через `claude --cloud`. Они выбирают место выполнения сессии по её среде, поэтому подключите одну среду для каждой платформы, которую хотите предложить.

### Подключение сред {#claude-code-connect}

1. Владелец организации Claude включает **Allow self-hosted environments** на странице администрирования [Cloud environments](https://claude.ai/admin-settings/cloud-environments). Для этого требуется план Team или Enterprise; см. руководство Anthropic по [self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments).
2. На той же странице создайте самостоятельно размещённую среду для каждой платформы с именем, которое увидят разработчики, например **Tuist Linux** и **Tuist macOS**. Скопируйте ID `ccpool_…` каждой среды и её ключ среды, который показывается только один раз.
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

Разработчики выбирают среду, а вместе с ней и платформу, при запуске облачной сессии:

- **claude.ai, настольные и мобильные приложения:** выберите **Tuist Linux** или **Tuist macOS** в выборе среды новой сессии.
- **Claude Code CLI:** выполните `/remote-env` в `claude` и выберите среду по имени. Затем `claude --cloud "<task>"` будет выполняться в ней. Чтобы выбрать среду для одной сессии, передайте её ID: `claude --cloud "<task>" --environment ccpool_...`.
- **Вся команда или репозиторий:** установите ID среды по умолчанию в [settings](https://code.claude.com/docs/en/settings) Claude Code, например в `.claude/settings.json` репозитория:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

Сессии в этих средах используют потребление Claude Code вашей организации как обычно, а их песочницы учитываются в вашем аккаунте Tuist.

### Выбор Xcode {#xcode}

Каждая среда macOS загружает один <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>, по умолчанию, если вы не подключили её с указанием `xcode_version`, например `"xcode_version": "26.1.1"`. Чтобы предложить более одного варианта, подключите отдельную среду для каждого и назовите их соответственно, например **Tuist macOS · Xcode 26.1.1**. Разработчики затем выбирают Xcode, выбирая среду.

Чтобы перевести среду на другой Xcode, обновите её:

```bash
curl -X PATCH "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments/<id>" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{ "xcode_version": "27.0" }'
```

Новые сессии получают новый Xcode, а сессии, у которых уже есть песочница, сохраняют свой. `null` возвращает к значению по умолчанию. То же самое относится к средам Managed Agents, сессии которых также могут [выбирать свой собственный](#managed-agents-xcode).

### Более быстрый запуск сессий и сборок {#claude-code-caching}

- **Кэш Tuist:** сессии получают `TUIST_URL` и, если у вашего аккаунта есть кэш в том же стойке, `TUIST_CACHE_ENDPOINT`. CLI Tuist и задачи Mix `tuist_ex` в сессии входят самостоятельно, используя токен идентичности сессии. См. раздел <.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code sessions</.localized_link> в руководстве по аутентификации.
- **Кэшированные извлечения:** когда приложение Tuist GitHub вашего аккаунта может читать репозиторий сессии, новая сессия начинается с того же кэшированного извлечения, которое используют ваши раннеры Tuist, поэтому она загружает только недостающие коммиты вместо полного клонирования. По завершении сессии она возвращает объекты последнего коммита ветки по умолчанию, что поддерживает актуальность кэшированного извлечения даже для репозиториев, не запускающих CI на Tuist. Обновление происходит только по коммиту, который GitHub сообщает для ветки по умолчанию; собственные ветки сессии никогда не обновляют кэш. Отключите песочницы или удалите приложение, чтобы остановить это.
- **macOS:** Mac разделяет сборки сессий Claude Code, выполняемые на каждой ВМ, поэтому новая сессия не загружает их заново.

## Использование Mac из любой сессии Claude Code {#remote-mac}

Сессии Claude Code, работающие на Linux, такие как облачные сессии в среде, размещённой Anthropic, всё ещё могут собирать и тестировать код для платформ Apple в песочнице macOS Tuist, как описано в разделе <.localized_link href="/guides/features/sandboxes#coding-agents">Build on a Mac from a coding agent</.localized_link>. В отличие от среды **Tuist macOS**, сессия сохраняет свою собственную среду.

В среде **Tuist Linux** ничего настраивать не нужно: CLI Tuist и сервер Tuist MCP уже установлены и входят в систему, используя идентичность сессии.

Для облачных сессий в среде, размещённой Anthropic:

1. Сделайте <.localized_link href="/guides/features/agentic-coding/mcp">MCP server</.localized_link> Tuist доступным для сессий: добавьте `https://tuist.dev/mcp` как коннектор в claude.ai и включите его для сессии или объявите его в закоммиченном файле `.mcp.json` репозитория.
2. Установите CLI Tuist в [setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts) среды, например с помощью `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`.
3. Создайте <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> с областью действия `account:sandboxes:write` и добавьте его в [environment variables](https://code.claude.com/docs/en/cloud-environments#set-environment-variables) среды как `TUIST_TOKEN`. Все, кто использует среду, могут его прочитать, поэтому не назначайте ему других областей действия, если они не должны также использовать ваш кеш: команды на Mac получают <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">cache access</.localized_link> только в той мере, в какой это разрешено токеном, поэтому добавьте `ci`, чтобы сборки на Mac могли читать и записывать ваш кеш.
4. Разрешите среде доступ к Tuist. Стандартный сетевой доступ Anthropic **Trusted** не включает `tuist.dev`, поэтому выберите **Custom**, оставьте домены по умолчанию и добавьте `tuist.dev` в **Allowed domains**. CLI загружает файлы сессии на Mac через `tuist.dev`, поэтому другие домены не требуются.

На Mac установлен CLI Tuist, и он запускает версию проекта, если она зафиксирована через mise; начиная с Tuist 4.218.0, каждая команда самостоятельно входит в кеш вашего аккаунта.

### Готовые Mac {#remote-mac-snapshots}

Среда **Tuist Linux** может подготовить эти Mac заранее. Настройте её скрипт настройки macOS через API (`macos_setup_script` в `PATCH /api/accounts/{account}/sandboxes/agent-environments/{id}`), например:

```bash
mise install
tuist install
tuist generate --no-open
xcodebuild build -workspace App.xcworkspace -scheme App -destination 'platform=iOS Simulator,name=iPhone 17'
```

Когда Claude создаёт Mac для репозитория, подключённого к одному из ваших проектов Tuist, `create_sandbox` получает репозиторий, и Mac загружается из снимка этого репозитория для своего Xcode: ветка по умолчанию клонируется в `~/work/<name>`, там выполнен скрипт, и продукты сборки находятся на месте. Первый `tuist sandbox sync` отправляет только файлы, отличающиеся от этого коммита, поэтому Xcode пересобирает только то, что изменилось. Первый Mac для репозитория и Xcode загружается без предварительной подготовки, а его снимок строится на простаивающем Mac в течение часа для последующих Mac. Изменение скрипта, Xcode или образа приводит к повторной сборке. Снимок сохраняет симуляторы образа и удаляет те, которые были созданы скриптом, и каждый такой Mac начинает загрузку новейшего Pro iPhone из образа (iPhone 18 Pro на Xcode 27.2) сразу после запуска, так что он готов к моменту завершения первой сборки; выполните сборку для этого симулятора и в скрипте, чтобы сборки сессии для него использовали данные из снимка.

Claude удаляет Mac после завершения задачи. Оставшийся Mac приостанавливается при простое и удаляется после 14 дней простоя. Mac, созданные таким образом, учитываются в вашем аккаунте Tuist так же, как и любые другие песочницы.
