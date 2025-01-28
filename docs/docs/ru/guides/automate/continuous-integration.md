---
title: Непрерывная интеграция (CI)
titleTemplate: :title · Разработка · Руководства · Tuist
description: Узнайте, как использовать Tuist в ваших рабочих процессах CI.
---

# Непрерывная интеграция (CI) {#continuous-integration-ci}

Вы можете использовать Tuist в окружениях [непрерывной интеграции](https://ru.wikipedia.org/wiki/%D0%9D%D0%B5%D0%BF%D1%80%D0%B5%D1%80%D1%8B%D0%B2%D0%BD%D0%B0%D1%8F_%D0%B8%D0%BD%D1%82%D0%B5%D0%B3%D1%80%D0%B0%D1%86%D0%B8%D1%8F). В следующих разделах приведены примеры того, как это можно сделать на различных платформах CI.

## Примеры {#examples}

Чтобы запускать Tuist команды в ваших рабочих процессах CI, вам нужно установить Tuist в вашей среде CI.

### Xcode Cloud {#xcode-cloud}

В [Xcode Cloud](https://developer.apple.com/xcode-cloud/), который использует Xcode проекты, вам нужно будет добавить [post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) скрипт для установки Tuist и запуска необходимых команд, например `tuist generate`:

:::code-group

```bash [Mise]
#!/bin/sh
curl https://mise.jdx.dev/install.sh | sh
mise install # Installs the version from .mise.toml

# Runs the version of Tuist indicated in the .mise.toml file {#runs-the-version-of-tuist-indicated-in-the-misetoml-file}
mise exec -- tuist generate
```

```bash [Homebrew]
#!/bin/sh
brew install --formula tuist@x.y.z

tuist generate
```

:::

### Codemagic {#codemagic}

В [Codemagic](https://codemagic.io) вы можете добавить дополнительный шаг в рабочий процесс для установки Tuist:

::: code-group

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

### GitHub Actions {#github-actions}

On [GitHub Actions](https://docs.github.com/en/actions) you can add an additional step to install Tuist, and in the case of managing the installation of Mise, you can use the [mise-action](https://github.com/jdx/mise-action), which abstracts the installation of Mise and Tuist:

::: code-group

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

:::tip
Мы рекомендуем использовать `mise use --pin` в ваших проектах, чтобы закрепить версию Tuist в разных окружениях. Команда создаст файл `.tool-versions`, содержащий версию Tuist.
:::

## Аутентификация {#authentication}

При использовании серверных функций, таких как <LocalizedLink href="/guides/develop/build/cache">cache</LocalizedLink>, вам понадобится способ аутентификации запросов, идущих с ваших рабочих процессов CI на сервер. Для этого можно сгенерировать токен, привязанный к проекту, выполнив следующую команду:

```bash
tuist project tokens create my-handle/MyApp
```

Команда создаст токен для проекта с полным названием `my-account/my-project`. Установите значение переменной окружения
`TUIST_CONFIG_TOKEN` в вашей среде CI, так что бы она не была раскрыта.

> [!IMPORTANT] ОБНАРУЖЕНИЕ СРЕДЫ CI
> Tuist использует токен только в том случае, если обнаруживает, что работает в среде CI. Если ваше окружение CI не обнаружено, вы можете принудительно использовать токен, установив переменную окружения `CI` в значение `1`.
