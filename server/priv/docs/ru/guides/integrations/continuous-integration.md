---
{
  "title": "Непрерывная интеграция (CI)",
  "titleTemplate": ":title · Автоматизация · Руководства · Tuist",
  "description": "Узнайте, как использовать Tuist в ваших CI-процессах."
}
---
# Непрерывная интеграция (CI) {#continuous-integration-ci}

Чтобы запускать команды Tuist в ваших рабочих процессах [непрерывной интеграции](https://en.wikipedia.org/wiki/Continuous_integration), необходимо установить её в среде CI. 

Аутентификация необязательна, но требуется, если вы хотите использовать серверные функции, такие как <.localized_link href="/guides/features/cache">кэш</.localized_link>. 

В следующих разделах приведены примеры настройки для различных платформ CI.

## Примеры {#examples}

### GitHub Actions {#github-actions}

В [GitHub Actions](https://docs.github.com/en/actions) можно использовать <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC-аутентификацию</.localized_link> для безопасной аутентификации без секретов:

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
      - run: tuist auth login
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
      - run: tuist auth login
      - run: tuist setup cache
```
```yaml [Project token (Mise)]
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
```yaml [Project token (Homebrew)]
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
> Перед использованием OIDC-аутентификации необходимо <.localized_link href="/guides/integrations/gitforge/github">подключить ваш репозиторий GitHub</.localized_link> к проекту Tuist. Для работы OIDC требуется `permissions: id-token: write`. В качестве альтернативы можно использовать <.localized_link href="/guides/server/authentication#account-tokens">токен аккаунта</.localized_link> с секретом `TUIST_TOKEN`.


> [!TIP]
> Рекомендуем использовать `mise use --pin` в проектах Tuist, чтобы зафиксировать версию Tuist для всех сред. Эта команда создаст файл `.tool-versions`, содержащий версию Tuist.


### Xcode Cloud {#xcode-cloud}

В [Xcode Cloud](https://developer.apple.com/xcode-cloud/), где проекты Xcode являются источником истины, необходимо добавить скрипт [post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) для установки Tuist и запуска нужных команд, например `tuist generate`:

::: code-group

```bash [Mise]
#!/bin/sh

# Mise installation taken from https://mise.jdx.dev/continuous-integration.html#xcode-cloud
curl https://mise.run | sh # Install Mise
export PATH="$HOME/.local/bin:$PATH"

mise install # Installs the version from .mise.toml

# Runs the version of Tuist indicated in the .mise.toml file {#runs-the-version-of-tuist-indicated-in-the-misetoml-file}
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
> Используйте <.localized_link href="/guides/server/authentication#account-tokens">токен аккаунта</.localized_link>, задав переменную окружения `TUIST_TOKEN` в настройках рабочего процесса Xcode Cloud.


### CircleCI {#circleci}

В [CircleCI](https://circleci.com) можно использовать <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC-аутентификацию</.localized_link> для безопасной аутентификации без секретов:

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
          name: Authenticate
          command: mise exec -- tuist auth login
      - run:
          name: Build
          command: mise exec -- tuist setup cache
```
```yaml [Project token (Mise)]
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
> Перед использованием OIDC-аутентификации необходимо <.localized_link href="/guides/integrations/gitforge/github">подключить ваш репозиторий GitHub</.localized_link> к проекту Tuist. Токены CircleCI OIDC включают подключенный репозиторий GitHub, который Tuist использует для авторизации доступа к вашим проектам. В качестве альтернативы можно использовать <.localized_link href="/guides/server/authentication#account-tokens">токен аккаунта</.localized_link> с переменной окружения `TUIST_TOKEN`.


### Bitrise {#bitrise}

В [Bitrise](https://bitrise.io) можно использовать <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC-аутентификацию</.localized_link> для безопасной аутентификации без секретов:

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
          title: Authenticate
          inputs:
            - content: mise exec -- tuist auth login
      - script@1:
          title: Build
          inputs:
            - content: mise exec -- tuist setup cache
```
```yaml [Project token (Mise)]
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
> Перед использованием OIDC-аутентификации необходимо <.localized_link href="/guides/integrations/gitforge/github">подключить ваш репозиторий GitHub</.localized_link> к проекту Tuist. Токены Bitrise OIDC включают подключенный репозиторий GitHub, который Tuist использует для авторизации доступа к вашим проектам. В качестве альтернативы можно использовать <.localized_link href="/guides/server/authentication#account-tokens">токен аккаунта</.localized_link> с переменной окружения `TUIST_TOKEN`.


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
          mise install # Installs the version from .mise.toml
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
> Создайте <.localized_link href="/guides/server/authentication#account-tokens">токен аккаунта</.localized_link> и добавьте его как секретную переменную окружения с именем `TUIST_TOKEN`.

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
> Шаг Tuist Install устанавливает Tuist через Homebrew и запускает `tuist generate`. Задайте входной параметр **Tuist Version**, чтобы зафиксировать версию, затем добавьте шаг Tuist Commands для выполнения таких команд, как `tuist test` или `tuist build`.

> [!NOTE]
> **Аутентификация**
>
> Создайте <.localized_link href="/guides/server/authentication#account-tokens">токен аккаунта</.localized_link>, добавьте его как переменную с именем `TUIST_TOKEN` в [группу переменных окружения](https://docs.appcircle.io/build/build-environment-variables) и выберите эту группу в конфигурации сборки. Отметьте переменную как секретную, нажав значок замка.

## Отчет о запуске {#run-report}

Когда Tuist загружает запуск, URL-адреса панели управления для него выводятся в логи. Чтобы получить их без парсинга логов — например, чтобы отправить ссылку на отчет о тестах в Slack при сбое задачи или передать данные запуска в ваши собственные инструменты — передайте `--run-report-path` (или установите `TUIST_RUN_REPORT_PATH`) в `tuist test`, `tuist xcodebuild test` или `tuist xcodebuild build`. После загрузки запуска Tuist записывает JSON-отчет по указанному пути:

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
| `runURL` | строка | URL-адрес панели управления для запуска. Всегда присутствует. |
| `testRunURL` | строка? | URL-адрес панели управления для запуска тестов, присутствует, если команда выполняла тесты. |
| `buildRunURL` | строка? | URL-адрес панели управления для сборки, присутствует, если команда выполняла сборку. |
| `testRuns` | массив | Результаты тестирования по схемам: `scheme`, `succeeded`, `totalTests`, `skippedTests`, `ranTests`, `failedTestNames`, `ranTestModules` и `skippedTestModules`. Счетчики тестов относятся к тестовым кейсам, а `skippedTests` считает те, которые в отчете помечены как пропущенные. `skippedTestModules` считает модули тестов, пропущенные благодаря <.localized_link href="/guides/features/selective-testing">выборочному тестированию</.localized_link>, и не включается, если выборочное тестирование не применялось или запуск является шардом тестов. |
| `buildRuns` | массив | Результаты сборки по схемам: `scheme`, `succeeded`, `durationInSeconds`. |

`testRunURL` и `buildRunURL` независимы: команда, которая одновременно собирает и тестирует, записывает оба URL, чего не могут сделать логи — они выводят только один URL на запуск.

> [!NOTE]
> **Когда записывается отчет**
>
> Отчет записывается только для запусков, которые загружаются на сервер, что требует аутентификации и происходит автоматически в CI. Путь очищается в начале каждого запуска, поэтому запуск, который не создает отчет, не оставляет ничего, вместо устаревшего отчета от предыдущего запуска.

В GitLab CI распространенный вариант использования — предоставить URL последующим задачам через [отчет `dotenv`](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv):

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
