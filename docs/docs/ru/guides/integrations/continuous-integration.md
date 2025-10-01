---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# Непрерывная интеграция (CI) {#continuous-integration-ci}

Вы можете использовать Tuist в средах [непрерывной
интеграции](https://en.wikipedia.org/wiki/Continuous_integration). В следующих
разделах приведены примеры того, как это сделать на различных платформах CI.

## Примеры {#examples}

Чтобы выполнять команды Tuist в рабочих процессах CI, вам нужно установить его в
среду CI.

### Xcode Cloud {#xcode-cloud}

В [Xcode Cloud](https://developer.apple.com/xcode-cloud/), который использует
проекты Xcode в качестве источника истины, вам нужно будет добавить скрипт
[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)
для установки Tuist и запуска необходимых команд, например `tuist generate`:

:::код-группа

```bash [Mise]
#!/bin/sh

# Mise installation taken from https://mise.jdx.dev/continuous-integration.html#xcode-cloud
curl https://mise.run | sh # Install Mise
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
:::
### Codemagic {#codemagic}

В [Codemagic](https://codemagic.io) вы можете добавить дополнительный шаг в
рабочий процесс для установки Tuist:

::: кодовая группа
```yaml [Mise]
workflows:
  lint:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
    scripts:
      - name: Install Mise
        script: |
          curl https://mise.jdx.dev/install.sh | sh
          mise install # Installs the version from .mise.toml
      - name: Build
        script: mise exec -- tuist build
```
```yaml [Homebrew]
workflows:
  lint:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
    scripts:
      - name: Install Tuist
        script: |
          brew install --formula tuist@x.y.z
      - name: Build
        script: tuist build
```
:::

### Действия GitHub {#github-actions}

В [GitHub Actions](https://docs.github.com/en/actions) вы можете добавить
дополнительный шаг для установки Tuist, а в случае управления установкой Mise
можно использовать [mise-action](https://github.com/jdx/mise-action), который
абстрагирует установку Mise и Tuist:

::: кодовая группа
```yaml [Mise]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main
jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: jdx/mise-action@v2
      - run: tuist build
```
```yaml [Homebrew]
name: test
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main
jobs:
  lint:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - run: brew install --formula tuist@x.y.z
      - run: tuist build
```
:::

::: Совет Мы рекомендуем использовать команду `mise use --pin` в проектах Tuist,
чтобы зафиксировать версию Tuist в разных средах. Команда создаст файл
`.tool-versions`, содержащий версию Tuist. :::

## Аутентификация {#authentication}

При использовании серверных функций, таких как
<LocalizedLink href="/guides/features/cache">cache</LocalizedLink>, вам
понадобится способ аутентификации запросов, идущих от ваших рабочих процессов CI
к серверу. Для этого можно сгенерировать токен, привязанный к проекту, выполнив
следующую команду:

```bash
tuist project tokens create my-handle/MyApp
```

Команда сгенерирует токен для проекта с полным именем `my-account/my-project`.
Установите значение переменной окружения `TUIST_CONFIG_TOKEN` в вашей среде CI,
убедившись, что она настроена как секретная, чтобы ее нельзя было раскрыть.

> [!ВАЖНО] ОБНАРУЖЕНИЕ СРЕДЫ CI Tuist использует токен только в том случае, если
> обнаруживает, что работает в среде CI. Если ваше CI-окружение не обнаружено,
> вы можете принудительно использовать токен, установив переменную окружения
> `CI` в значение `1`.
