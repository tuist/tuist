---
{
  "title": "Кэширующие тома",
  "titleTemplate": ":title · Раннеры · Возможности · Руководства · Tuist",
  "description": "Сохраняйте кэши Xcode, модулей и Gradle, а также любые другие директории между задачами раннеров Tuist на Linux или macOS при использовании GitHub Actions, Buildkite и GitLab CI."
}
---
# Тома кеша {#cache-volumes}

Раннеры Tuist могут сохранять кеш между задачами, поэтому новый раннер стартует уже «разогретым». Каждая задача получает приватную копию последних сохранённых данных с правом записи.

- **Управляемые кеши** сохраняют кеш компиляции Xcode, модульный кеш Tuist и кеши Gradle — каждый в одном шаге. Tuist знает, где находится каждый кеш, и хранит его в своём хранилище.
- **Пользовательские тома** сохраняют любые другие директории, например кеш загрузок менеджера пакетов, под выбранным вами ключом.

Добавляйте шаги после checkout и перед командами, которые используют кеши. На раннерах, не являющихся раннерами Tuist, они ничего не делают, а проблемы с кешем никогда не приводят к падению задачи: шаг логирует предупреждение, и задача продолжается с пустым кешем.

## Управляемые кеши {#managed-caches}

Шаги лишь определяют, где находятся кеши. Сохраняйте существующую настройку кеша: `tuist setup cache` или настройки сборки, включающие кеш компиляции (см. <.localized_link href="/guides/features/cache/xcode-cache">руководство по кешу Xcode</.localized_link>), аутентификацию для модульного кеша и <.localized_link href="/guides/features/cache/gradle-cache">плагин Tuist для Gradle</.localized_link> для удалённого кеша сборки Gradle. В GitLab CI комбинируйте фрагменты через `!reference`, потому что `extends` заменяет `before_script`.

### Кеш Xcode {#xcode-cache}

Сохраняет хранилище кеша компиляции Xcode на раннерах macOS.

::: code-group

```yaml [GitHub Actions]
jobs:
  build:
    runs-on: tuist-macos
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/xcode-cache@v1
      - run: xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```

```yaml [Buildkite]
steps:
  - label: Build
    agents:
      queue: tuist-macos
    plugins:
      - tuist/xcode-cache#v1: ~
    command: xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/xcode-cache-gitlab/v1/xcode-cache.yml

build:
  tags: [tuist-macos]
  before_script:
    - !reference [.tuist-xcode-cache, before_script]
  script:
    - xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```
<!-- -->
:::

### Модульный кеш {#module-cache}

Сохраняет локальный кеш Tuist на раннерах macOS: бинарные файлы <.localized_link href="/guides/features/cache/module-cache">модульного кеша</.localized_link>, скомпилированные манифесты, плагины и результаты выборочного тестирования.

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-macos
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/module-cache@v1
      - uses: jdx/mise-action@v4
      - run: tuist auth login
      - run: tuist install
      - run: tuist generate --no-open
      - run: tuist test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-macos
    plugins:
      - tuist/module-cache#v1: ~
    command: |
      mise install
      tuist auth login
      tuist install
      tuist generate --no-open
      tuist test
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/module-cache-gitlab/v1/module-cache.yml

test:
  tags: [tuist-macos]
  before_script:
    - !reference [.tuist-module-cache, before_script]
  script:
    - mise install
    - tuist auth login
    - tuist install
    - tuist generate --no-open
    - tuist test
```
<!-- -->
:::

### Кеш Gradle {#gradle-cache}

Сохраняет директории `caches` и `wrapper` домашнего каталога пользователя Gradle на раннерах Linux и macOS: зависимости, преобразованные JAR-файлы, скомпилированные скрипты сборки и дистрибутивы Gradle. Установите `GRADLE_USER_HOME` перед шагом, если вы его используете, и отключите другое кэширование этих директорий, например `cache: gradle` в `actions/setup-java`.

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
      - uses: tuist/gradle-cache@v1
      - run: ./gradlew test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/gradle-cache#v1: ~
    command: ./gradlew test
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/gradle-cache-gitlab/v1/gradle-cache.yml

test:
  tags: [tuist-linux]
  before_script:
    - !reference [.tuist-gradle-cache, before_script]
  script:
    - ./gradlew test
```
<!-- -->
:::

## Пользовательские тома {#custom-volumes}

Выберите стабильный `key` и `path`, затем подключите том перед установкой зависимостей. Путь должен быть пустым или отсутствовать. Удалите любое кэширование архивов или восстановление артефактов, которые записывают в ту же директорию. Чтобы хранить несколько директорий в одном томе, см. [Несколько директорий в одном томе](#several-directories-in-one-volume).

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/cache-volume@v1
        with:
          key: npm
          path: ~/.npm
      - run: npm ci
      - run: npm test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: npm
              path: ~/.npm
    command: |
      npm ci
      npm test
```

```yaml [GitLab CI]
test:
  tags: [tuist-linux]
  before_script:
    - tuist-cache-volume --key npm --path ~/.npm
  script:
    - npm ci
    - npm test
```
<!-- -->
:::

### Несколько директорий в одном томе {#several-directories-in-one-volume}

Том может содержать несколько директорий. В GitHub Actions указывайте по одному пути на строку; в Buildkite задайте `path` как список; в GitLab CI передавайте `--path` один раз для каждой директории. Пустые строки и окружающие пробельные символы игнорируются.

::: code-group

```yaml [GitHub Actions]
jobs:
  lint:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/cache-volume@v1
        with:
          key: python-tools
          path: |
            ~/.cache/pip
            ~/.cache/pre-commit
      - run: pip install pre-commit
      - run: pre-commit run --all-files
```

```yaml [Buildkite]
steps:
  - label: Lint
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: python-tools
              path:
                - ~/.cache/pip
                - ~/.cache/pre-commit
    command: |
      pip install pre-commit
      pre-commit run --all-files
```

```yaml [GitLab CI]
lint:
  tags: [tuist-linux]
  before_script:
    - tuist-cache-volume --key python-tools --path ~/.cache/pip --path ~/.cache/pre-commit
  script:
    - pip install pre-commit
    - pre-commit run --all-files
```
<!-- -->
:::

- **Общая ёмкость.** Все пути делят ёмкость тома и восстанавливаются и сохраняются вместе.
- **Группируйте небольшие связанные директории.** Выделите большой или часто меняющейся директории отдельный том.
- **Без вложенности.** Пути внутри одного тома не должны содержать друг друга.
- **Изменение списка начинает с холодного старта.** Каждый путь хранится в своей директории внутри тома, идентифицируемой по тому, как записан путь. Переключение между одним путём и несколькими, а также добавление, удаление или перезапись пути меняет эту структуру: первая задача после изменения стартует с холодным кешем для затронутых путей. Содержимое путей, которые больше не указаны, остаётся в томе, пока вы его не удалите.

### Как работают ключи {#how-keys-work}

Ключ именует том, который меняется со временем; это не имя фиксированного снимка, как ключ `actions/cache`.

- **Один том на ключ.** Каждый ключ ограничен репозиторием (в Buildkite — пайплайном; в GitLab CI — проектом), платформой, архитектурой CPU и пользователем. Каждая задача, подключающая его, стартует с последних сохранённых данных, а подходящие задачи сохраняют свои изменения обратно в тот же том.
- **Держите ключи стабильными.** Не включайте версии или хеши lock-файлов в ключ. С `actions/cache` ключ вида `deps-${{ hashFiles('Package.resolved') }}` создаёт новую запись при каждом изменении, а `restore-keys` откатывается к более старой. Здесь новый ключ — это новый пустой том: первая задача после каждого изменения стартует с холодным кешем, а старые тома остаются до истечения срока. Оставьте ключ и позвольте инструменту обновлять содержимое; менеджеры пакетов переиспользуют всё, что ещё актуально.
- **Нет частичных совпадений.** Ключей восстановления нет. Ключ, который ещё не был сохранён, стартует пустым.
- **Ключи, начинающиеся с `tuist-`, зарезервированы** для собственных кешей Tuist и отклоняются до подключения тома.
- **Намеренный сброс.** Измените ключ или удалите том, если хотите, чтобы задача стартовала с пустым кешем.
- **Оставьте ключи `tuist-` для Tuist.** Управляемые кеши используют ключи, начинающиеся с `tuist-`, поэтому выберите другое имя для своих томов.

В Linux пути монтируются как обычные директории, поэтому инструменты могут использовать свои стандартные расположения, такие как `deps`, `_build` и `node_modules`. Сохраняйте обычные правила `.gitignore`. В macOS пути являются символическими ссылками: используйте кеши загрузок, такие как `~/.npm`; `node_modules` и инструменты, заменяющие свою директорию кеша, не поддерживаются. Игнорируйте ссылки на workspace без завершающего слэша в `.gitignore`.

## Сохранение изменений {#saving-changes}

Управляемые кеши и пользовательские тома сохраняют изменения успешных задач из вашего репозитория на любой ветке:

| Провайдер | Задачи, сохраняющие изменения |
| --- | --- |
| GitHub Actions | Задачи push, по расписанию, ручного запуска и pull request из самого репозитория |
| Buildkite | Сборки по вебхуку и расписанию репозитория пайплайна, включая его pull request |
| GitLab CI | Push, расписание и веб-пайплайны проекта, а также пайплайны его собственных merge request, если подключение имеет <.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">токен доступа к API</.localized_link> |

Другие задачи могут использовать кеш, но их изменения отбрасываются. К ним относятся pull request из форков, задачи `pull_request_target`, сборки Buildkite, запущенные через API или дашборд, GitLab merge request из форков или без токена доступа к API, а также теги. Задача, которая не изменяет том, оставляет сохранённую версию на месте. Вы можете сузить список веток, сохраняющих данные, в профиле раннера; см. [Выберите ветки для сохранения](#choose-which-branches-save).

Параллельные задачи работают независимо; изменения от разных задач не объединяются. Никогда не кешируйте учётные данные или незаменимые данные.

### Выберите ветки для сохранения {#choose-which-branches-save}

Вы можете изменить, какие ветки сохраняют управляемые кеши и пользовательские тома. Откройте **Runners → Profiles**, отредактируйте профиль, который используют ваши задачи, и разверните раздел **Save cache from**. Задачи используют запрошенный ими профиль: в `runs-on:` для GitHub Actions, в качестве очереди для Buildkite или в `tags:` для GitLab CI. Настройки применяются ко всем томам, используемым задачами этого профиля, включая тома, созданные позже.

![Форма профиля раннера с развернутым разделом Save cache from, где включена Default branch и добавлены develop и release/* как дополнительные ветки](/images/guides/features/runners/save-cache-from.png)

По умолчанию каждая успешная задача из репозитория сохраняет свои изменения. Чтобы сохранять данные только с некоторых веток, включите **Limit to specific branches**:

- **Default branch** позволяет задачам на основной ветке каждого репозитория сохранять изменения. Отключите этот параметр, чтобы сохранять данные только с дополнительных веток.
- В разделе **Additional branches** добавьте до 20 имён веток, которые также будут сохранять данные. Используйте `*` как подстановочный знак: `release/*` соответствует `release/1.0`.

Задачи, перечисленные в разделе [Сохранение изменений](#saving-changes), сохраняют свои изменения, если их ветка совпадает. В задачах push и ручного запуска GitHub Actions тег с подходящим именем также считается совпадением.

Задачи на других ветках всё ещё могут использовать кеш, но их изменения отбрасываются. Задачи, которые никогда не сохраняют данные, например pull request из форков, не сохраняют их даже на подходящей ветке. Сужение этих настроек или удаление профиля приводит к отмене ожидающих изменений, которые они больше не разрешают; удалённый профиль возвращается к сохранению со всех веток.

## Ёмкость и хранение {#capacity-and-retention}

Кеш Xcode начинается с **30 ГБ**. Кеш модулей, кеш Gradle и каждый пользовательский том начинаются с **20 ГБ**. Укажите размер, чтобы задать другую ёмкость кеша или тома, целое число ГБ от `1gb` до `100gb`:

::: code-group

```yaml [GitHub Actions]
- uses: tuist/xcode-cache@v1
  with:
    size: 50gb
- uses: tuist/module-cache@v1
  with:
    size: 40gb
```

```yaml [Buildkite]
plugins:
  - tuist/xcode-cache#v1:
      size: 50gb
  - tuist/module-cache#v1:
      size: 40gb
```

```yaml [GitLab CI]
build:
  variables:
    TUIST_XCODE_CACHE_SIZE: 50gb
    TUIST_MODULE_CACHE_SIZE: 40gb
```
<!-- -->
:::

Кеш Gradle и пользовательские тома принимают тот же входной параметр `size` (`TUIST_GRADLE_CACHE_SIZE` и `TUIST_VOLUME_SIZE` в GitLab CI, `--size` для `tuist-cache-volume`). Больший размер увеличивает том, сохраняя его содержимое, начиная со следующей задачи. Меньший размер применяется после следующего удаления или истечения срока действия тома. Когда задачи запрашивают разные размеры одного кеша, применяется наибольший, поэтому указывайте каждый размер в одном месте.

Все они истекают через **7 дней без монтирования задачей**, и следующая задача начинается с пустого тома после истечения срока. Tuist очищает кеши Xcode и модулей, чтобы уложиться в их ёмкость, а шаг кеша Gradle заставляет Gradle удалять записи, не использовавшиеся семь дней, после каждой сборки.

Пользовательские тома не очищают старые зависимости: используйте настройки очистки вашего инструмента, чтобы держать их небольшими. Запись в полный том может привести к сбою задачи. Когда сохранённое содержимое достигает **80%** ёмкости тома и у задачи заканчивается место на нём, следующая задача начинается с пустого тома, а её изменения начинают новое сохранённое состояние.

## Просмотр и удаление томов {#inspecting-and-clearing-volumes}

Откройте **Runners → Volumes**, чтобы просмотреть используемое пространство, процент попаданий в кеш и историю задач. Кеши Xcode, модулей и Gradle также отображаются там.

Администраторы аккаунта могут выбрать **Delete volume**, чтобы удалить том и его сохранённое содержимое. Выполняющиеся задачи сохраняют свои частные копии, но не могут сохранить их обратно, а следующая задача, использующая тот же ключ, начинается с пустого тома. Удалённые тома больше не отображаются в списке.

Чтобы удалить том из терминала или рабочего процесса, найдите его ID и передайте его в `tuist runner volume delete`:

```bash
tuist runner volume list --account my-org --name gradle-build-cache --json
tuist runner volume delete <volume-id> --account my-org --yes
```

Та же операция доступна через [API](https://tuist.dev/api/docs#tag/runners) как `DELETE /api/accounts/{account_handle}/runners/volumes/{volume_id}` и через [MCP server](/guides/features/agentic-coding/mcp) как `delete_runner_volume`. Все они требуют прав администратора аккаунта или токена с областью действия `account:runners:write`.
