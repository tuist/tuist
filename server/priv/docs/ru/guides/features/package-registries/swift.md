---
{
  "title": "Swift",
  "titleTemplate": ":title · Реестры пакетов · Возможности · Руководства · Tuist",
  "description": "Ускорьте разрешение зависимостей Swift Package Manager с минут до секунд благодаря реестру пакетов Swift от Tuist, работающему на основе глобальной сети кэширования Tuist."
}
---
# Реестр пакетов Swift {#swift-package-registry}

С ростом числа зависимостей увеличивается и время их разрешения. В отличие от других менеджеров пакетов, таких как [CocoaPods](https://cocoapods.org/) или [npm](https://www.npmjs.com/), которые являются централизованными, Swift Package Manager не использует такой подход. Из-за этого SwiftPM вынужден разрешать зависимости, выполняя полное клонирование каждого репозитория, что занимает много времени и требует больше памяти по сравнению с централизованным решением. Чтобы решить эту проблему, Tuist предоставляет реализацию [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md), позволяющую загружать только те коммиты, которые вам _действительно нужны_. Пакеты в реестре основаны на данных из [Swift Package Index](https://swiftpackageindex.com/): если пакет доступен там, он также присутствует в реестре Tuist. Кроме того, пакеты распространяются по всему миру через edge-хранилище, что обеспечивает минимальную задержку при их разрешении.

## Использование {#usage}

Есть два способа настроить реестр:

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
> `registryEnabled` также настраивает реестр для проектов, которые интегрируют зависимости через стандартную интеграцию Swift Package Manager в Xcode, а не через интеграцию на основе XcodeProj от Tuist. Эта опция не настраивает Xcode на разрешение пакетов, объявленных с URL-адресом системы контроля версий из реестра. Для этого выполните `tuist registry setup` один раз на каждой машине, как описано в разделе <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">Разрешение пакетов из системы контроля версий</.localized_link>.


### Вариант 2: Ручная настройка {#manual-setup}

Чтобы настроить реестр вручную, выполните следующую команду в директории вашего проекта:

```bash
tuist registry setup
```

Эта команда создает файл конфигурации реестра, который включает его для вашего проекта. Убедитесь, что этот файл закоммичен, чтобы ваша команда также могла использовать реестр.

### Аутентификация (необязательно) {#authentication}

Аутентификация является **необязательной**. Без аутентификации вы можете использовать реестр с ограничением частоты запросов **1000 запросов в минуту** на один IP-адрес. Чтобы получить более высокий лимит **20 000 запросов в минуту**, выполните аутентификацию, запустив:

```bash
tuist registry login
```

> [!NOTE]
> Для аутентификации требуется <.localized_link href="/guides/server/accounts-and-projects">аккаунт и проект Tuist</.localized_link>.


### Разрешение зависимостей {#resolving-dependencies}

Чтобы разрешать зависимости из реестра вместо системы контроля версий, выберите инструкцию в соответствии с настройками вашего проекта:
- <.localized_link href="/guides/features/package-registries/swift/xcode-project">Xcode project</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/generated-project">Generated project with the Xcode package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/xcodeproj-integration">Generated project with the XcodeProj-based package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/swift-package">Swift package</.localized_link>

Чтобы настроить реестр в CI, следуйте этому руководству: <.localized_link href="/guides/features/package-registries/swift/continuous-integration">Непрерывная интеграция</.localized_link>.

### Идентификаторы реестра пакетов {#package-registry-identifiers}

При использовании идентификаторов реестра пакетов в файлах `Package.swift` или `Project.swift` необходимо преобразовать URL пакета в формат реестра. Идентификатор реестра всегда имеет вид `{organization}.{repository}`. Например, для использования реестра с пакетом `https://github.com/pointfreeco/swift-composable-architecture` идентификатор будет `pointfreeco.swift-composable-architecture`.

> [!NOTE]
> Идентификатор не может содержать более одной точки. Если имя репозитория содержит точку, она заменяется на символ подчеркивания. Например, пакет `https://github.com/groue/GRDB.swift` будет иметь идентификатор реестра `groue.GRDB_swift`.
