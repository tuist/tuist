---
{
  "title": "Swift",
  "titleTemplate": ":title · Реестры пакетов · Возможности · Руководства · Tuist",
  "description": "Ускорьте разрешение зависимостей Swift Package Manager с минут до секунд благодаря реестру пакетов Swift от Tuist, работающему на основе глобальной сети кэширования Tuist."
}
---
# Реестр пакетов Swift {#swift-package-registry}

По мере роста числа зависимостей увеличивается и время на их разрешение. В то время как другие менеджеры пакетов, такие как [CocoaPods](https://cocoapods.org/) или [npm](https://www.npmjs.com/), являются централизованными, Swift Package Manager — нет. Из-за этого SwiftPM приходится разрешать зависимости, выполняя глубокое клонирование каждого репозитория, что может занимать много времени и потреблять больше памяти по сравнению с централизованным подходом. Чтобы решить эту проблему, Tuist предоставляет реализацию [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md), позволяющую скачивать только те коммиты, которые вам _действительно нужны_. Пакеты в реестре основаны на данных из [Swift Package Index](https://swiftpackageindex.com/): если вы можете найти пакет там, он также доступен в реестре Tuist. Кроме того, пакеты распространяются по всему миру с использованием edge-хранилища для обеспечения минимальной задержки при их разрешении.

## Использование {#usage}

Существует два способа настройки реестра:

### Вариант 1: Автоматическая настройка во время генерации (рекомендуется) {#automatic-setup}

Если вы используете Tuist для генерации проекта, вы можете включить реестр, установив опцию `registryEnabled` в конфигурации `Tuist.swift`:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            registryEnabled: true
        )
    )
)
```

При включении этой опции `tuist generate` автоматически создаст файл конфигурации реестра в вашем рабочем пространстве. Это избавляет от необходимости отдельно запускать `tuist registry setup`.

> [!TIP]
> `registryEnabled` также настраивает реестр для проектов, которые интегрируют зависимости через стандартную интеграцию Swift Package Manager в Xcode, а не через интеграцию на основе XcodeProj в Tuist. Эта опция не настраивает Xcode на разрешение пакетов, объявленных с URL-адресом системы контроля версий из реестра. Для этого выполните `tuist registry setup` один раз на каждой машине, как описано в разделе <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">Разрешение пакетов из системы контроля версий</.localized_link>.


### Вариант 2: Ручная настройка {#manual-setup}

Чтобы настроить реестр вручную, выполните следующую команду в каталоге вашего проекта:

```bash
tuist registry setup
```

Эта команда генерирует файл конфигурации реестра, который включает реестр для вашего проекта. Убедитесь, что этот файл зафиксирован в системе контроля версий, чтобы ваша команда также могла пользоваться преимуществами реестра.

### Аутентификация (необязательно) {#authentication}

Аутентификация является **необязательной**. Без аутентификации вы можете использовать реестр с ограничением частоты запросов **1000 запросов в минуту** на один IP-адрес. Чтобы получить более высокое ограничение в **20 000 запросов в минуту**, вы можете пройти аутентификацию, выполнив команду:

```bash
tuist registry login
```

> [!NOTE]
> Для аутентификации требуется <.localized_link href="/guides/server/accounts-and-projects">учетная запись и проект Tuist</.localized_link>.


### Разрешение зависимостей {#resolving-dependencies}

Чтобы разрешать зависимости из реестра вместо системы контроля версий, продолжайте чтение в соответствии с настройками вашего проекта:
- <.localized_link href="/guides/features/package-registries/swift/xcode-project">Xcode project</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/generated-project">Generated project with the Xcode package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/xcodeproj-integration">Generated project with the XcodeProj-based package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/swift-package">Swift package</.localized_link>

Чтобы настроить реестр в CI, следуйте этому руководству: <.localized_link href="/guides/features/package-registries/swift/continuous-integration">Непрерывная интеграция</.localized_link>.

### Идентификаторы реестра пакетов {#package-registry-identifiers}

При использовании идентификаторов реестра пакетов в файле `Package.swift` или `Project.swift` необходимо преобразовать URL-адрес пакета в формат реестра. Идентификатор реестра всегда имеет вид `{organization}.{repository}`. Например, чтобы использовать реестр для пакета `https://github.com/pointfreeco/swift-composable-architecture`, идентификатор реестра будет `pointfreeco.swift-composable-architecture`.

> [!NOTE]
> Идентификатор не может содержать более одной точки. Если имя репозитория содержит точку, она заменяется на символ подчеркивания. Например, пакет `https://github.com/groue/GRDB.swift` будет иметь идентификатор реестра `groue.GRDB_swift`.
