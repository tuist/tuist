---
{
  "title": "Непрерывная интеграция (CI)",
  "titleTemplate": ":title · Автоматизация · Руководства · Tuist",
  "description": "Узнайте, как использовать Tuist в ваших CI-процессах."
}
---
# Непрерывная интеграция (CI) {#continuous-integration-ci}

Чтобы запускать команды Tuist в ваших рабочих процессах [непрерывной интеграции](https://en.wikipedia.org/wiki/Continuous_integration), необходимо установить его в среде CI. 

Аутентификация необязательна, но требуется, если вы хотите использовать серверные функции, такие как <.localized_link href="/guides/features/cache">кэш</.localized_link>. Чтобы сократить время выполнения задач CI и снизить их стоимость после установки Tuist, см. разделы [Медленные сборки](https://tuist.dev/solutions/slow-builds) и [Затраты на CI](https://tuist.dev/solutions/ci-costs).

В следующих разделах приведены примеры настройки для различных платформ CI. Once подключается через собственный нативный провайдер Tuist; ему не требуется CLI Tuist. См. описание этого рабочего процесса в разделе [Once](#once).

## Once {#once}

Зафиксируйте в репозитории конфигурацию провайдера и привязку кэша из руководства <.localized_link href="/guides/get-started/once-project">Начало работы с Once</.localized_link>. Установите Once в задаче, следуя [инструкциям по установке Once](https://buildonce.dev/docs/guide/getting-started), затем выполните аутентификацию перед запуском работ, поддерживающих кэширование.

GitHub Actions, CircleCI и Bitrise поддерживают безинтерактивный вход через OpenID Connect для Once. Подключите репозиторий к проекту Tuist, как описано в разделе <.localized_link href="/guides/server/authentication#oidc-tokens">Аутентификация OIDC</.localized_link>. В GitHub Actions предоставьте разрешение на запись токена удостоверения:

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: jdx/mise-action@v2
      # Pin Once in your repository's mise.toml.
      - run: once auth login --provider tuist --no-browser
      - run: once build MyTarget
      - run: once test
```

Выберите ОС с набором инструментов, требуемым вашим целями. Замените `MyTarget` на имя вашей цели и зафиксируйте версию Once через существующий процесс установки инструментов. Полученная сессия будет повторно использоваться для доступа к кэшу, отчётности и публикации артефактов в ходе задачи.

На других платформах установите `TUIST_TOKEN` в значение <.localized_link href="/guides/server/authentication#account-tokens">токена учётной записи</.localized_link>, авторизованного для необходимых операций. Храните его в хранилище секретов CI, никогда не размещайте в `once.toml` или в исходном коде рабочего процесса. При использовании этого токена интерактивный вход не требуется.

Для наборов с несколькими воркерами следуйте руководству <.localized_link href="/guides/features/test-sharding/once">Шардирование тестов в Once</.localized_link>. Чтобы публиковать приложения, добавьте явный шаг <.localized_link href="/guides/features/previews/once">Публикация превью через Once</.localized_link>. Обычные сборки не публикуют превью автоматически.

## Примеры {#examples}

### GitHub Actions {#github-actions}

В [GitHub Actions](https://docs.github.com/en/actions) можно использовать <.localized_link href="/guides/server/authentication#oidc-tokens">аутентификацию OIDC</.localized_link> для безопасного входа без хранения секретов:

::: code-group
```yaml [OIDC (Mise)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist setup cache
```
```yaml [OIDC (Homebrew)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: brew install --formula tuist@x.y.z
      - run: tuist setup cache
```
```yaml [Account token (Mise)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

env:
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist setup cache
```
```yaml [Account token (Homebrew)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

env:
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: brew install --formula tuist@x.y.z
      - run: tuist setup cache
```
<!-- -->
:::

> [!NOTE]
> **Настройка OIDC**
>
> Перед использованием аутентификации OIDC необходимо <.localized_link href="/guides/integrations/gitforge/github">подключить ваш репозиторий GitHub</.localized_link> к проекту Tuist. Для работы OIDC требуется разрешение `permissions: id-token: write`. Начиная с Tuist 4.218.0, CLI обменивает токен удостоверения при первом запросе, поэтому шаг `tuist auth login` в рабочем процессе не нужен; в более ранних версиях выполняйте `tuist auth login` перед другими командами Tuist. В качестве альтернативы можно использовать <.localized_link href="/guides/server/authentication#account-tokens">токен учётной записи</.localized_link> с секретом `TUIST_TOKEN`.


> [!TIP]
> Рекомендуем использовать `mise use --pin` в проектах Tuist, чтобы зафиксировать версию Tuist для всех сред. Эта команда фиксирует версию Tuist в файле `mise.toml`.


### Xcode Cloud {#xcode-cloud}

В [Xcode Cloud](https://developer.apple.com/xcode-cloud/), где проекты Xcode являются основным источником истины, необходимо добавить скрипт [post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) для установки Tuist и запуска нужных команд, например `tuist generate`:

::: code-group

```bash [Mise]
#!/bin/sh

# Mise installation taken from https://mise.jdx.dev/continuous-integration.html#xcode-cloud
curl https://mise.run | sh # Install Mise
export PATH="$HOME/.local/bin:$PATH"

mise install # Installs the version from mise.toml

# Runs the version of Tuist indicated in the mise.toml file
mise exec -- tuist install --path ../ # `--path` needed as this is run from within the `ci_scripts` directory
mise exec -- tuist generate -p ../ --no-open # `-p` needed as this is run from within the `ci_scripts` directory
```
```bash [Homebrew]
#!/bin/sh
brew install --formula tuist@x.y.z

tuist generate
```
<!-- -->
:::

> [!NOTE]
> **Аутентификация**
>
> Используйте <.localized_link href="/guides/server/authentication#account-tokens">токен учётной записи</.localized_link>, установив переменную окружения `TUIST_TOKEN` в настройках рабочего процесса Xcode Cloud.


### CircleCI {#circleci}

В [CircleCI](https://circleci.com) можно использовать <.localized_link href="/guides/server/authentication#oidc-tokens">аутентификацию OIDC</.localized_link> для безопасного входа без хранения секретов:

::: code-group
```yaml [OIDC (Mise)]
version: 2.1
jobs:
  build:
    macos:
      xcode: "15.0.1"
    steps:
      - checkout
      - run:
          name: Install Mise
          command: |
            curl https://mise.jdx.dev/install.sh | sh
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> $BASH_ENV
      - run:
          name: Install Tuist
          command: mise install
      - run:
          name: Build
          command: mise exec -- tuist setup cache
```
```yaml [Account token (Mise)]
version: 2.1
jobs:
  build:
    macos:
      xcode: "15.0.1"
    environment:
      TUIST_TOKEN: $TUIST_TOKEN
    steps:
      - checkout
      - run:
          name: Install Mise
          command: |
            curl https://mise.jdx.dev/install.sh | sh
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> $BASH_ENV
      - run:
          name: Install Tuist
          command: mise install
      - run:
          name: Build
          command: mise exec -- tuist setup cache
```
<!-- -->
:::

> [!NOTE]
> **Аутентификация**
>
> Перед использованием аутентификации OIDC необходимо <.localized_link href="/guides/integrations/gitforge/github">подключить ваш репозиторий GitHub</.localized_link> к проекту Tuist. Токены OIDC CircleCI содержат информацию о подключённом репозитории GitHub, которую Tuist использует для авторизации доступа к вашим проектам. Начиная с Tuist 4.218.0, CLI обменивает токен удостоверения при первом запросе, поэтому шаг `tuist auth login` не нужен; в более ранних версиях выполняйте `mise exec -- tuist auth login` перед другими командами Tuist. В качестве альтернативы можно использовать <.localized_link href="/guides/server/authentication#account-tokens">токен учётной записи</.localized_link> с переменной окружения `TUIST_TOKEN`.


### Bitrise {#bitrise}

В [Bitrise](https://bitrise.io) можно использовать <.localized_link href="/guides/server/authentication#oidc-tokens">аутентификацию OIDC</.localized_link> для безопасного входа без хранения секретов:

::: code-group
```yaml [OIDC (Mise)]
workflows:
  build:
    steps:
      - git-clone@8: {}
      - script@1:
          title: Install Mise
          inputs:
            - content: |
                curl https://mise.jdx.dev/install.sh | sh
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
      - script@1:
          title: Install Tuist
          inputs:
            - content: mise install
      - get-identity-token@0:
          inputs:
          - audience: tuist
      - script@1:
          title: Build
          inputs:
            - content: mise exec -- tuist setup cache
```
```yaml [Account token (Mise)]
workflows:
  build:
    steps:
      - git-clone@8: {}
      - script@1:
          title: Install Mise
          inputs:
            - content: |
                curl https://mise.jdx.dev/install.sh | sh
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
      - script@1:
          title: Install Tuist
          inputs:
            - content: mise install
      - script@1:
          title: Build
          inputs:
            - content: mise exec -- tuist setup cache
```
<!-- -->
:::

> [!NOTE]
> **Аутентификация**
>
> Перед использованием аутентификации OIDC необходимо <.localized_link href="/guides/integrations/gitforge/github">подключить ваш репозиторий GitHub</.localized_link> к проекту Tuist. Токены OIDC Bitrise содержат информацию о подключённом репозитории GitHub, которую Tuist использует для авторизации доступа к вашим проектам. Начиная с Tuist 4.218.0, CLI обменивает токен удостоверения при первом запросе, поэтому шаг `tuist auth login` не нужен; в более ранних версиях выполняйте `mise exec -- tuist auth login` перед другими командами Tuist. В качестве альтернативы можно использовать <.localized_link href="/guides/server/authentication#account-tokens">токен учётной записи</.localized_link> с переменной окружения `TUIST_TOKEN`.


### Codemagic {#codemagic}

В [Codemagic](https://codemagic.io) можно добавить дополнительный шаг в рабочий процесс для установки Tuist:

::: code-group
```yaml [Mise]
workflows:
  build:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
      vars:
        TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
    scripts:
      - name: Install Mise
        script: |
          curl https://mise.jdx.dev/install.sh | sh
          mise install # Installs the version from mise.toml
      - name: Build
        script: mise exec -- tuist setup cache
```
```yaml [Homebrew]
workflows:
  build:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
      vars:
        TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
    scripts:
      - name: Install Tuist
        script: |
          brew install --formula tuist@x.y.z
      - name: Build
        script: tuist setup cache
```
<!-- -->
:::

> [!NOTE]
> **Аутентификация**
>
> Создайте <.localized_link href="/guides/server/authentication#account-tokens">токен учётной записи</.localized_link> и добавьте его как секретную переменную окружения с именем `TUIST_TOKEN`.

### Appcircle {#appcircle}

В [Appcircle](https://appcircle.io) можно использовать встроенные шаги рабочего процесса [Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install) и [Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands) или добавить шаг **Custom Script** после шага **Git Clone**, чтобы самостоятельно установить Tuist:

::: code-group
```bash [Mise]
cd $AC_REPOSITORY_DIR
curl https://mise.jdx.dev/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
mise install
mise exec -- tuist setup cache
```
```bash [Homebrew]
cd $AC_REPOSITORY_DIR
brew install --formula tuist@x.y.z
tuist setup cache
```
<!-- -->
:::

> [!NOTE]
> **Шаги рабочего процесса**
>
> Шаг Tuist Install устанавливает Tuist через Homebrew и запускает `tuist generate`. Укажите версию в поле ввода **Tuist Version**, чтобы зафиксировать её, а затем добавьте шаг Tuist Commands для выполнения команд, таких как `tuist test` или `tuist build`.

> [!NOTE]
> **Аутентификация**
>
> Создайте <.localized_link href="/guides/server/authentication#account-tokens">токен учётной записи</.localized_link>, добавьте его как переменную с именем `TUIST_TOKEN` в [группу переменных окружения](https://docs.appcircle.io/build/build-environment-variables) и выберите эту группу в конфигурации сборки. Пометьте переменную как секретную, нажав на значок замка.

## Форматирование вывода xcodebuild {#xcodebuild-output-formatting}

`tuist build`, `tuist test`, `tuist xcodebuild build` и `tuist xcodebuild test` форматируют вывод `xcodebuild` с помощью форматтера из [xcbeautify](https://github.com/cpisciotta/xcbeautify), поэтому вам не нужно самостоятельно передавать эти команды через xcbeautify. В GitHub Actions, определяемых по переменной окружения `GITHUB_ACTIONS`, Tuist использует рендерер GitHub Actions от xcbeautify, который выводит предупреждения компилятора, ошибки и сбои тестов как аннотации в сводке запуска и в пул-реквесте. В остальных случаях используется терминальный рендерер с цветным выводом, если только вывод не перенаправляется в конвейер или не установлена переменная `NO_COLOR`.

Передайте `--verbose`, чтобы вывести неформатированный вывод `xcodebuild`, например, когда сборка завершается с ошибкой без явного сообщения об ошибке.

Если задача вызывает `xcodebuild` напрямую, а не через Tuist, самостоятельно передайте вывод через xcbeautify и установите `pipefail`, чтобы сбой сборки приводил к сбою шага:

```bash
set -o pipefail
xcodebuild test -scheme App | xcbeautify --renderer github-actions
```

## Отчёт о запуске {#run-report}

Когда Tuist загружает запуск, URL-адреса дашборда для него выводятся в логи. Чтобы получить их без парсинга логов — например, чтобы отправить ссылку на отчёт о тестах в Slack при сбое задачи или передать данные запуска в ваши собственные инструменты — передайте `--run-report-path` (или установите `TUIST_RUN_REPORT_PATH`) в команды `tuist test`, `tuist xcodebuild test` или `tuist xcodebuild build`. Tuist записывает JSON-отчёт по этому пути после загрузки запуска:

```json
{
  "runId": "0193f8c1-...",
  "status": "success",
  "runURL": "https://tuist.dev/acme/app/runs/0193f8c1-...",
  "testRunURL": "https://tuist.dev/acme/app/tests/test-runs/...",
  "buildRunURL": "https://tuist.dev/acme/app/builds/build-runs/...",
  "testRuns": [
    {
      "scheme": "App",
      "succeeded": true,
      "totalTests": 42,
      "skippedTests": 0,
      "ranTests": 42,
      "failedTestNames": [],
      "ranTestModules": 3,
      "skippedTestModules": 5
    }
  ],
  "buildRuns": [
    { "scheme": "App", "succeeded": true, "durationInSeconds": 12.3 }
  ]
}
```

| Поле | Тип | Описание |
| - | - | - |
| `runId` | строка | Уникальный идентификатор запуска. |
| `status` | строка | `"success"` или `"failure"`. |
| `runURL` | строка | URL-адрес дашборда для запуска. Всегда присутствует. |
| `testRunURL` | строка? | URL-адрес дашборда для запуска тестов, присутствует, если команда выполняла тесты. |
| `buildRunURL` | строка? | URL-адрес дашборда для запуска сборки, присутствует, если команда выполняла сборку. |
| `testRuns` | массив | Результаты тестов по схемам: `scheme`, `succeeded`, `totalTests`, `skippedTests`, `ranTests`, `failedTestNames`, `ranTestModules` и `skippedTestModules`. Счётчики тестов относятся к тест-кейсам, а `skippedTests` считает те, которые пакет результатов отмечает как пропущенные. `skippedTestModules` считает модули тестов, пропущенные <.localized_link href="/guides/features/selective-testing">выборочным тестированием</.localized_link>, и опускается, если выборочное тестирование не применялось или запуск является шардом тестов. |
| `buildRuns` | массив | Результаты сборки по схемам: `scheme`, `succeeded`, `durationInSeconds`. |

`testRunURL` и `buildRunURL` независимы: команда, которая одновременно выполняет сборку и тесты, записывает оба URL, чего не могут сделать логи — они выводят только один URL на запуск.

> [!NOTE]
> **Когда записывается отчёт**
>
> Отчёт записывается только для запусков, которые загружаются на сервер, что требует аутентификации и происходит автоматически в CI. Путь очищается в начале каждого запуска, поэтому запуск, не создавший отчёт, не оставляет старых данных от предыдущего запуска.

В GitLab CI распространённым вариантом использования является предоставление URL последующим задачам через [отчёт `dotenv`](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv):

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
