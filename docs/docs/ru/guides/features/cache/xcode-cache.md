---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# Кэш Xcode {#xcode-cache}

Tuist поддерживает кэш компиляции Xcode, что позволяет командам обмениваться
артефактами компиляции, используя возможности кэширования системы сборки.

## Настройка {#setup}

::: warning ТРЕБОВАНИЯ
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects"> Аккаунт Tuist и
  проект</LocalizedLink>
- Xcode 26.0 или более поздней версии
<!-- -->
:::

Если у вас еще нет учетной записи Tuist и проекта, вы можете создать их,
выполнив следующую команду:

```bash
tuist init
```

После того, как у вас будет файл `Tuist.swift`, ссылающийся на ваш `fullHandle`,
вы можете настроить кэширование для вашего проекта, запустив:

```bash
tuist setup cache
```

Эта команда создает
[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
для запуска локальной службы кэширования при запуске, которую система сборки
Swift [build system](https://github.com/swiftlang/swift-build) использует для
обмена артефактами компиляции. Эту команду необходимо запустить один раз как в
локальной среде, так и в среде CI.

Чтобы настроить кэш на CI, убедитесь, что вы
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">авторизованы</LocalizedLink>.

### Настройте параметры сборки Xcode {#configure-xcode-build-settings}

Добавьте следующие настройки сборки в свой проект Xcode:

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

Обратите внимание, что `COMPILATION_CACHE_REMOTE_SERVICE_PATH` и
`COMPILATION_CACHE_ENABLE_PLUGIN` необходимо добавить в качестве
пользовательских настроек сборки **** , поскольку они не отображаются
непосредственно в интерфейсе настроек сборки Xcode:

::: info SOCKET PATH
<!-- -->
Путь к сокету будет отображаться при запуске `tuist setup cache`. Он основан на
дескрипторе вашего проекта, в котором косые черты заменены подчеркиваниями.
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
Ручная настройка параметров не требуется, если ваш проект сгенерирован Tuist.

В этом случае вам нужно всего лишь добавить `enableCaching: true` в файл
`Tuist.swift`:
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

Чтобы включить кэширование в вашей CI-среде, вам необходимо выполнить ту же
команду, что и в локальной среде: `tuist setup cache`.

Для аутентификации можно использовать либо
<LocalizedLink href="/guides/server/authentication#oidc-tokens">аутентификацию
OIDC</LocalizedLink> (рекомендуется для поддерживаемых поставщиков CI), либо
<LocalizedLink href="/guides/server/authentication#account-tokens">токен учетной
записи</LocalizedLink> через переменную среды `TUIST_TOKEN`.

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

См.
<LocalizedLink href="/guides/integrations/continuous-integration">руководство по
непрерывной интеграции</LocalizedLink> для получения дополнительных примеров,
включая аутентификацию на основе токенов и другие платформы CI, такие как Xcode
Cloud, CircleCI, Bitrise и Codemagic.
