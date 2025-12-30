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

::: предупреждение РЕКВИЗИТЫ
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Туистский счет и проект</LocalizedLink>
- Xcode 26.0 или более поздняя версия
<!-- -->
:::

Если у вас еще нет учетной записи Tuist и проекта, вы можете создать их,
выполнив команду:

```bash
tuist init
```

Когда у вас есть файл `Tuist.swift`, ссылающийся на ваш `fullHandle`, вы можете
настроить кэширование для своего проекта, выполнив команду:

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

Кроме того, необходимо убедиться, что переменная окружения `TUIST_TOKEN`
установлена. Вы можете создать ее, следуя документации
<LocalizedLink href="/guides/server/authentication#as-a-project">здесь</LocalizedLink>.
Переменная окружения `TUIST_TOKEN` _ должна_ присутствовать на вашем шаге
сборки, но мы рекомендуем установить ее для всего рабочего процесса CI.

Пример рабочего процесса для GitHub Actions может выглядеть следующим образом:
```yaml
name: Build

env:
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    steps:
      - # Your set up steps...
      - name: Set up Tuist Cache
        run: tuist setup cache
      - # Your build steps
```
