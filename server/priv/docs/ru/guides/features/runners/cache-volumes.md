---
{
  "title": "Кэширующие тома",
  "titleTemplate": ":title · Раннеры · Возможности · Руководства · Tuist",
  "description": "Сохраняйте кэши Xcode, модулей и Gradle, а также любые другие директории между задачами раннеров Tuist на Linux или macOS в GitHub Actions, Buildkite и GitLab CI."
}
---
# Тома кэша {#cache-volumes}

Раннеры Tuist могут сохранять кэш между заданиями, чтобы новый раннер начинал работу с «разогретым» кэшем. Каждое задание получает приватную копию последних сохранённых данных с правами на запись.

- **Управляемые кэши** сохраняют кэш компиляции Xcode, модульный кэш Tuist и кэши Gradle — каждый в одном шаге. Tuist знает, где находится каждый кэш, и хранит его в своём хранилище.
- **Пользовательские тома** сохраняют любые другие директории, например кэш загрузок менеджера пакетов, под выбранным вами ключом.

Добавьте шаги после checkout и перед командами, которые используют кэши. На раннерах, не являющихся раннерами Tuist, они ничего не делают, а проблемы с кэшем никогда не приводят к падению задания: шаг логирует предупреждение, и задание продолжается с пустым кэшем.

## Управляемые кэши {#managed-caches}

Шаги лишь определяют, где находятся кэши. Сохраните существующую настройку кэша: `tuist setup cache` или настройки сборки, включающие кэш компиляции (см. <.localized_link href="/guides/features/cache/xcode-cache">руководство по кэшу Xcode</.localized_link>), аутентификацию для модульного кэша и <.localized_link href="/guides/features/cache/gradle-cache">плагин Tuist для Gradle</.localized_link> для удалённого кэша сборки Gradle. В GitLab CI объединяйте фрагменты с помощью `!reference`, потому что `extends` заменяет `before_script`.

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

### Модульный кэш {#module-cache}

Сохраняет локальный кэш Tuist на раннерах macOS: бинарные файлы <.localized_link href="/guides/features/cache/module-cache">модульного кэша</.localized_link>, скомпилированные манифесты, плагины и результаты выборочного тестирования.

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

Выберите стабильный `key` и `path`, затем подключите том перед установкой зависимостей. Путь должен быть пустым или отсутствовать. Удалите любое кэширование архивов или восстановление артефактов, которое записывает данные в ту же директорию. Чтобы сохранить несколько директорий в одном томе, см. [Несколько директорий в одном томе](#several-directories-in-one-volume).

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

Том может содержать несколько директорий. В GitHub Actions перечислите по одному пути на строку; в Buildkite задайте `path` как список; в GitLab CI передавайте `--path` один раз для каждой директории. Пустые строки и окружающие пробельные символы игнорируются.

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
- **Группируйте небольшие связанные директории.** Выделите отдельный том для большой или часто меняющейся директории.
- **Без вложенности.** Пути в одном томе не должны содержать друг друга.
- **Изменение списка начинает с холодного старта.** Каждый путь хранится в своей собственной директории внутри тома, идентифицируемой по тому, как записан путь. Переключение между одним путём и несколькими, а также добавление, удаление или перезапись пути меняет эту структуру: первое задание после изменения начинает с холодного старта для затронутых путей. Содержимое путей, которые больше не указаны, остаётся в томе, пока вы его не очистите.

### Как работают ключи {#how-keys-work}

Ключ именует том, который меняется со временем; это не имя фиксированного снимка, как ключ `actions/cache`.

- **Один том на ключ.** Каждый ключ ограничен репозиторием (в Buildkite — пайплайном; в GitLab CI — проектом), платформой, архитектурой процессора и пользователем. Каждое задание, подключающее его, начинает с последних сохранённых данных, а подходящие задания сохраняют свои изменения обратно в тот же том.
- **Держите ключи стабильными.** Не включайте версии или хеши lock-файлов в ключ. С `actions/cache` ключ вида `deps-${{ hashFiles('Package.resolved') }}` создаёт новую запись при каждом изменении, а `restore-keys` откатывается к более старой. Здесь новый ключ — это новый пустой том: первое задание после каждого изменения начинает с холодного старта, а старые тома остаются до истечения срока их действия. Оставьте ключ неизменным и позвольте инструменту обновлять содержимое; менеджеры пакетов повторно используют всё, что ещё актуально.
- **Нет частичных совпадений.** Ключей восстановления нет. Ключ, который ещё не был сохранён, начинается пустым.
- **Намеренный сброс.** Измените ключ или очистите том в панели управления, если хотите, чтобы задание начиналось с пустого состояния.
- **Оставьте ключи `tuist-` для Tuist.** Управляемые кэши используют ключи, начинающиеся с `tuist-`, поэтому выберите другое имя для своих томов.

В Linux пути монтируются как обычные директории, поэтому инструменты могут использовать свои обычные расположения, такие как `deps`, `_build` и `node_modules`. Сохраняйте обычные правила `.gitignore`. В macOS пути являются символическими ссылками: используйте кэши загрузок, такие как `~/.npm`; `node_modules` и инструменты, заменяющие свою директорию кэша, не поддерживаются. Игнорируйте ссылки на рабочую область без завершающего слэша в `.gitignore`.

## Сохранение изменений {#saving-changes}

Управляемые кэши и пользовательские тома сохраняют изменения успешных заданий из вашего репозитория на любой ветке:

| Провайдер | Задания, сохраняющие изменения |
| --- | --- |
| GitHub Actions | Задания push, по расписанию, ручного запуска и pull request из самого репозитория |
| Buildkite | Сборки по вебхуку и расписанию репозитория пайплайна, включая его pull request |
| GitLab CI | Push-сборки, сборки по расписанию и веб-пайплайны проекта, а также пайплайны его собственных merge request, если подключение имеет <.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">токен доступа к API</.localized_link> |

Другие задания могут использовать кэш, но их изменения отбрасываются. К ним относятся pull request из форков, задания `pull_request_target`, сборки Buildkite, запущенные через API или панель управления, merge request в GitLab из форков или без токена доступа к API, а также теги. Задание, которое не изменяет том, оставляет сохранённую версию на месте. Вы можете ограничить ветки, сохраняющие данные, в профиле раннера; см. [Выбор веток для сохранения](#choose-which-branches-save).

Параллельные задания работают независимо; изменения от разных заданий не объединяются. Никогда не кэшируйте учётные данные или незаменимые данные.

### Выбор веток для сохранения {#choose-which-branches-save}

Вы можете изменить, какие ветки сохраняют управляемые кэши и пользовательские тома. Откройте **Runners → Profiles**, отредактируйте профиль, который используют ваши задания, и разверните раздел **Save cache from**. Задания используют запрошенный ими профиль: в `runs-on:` для GitHub Actions, в качестве очереди для Buildkite или в `tags:` для GitLab CI. Настройки применяются ко всем томам, используемым заданиями этого профиля, включая тома, созданные позже.

![Форма профиля раннера с развернутым разделом Save cache from, где включена Default branch и добавлены develop и release/* как дополнительные ветки](/images/guides/features/runners/save-cache-from.png)

По умолчанию каждое успешное задание из репозитория сохраняет свои изменения. Чтобы сохранять данные только из некоторых веток, включите **Limit to specific branches**:

- **Default branch** позволяет заданиям на основной ветке каждого репозитория сохранять данные. Отключите этот параметр, чтобы сохранять данные только из дополнительных веток.
- В разделе **Additional branches** добавьте до 20 имён веток, которые также будут сохранять данные. Используйте `*` в качестве подстановочного знака: `release/*` соответствует `release/1.0`.

Задания, перечисленные в разделе [Сохранение изменений](#saving-changes), сохраняют свои изменения, если их ветка совпадает. В GitHub Actions при push и ручном запуске тег с подходящим именем также считается совпадением.

Задания на других ветках всё ещё могут использовать кэш, но их изменения отбрасываются. Задания, которые никогда не сохраняют данные, например pull request из форков, не сохраняют данные даже на совпадающей ветке. Сужение этих настроек или удаление профиля приводит к отмене ожидающих изменений, которые они больше не разрешают; удалённый профиль возвращается к сохранению данных из всех веток.

## Ёмкость и хранение {#capacity-and-retention}

Кэш Xcode начинается с **30 ГБ**. Кэш модулей, кэш Gradle и каждый пользовательский том начинаются с **20 ГБ**. Укажите размер, чтобы задать кэшу или тому другую ёмкость, целое число ГБ от `1gb` до `100gb`:

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

Кэш Gradle и пользовательские тома принимают тот же входной параметр `size` (`TUIST_GRADLE_CACHE_SIZE` и `TUIST_VOLUME_SIZE` в GitLab CI, `--size` для `tuist-cache-volume`). Больший размер увеличивает том, сохраняя его содержимое, начиная со следующего задания. Меньший размер применяется после следующей очистки тома или его истечения срока действия. Когда задания запрашивают разные размеры одного кэша, применяется наибольший, поэтому указывайте каждый размер в одном месте.

Все они истекают через **7 дней без монтирования заданием**, и следующее задание начинается с пустого тома после истечения срока. Tuist очищает кэши Xcode и модулей, чтобы уложиться в их ёмкость, а шаг кэша Gradle заставляет Gradle удалять записи, не использовавшиеся семь дней, после каждой сборки.

Пользовательские тома не очищают старые зависимости: используйте настройки очистки вашего инструмента, чтобы поддерживать их небольшой размер. Запись в полный том может привести к сбою задания. Когда сохранённое содержимое достигает **80%** ёмкости тома и у задания заканчивается место на нём, следующее задание начинается с пустого тома, а его изменения начинают новое сохранённое состояние.

## Просмотр и очистка томов {#inspecting-and-clearing-volumes}

Откройте **Runners → Volumes**, чтобы просмотреть использованное пространство, процент попаданий в кэш и историю заданий. Администраторы аккаунта могут выбрать **Clear volume**, чтобы будущие задания начинались с пустого состояния. Выполняющиеся задания сохраняют свои частные копии, но не могут сохранить их обратно. Кэши Xcode и модулей также отображаются там, но их нельзя очистить.
