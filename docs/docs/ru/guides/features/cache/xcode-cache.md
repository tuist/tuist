---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# Кэш Xcode {#xcode-cache}

Tuist обеспечивает поддержку кэша компиляции Xcode, что позволяет командам
обмениваться артефактами компиляции, используя возможности кэширования системы
сборки.

## Настройка {#setup}

::: warning ТРЕБОВАНИЯ
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects"> Аккаунт Tuist и
  проект</LocalizedLink>
- Xcode 26.0 или более поздняя версия
<!-- -->
:::

Если у вас еще нет учетной записи Tuist и проекта, вы можете создать их,
выполнив команду:

```bash
tuist init
```

После того как у вас есть файл `Tuist.swift`, ссылающийся на ваш `fullHandle`,
вы можете настроить кэширование для вашего проекта, выполнив команду:

```bash
tuist setup cache
```

Эта команда создает
[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
для запуска локальной службы кэширования при запуске, которую [система сборки
Swift](https://github.com/swiftlang/swift-build) использует для обмена
артефактами компиляции. Эту команду нужно выполнить один раз в локальной и
CI-средах.

Чтобы настроить кэш на CI, убедитесь, что вы прошли
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">аутентификацию</LocalizedLink>.

### Настройка параметров сборки Xcode {#configure-xcode-build-settings}

Добавьте следующие настройки сборки в свой проект Xcode:

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

Обратите внимание, что `COMPILATION_CACHE_REMOTE_SERVICE_PATH` и
`COMPILATION_CACHE_ENABLE_PLUGIN` должны быть добавлены как **пользовательские
настройки сборки**, поскольку они не отображаются непосредственно в
пользовательском интерфейсе настроек сборки Xcode:

::: info SOCKET PATH
<!-- -->
Путь к сокету будет отображаться при запуске `tuist setup cache`. Он основан на
полном дескрипторе вашего проекта с заменой косых черт на подчеркивания.
<!-- -->
:::

Вы также можете указать эти настройки при запуске `xcodebuild`, добавив
следующие флаги, например:

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/your_org_your_project.sock \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
```

::: info GENERATED PROJECTS
<!-- -->
Задавать настройки вручную не нужно, если ваш проект сгенерирован Tuist.

В этом случае достаточно добавить `enableCaching: true` в файл `Tuist.swift`:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```
<!-- -->
:::

### Непрерывная интеграция {#continuous-integration}

Чтобы включить кэширование в среде CI, нужно выполнить ту же команду, что и в
локальных средах: `tuist setup cache`.

Для аутентификации можно использовать либо
<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC-аутентификацию</LocalizedLink>
(рекомендуется для поддерживаемых CI-провайдеров), либо
<LocalizedLink href="/guides/server/authentication#account-tokens">токен учетной
записи</LocalizedLink> через переменную окружения `TUIST_TOKEN`.

Пример рабочего процесса для GitHub Actions с использованием аутентификации
OIDC:
```yaml
name: Build

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
      - # Your build steps
```

Дополнительные примеры см. в руководстве
<LocalizedLink href="/guides/integrations/continuous-integration">Continuous
Integration</LocalizedLink>, включая аутентификацию на основе токенов и другие
CI-платформы, такие как Xcode Cloud, CircleCI, Bitrise и Codemagic.
