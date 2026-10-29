---
{
  "title": "Cache volumes",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Keep the Xcode, module and Gradle caches and any other directory between Tuist Linux or macOS runner jobs with GitHub Actions, Buildkite, and GitLab CI."
}
---
# Тома кэша {#cache-volumes}

Раннеры Tuist могут сохранять кэш между задачами, поэтому новый раннер начинает работу с уже прогретым кэшем. Каждая задача получает приватную копию для записи последних сохранённых данных.

- **Управляемые кэши** сохраняют кэш компиляции Xcode, кэш модулей Tuist и кэши Gradle — каждый одним шагом. Tuist знает, где находится каждый кэш, и хранит его в своём хранилище.
- **Пользовательские тома** сохраняют любой другой каталог, например кэш загрузок менеджера пакетов, под выбранным вами ключом.

Добавьте шаги после checkout и перед командами, которые используют кэши. На раннерах, которые не являются раннерами Tuist, они ничего не делают, и проблемы с кэшем никогда не приводят к падению задачи: шаг логирует предупреждение, а задача продолжается с пустым кэшем.

## Управляемые кэши {#managed-caches}

Шаги лишь определяют, где находятся кэши. Сохраните существующую настройку кэша: `tuist setup cache` или настройки сборки, включающие кэширование компиляции (см. <.localized_link href="/guides/features/cache/xcode-cache">руководство по кэшу Xcode</.localized_link>), аутентификацию для кэша модулей и <.localized_link href="/guides/features/cache/gradle-cache">плагин Tuist Gradle</.localized_link> для удалённого кэша сборки Gradle. В GitLab CI объединяйте фрагменты с помощью `!reference`, потому что `extends` заменяет `before_script`.

### Кэш Xcode {#xcode-cache}

Сохраняет хранилище кэша компиляции Xcode на раннерах macOS.

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

### Кэш модулей {#module-cache}

Сохраняет локальный кэш Tuist на раннерах macOS: бинарные файлы <.localized_link href="/guides/features/cache/module-cache">кэша модулей</.localized_link>, скомпилированные манифесты, плагины и результаты выборочного тестирования.

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

### Кэш Gradle {#gradle-cache}

Сохраняет каталоги `caches` и `wrapper` домашней директории пользователя Gradle на раннерах Linux и macOS: зависимости, преобразованные JAR-файлы, скомпилированные скрипты сборки и дистрибутивы Gradle. Установите `GRADLE_USER_HOME` перед шагом, если вы его используете, и отключите другое кэширование этих каталогов, например `cache: gradle` в `actions/setup-java`.

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

Выберите стабильный `key` и `path`, затем подключите том перед установкой зависимостей. Путь должен быть пустым или отсутствовать. Удалите любое кэширование архивов или восстановление артефактов, которые записывают в тот же каталог. Чтобы хранить несколько каталогов в одном томе, см. [Несколько каталогов в одном томе](#several-directories-in-one-volume).

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

### Несколько каталогов в одном томе {#several-directories-in-one-volume}

Том может содержать несколько каталогов. В GitHub Actions указывайте один путь на строку; в Buildkite задайте `path` как список; в GitLab CI передавайте `--path` один раз для каждого каталога. Пустые строки и окружающие пробельные символы игнорируются.

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

- **Общая ёмкость.** Все пути разделяют ёмкость тома и восстанавливаются и сохраняются вместе.
- **Группируйте небольшие связанные каталоги.** Выделите отдельный том для большого или часто меняющегося каталога.
- **Без вложенности.** Пути в одном томе не должны содержать друг друга.
- **Изменение списка приводит к холодному старту.** Каждый путь хранится в собственном каталоге внутри тома, идентифицируемом по тому, как написан путь. Переключение между одним путём и несколькими, а также добавление, удаление или перезапись пути меняет эту структуру: первая задача после изменения начинает работу с холодным кэшем для затронутых путей. Содержимое путей, которые больше не указаны, остаётся в томе до его очистки.

### Как работают ключи {#how-keys-work}

Ключ именует том, который меняется со временем; это не имя фиксированного снимка, как ключ `actions/cache`.

- **Один том на ключ.** Каждый ключ ограничен репозиторием (в Buildkite — пайплайном; в GitLab CI — проектом), платформой, архитектурой процессора и пользователем. Каждая задача, подключающая его, начинается с последних сохранённых данных, а подходящие задачи сохраняют свои изменения обратно в тот же том.
- **Сохраняйте ключи стабильными.** Не включайте версии или хэши lock-файлов в ключ. С `actions/cache` ключ вида `deps-${{ hashFiles('Package.resolved') }}` создаёт новую запись при каждом изменении, а `restore-keys` откатывается к более старой. Здесь новый ключ — это новый пустой том: первая задача после каждого изменения начинает с холодного кэша, а старые тома остаются до истечения срока их действия. Оставьте ключ и позвольте инструменту обновлять содержимое; менеджеры пакетов повторно используют всё, что ещё актуально.
- **Нет частичных совпадений.** Ключей восстановления нет. Ключ, который ещё не был сохранён, начинается пустым.
- **Намеренный перезапуск.** Измените ключ или очистите том в панели управления, если хотите, чтобы задача начиналась с пустого состояния.
- **Оставьте ключи `tuist-` для Tuist.** Управляемые кэши используют ключи, начинающиеся с `tuist-`, поэтому выберите другое имя для своих томов.

В Linux пути монтируются как обычные каталоги, поэтому инструменты могут использовать свои стандартные расположения, такие как `deps`, `_build` и `node_modules`. Сохраняйте обычные правила `.gitignore`. В macOS пути являются символическими ссылками: используйте кэши загрузок, такие как `~/.npm`; `node_modules` и инструменты, заменяющие свой каталог кэша, не поддерживаются. Игнорируйте ссылки на workspace без завершающего слэша в `.gitignore`.

## Сохранение изменений {#saving-changes}

Управляемые кэши и пользовательские тома сохраняют изменения успешных задач из вашего репозитория на любой ветке:

| Провайдер | Задачи, сохраняющие изменения |
| --- | --- |
| GitHub Actions | Задачи push, по расписанию, ручного запуска и pull request из самого репозитория |
| Buildkite | Сборки по вебхуку и расписанию репозитория пайплайна, включая его pull request |
| GitLab CI | Push-, запланированные и веб-пайплайны проекта, а также пайплайны его собственных merge request, если подключение имеет <.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">токен доступа к API</.localized_link> |

Другие задачи могут использовать кэш, но их изменения отбрасываются. К ним относятся pull request из форков, задачи `pull_request_target`, сборки Buildkite, запущенные через API или панель управления, merge request в GitLab из форков или без токена доступа к API, а также теги. Задача, не изменяющая том, оставляет сохранённую версию на месте. Вы можете ограничить ветки, сохраняющие данные, в профиле раннера; см. [Выбор веток для сохранения](#choose-which-branches-save).

Параллельные задачи работают независимо; изменения от разных задач не объединяются. Никогда не кэшируйте учётные данные или незаменимые данные.

### Выбор веток для сохранения {#choose-which-branches-save}

Вы можете изменить, какие ветки сохраняют управляемые кэши и пользовательские тома. Откройте **Runners → Profiles**, отредактируйте профиль, используемый вашими задачами, и разверните раздел **Save cache from**. Задачи используют запрошенный ими профиль: в `runs-on:` для GitHub Actions, в качестве очереди для Buildkite или в `tags:` для GitLab CI. Настройки применяются ко всем томам, используемым задачами этого профиля, включая тома, созданные позже.

![Форма профиля раннера с развернутым разделом Save cache from, где включена Default branch и добавлены develop и release/* в качестве дополнительных веток](/images/guides/features/runners/save-cache-from.png)

По умолчанию каждая успешная задача из репозитория сохраняет свои изменения. Чтобы сохранять только из некоторых веток, включите **Limit to specific branches**:

- **Default branch** позволяет задачам на основной ветке каждого репозитория сохранять изменения. Отключите этот параметр, чтобы сохранять только из дополнительных веток.
- В разделе **Additional branches** добавьте до 20 имён веток, которые также будут сохранять данные. Используйте `*` как подстановочный знак: `release/*` соответствует `release/1.0`.

Задачи, перечисленные в [Сохранение изменений](#saving-changes), сохраняют свои изменения, если их ветка совпадает. В GitHub Actions при push и ручном запуске тег с подходящим именем также считается совпадением.

Задачи на других ветках всё ещё могут использовать кэш, но их изменения отбрасываются. Задачи, которые никогда не сохраняют данные, например pull request из форков, также не сохраняют данные на совпадающей ветке. Сужение этих настроек или удаление профиля приводит к отмене ожидающих изменений, которые они больше не разрешают; удалённый профиль возвращается к сохранению из всех веток.

## Ёмкость и хранение {#capacity-and-retention}

Кэш Xcode начинается с **30 ГБ**. Кэш модулей, кэш Gradle и каждый пользовательский том начинаются с **20 ГБ**. Укажите размер, чтобы задать кэшу или тому другую ёмкость — целое число ГБ от `1gb` до `100gb`:

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

Кэш Gradle и пользовательские тома принимают тот же входной параметр `size` (`TUIST_GRADLE_CACHE_SIZE` и `TUIST_VOLUME_SIZE` в GitLab CI, `--size` для `tuist-cache-volume`). Больший размер увеличивает том, сохраняя его содержимое, начиная со следующей задачи. Меньший размер применяется после следующей очистки тома или его истечения срока действия. Если задачи запрашивают разные размеры одного кэша, применяется наибольший, поэтому указывайте каждый размер в одном месте.

Все они истекают после **7 дней без монтирования задачей**, и следующая задача начинается с пустого тома после истечения срока. Tuist очищает кэши Xcode и модулей, чтобы уложиться в их ёмкость, а шаг кэша Gradle заставляет Gradle удалять записи, не использовавшиеся семь дней, после каждой сборки.

Пользовательские тома не очищают старые зависимости: используйте настройки очистки вашего инструмента, чтобы поддерживать их небольшой размер. Запись в полный том может привести к сбою задачи. Когда сохранённое содержимое достигает **80%** ёмкости тома и у задачи заканчивается место на нём, следующая задача начинается с пустого тома, а её изменения начинают новое сохранённое состояние.

## Просмотр и очистка томов {#inspecting-and-clearing-volumes}

Откройте **Runners → Volumes**, чтобы просмотреть используемое пространство, коэффициент попадания в кэш и историю задач. Администраторы аккаунта могут выбрать **Clear volume**, чтобы будущие задачи начинались с пустого состояния. Выполняющиеся задачи сохраняют свои приватные копии, но не могут сохранить их обратно. Кэши Xcode и модулей также отображаются там, но их нельзя очистить.
