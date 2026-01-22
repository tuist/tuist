---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# Непрерывная интеграция (CI) {#continuous-integration-ci}

Чтобы запускать команды Tuist в ваших рабочих процессах [непрерывной
интеграции](https://en.wikipedia.org/wiki/Continuous_integration), вам
необходимо установить его в вашей среде CI.

Аутентификация не является обязательной, но требуется, если вы хотите
использовать серверные функции, такие как
<LocalizedLink href="/guides/features/cache">cache</LocalizedLink>.

В следующих разделах приведены примеры того, как это сделать на разных
платформах CI.

## Примеры {#examples}

### GitHub Actions {#github-actions}

В [GitHub Actions](https://docs.github.com/en/actions) вы можете использовать
<LocalizedLink href="/guides/server/authentication#oidc-tokens">аутентификацию
OIDC</LocalizedLink> для безопасной аутентификации без секретных данных:

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

::: info OIDC SETUP
<!-- -->
Перед использованием аутентификации OIDC необходимо
<LocalizedLink href="/guides/integrations/gitforge/github">подключить
репозиторий GitHub</LocalizedLink> к проекту Tuist. Для работы OIDC требуются
разрешения `: id-token: write`. В качестве альтернативы можно использовать
<LocalizedLink href="/guides/server/authentication#account-tokens">токен учетной
записи</LocalizedLink> с секретным ключом `TUIST_TOKEN`.
<!-- -->
:::

::: tip
<!-- -->
Мы рекомендуем использовать `mise use --pin` в ваших проектах Tuist, чтобы
закрепить версию Tuist во всех средах. Команда создаст файл `.tool-versions`,
содержащий версию Tuist.
<!-- -->
:::

### Xcode Cloud {#xcode-cloud}

В [Xcode Cloud](https://developer.apple.com/xcode-cloud/), который использует
проекты Xcode в качестве источника достоверной информации, вам нужно будет
добавить скрипт
[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script),
чтобы установить Tuist и запустить необходимые команды, например `tuist
generate`:

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

::: info AUTHENTICATION
<!-- -->
Используйте
<LocalizedLink href="/guides/server/authentication#account-tokens">токен учетной
записи</LocalizedLink>, установив переменную среды `TUIST_TOKEN` в настройках
рабочего процесса Xcode Cloud.
<!-- -->
:::

### CircleCI {#circleci}

В [CircleCI](https://circleci.com) вы можете использовать
<LocalizedLink href="/guides/server/authentication#oidc-tokens">аутентификацию
OIDC</LocalizedLink> для безопасной аутентификации без секретных данных:

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

::: info AUTHENTICATION
<!-- -->
Перед использованием аутентификации OIDC необходимо
<LocalizedLink href="/guides/integrations/gitforge/github">подключить
репозиторий GitHub</LocalizedLink> к проекту Tuist. Токены CircleCI OIDC
включают подключенный репозиторий GitHub, который Tuist использует для
авторизации доступа к вашим проектам. В качестве альтернативы можно использовать
<LocalizedLink href="/guides/server/authentication#account-tokens">токен учетной
записи</LocalizedLink> с переменной среды `TUIST_TOKEN`.
<!-- -->
:::

### Bitrise {#bitrise}

На [Bitrise](https://bitrise.io) вы можете использовать
<LocalizedLink href="/guides/server/authentication#oidc-tokens">аутентификацию
OIDC</LocalizedLink> для безопасной аутентификации без секретных данных:

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

::: info AUTHENTICATION
<!-- -->
Перед использованием аутентификации OIDC необходимо
<LocalizedLink href="/guides/integrations/gitforge/github">подключить
репозиторий GitHub</LocalizedLink> к проекту Tuist. Токены Bitrise OIDC включают
подключенный репозиторий GitHub, который Tuist использует для авторизации
доступа к вашим проектам. В качестве альтернативы можно использовать
<LocalizedLink href="/guides/server/authentication#account-tokens">токен учетной
записи</LocalizedLink> с переменной среды `TUIST_TOKEN`.
<!-- -->
:::

### Codemagic {#codemagic}

В [Codemagic](https://codemagic.io) вы можете добавить дополнительный шаг в свой
рабочий процесс, чтобы установить Tuist:

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

::: info AUTHENTICATION
<!-- -->
Создайте
<LocalizedLink href="/guides/server/authentication#account-tokens">токен учетной
записи</LocalizedLink> и добавьте его в качестве секретной переменной среды с
именем `TUIST_TOKEN`.
<!-- -->
:::
