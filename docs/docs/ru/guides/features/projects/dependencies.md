---
{
  "title": "Dependencies",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to declare dependencies in your Tuist project."
}
---
# Зависимости {#dependencies}

Когда проект разрастается, его принято разделять на несколько таргетов для
совместного использования кода, определения границ и улучшения времени сборки.
Множество целей означает определение зависимостей между ними, формируя **граф
зависимостей**, который может включать и внешние зависимости.

## XcodeProj-кодифицированные графы {#xcodeprojcodified-graphs}

Из-за особенностей конструкции Xcode и XcodeProj ведение графа зависимостей
может быть утомительной и чреватой ошибками задачей. Вот несколько примеров
проблем, с которыми вы можете столкнуться:

- Поскольку система сборки Xcode выводит все продукты проекта в один и тот же
  каталог в производных данных, цели могут импортировать продукты, которые не
  должны импортировать. Компиляция может быть неудачной на CI, где чистые сборки
  более распространены, или позже, когда используется другая конфигурация.
- Переходные динамические зависимости цели должны быть скопированы в любой из
  каталогов, входящих в настройку сборки `LD_RUNPATH_SEARCH_PATHS`. В противном
  случае цель не сможет найти их во время выполнения. Это легко продумать и
  настроить, когда граф небольшой, но это становится проблемой, когда граф
  растет.
- Когда цель связывает статический
  [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle),
  ей требуется дополнительная фаза сборки, чтобы Xcode обработал пакет и извлек
  нужный бинарник для текущей платформы и архитектуры. Эта фаза сборки не
  добавляется автоматически, и ее легко забыть добавить.

Выше приведены лишь несколько примеров, но есть и множество других, с которыми
мы сталкивались на протяжении многих лет. Представьте себе, что вам требуется
команда инженеров для поддержки графа зависимостей и обеспечения его
достоверности. Или еще хуже, если бы все эти тонкости решались во время сборки
закрытой системой сборки, которую вы не можете контролировать или настраивать.
Звучит знакомо? Именно такой подход Apple применила в Xcode и XcodeProj и
унаследовала от менеджера пакетов Swift.

Мы твердо убеждены, что граф зависимостей должен быть **явным** и
**статическим**, потому что только в этом случае он может быть **проверен** и
**оптимизирован**. С Tuist вы сосредотачиваетесь на описании того, что от чего
зависит, а мы заботимся обо всем остальном. Все тонкости и детали реализации
абстрагируются от вас.

В следующих разделах вы узнаете, как объявить зависимости в своем проекте.

::: наконечник ВАЛИДАЦИЯ ГРАФА
<!-- -->
Tuist проверяет граф при генерации проекта, чтобы убедиться, что в нем нет
циклов и что все зависимости действительны. Благодаря этому любая команда может
принимать участие в развитии графа зависимостей, не опасаясь его нарушить.
<!-- -->
:::

## Локальные зависимости {#local-dependencies}

Цели могут зависеть от других целей в том же и других проектах, а также от
двоичных файлов. При инстанцировании цели `` вы можете передать аргумент
`dependencies` с любой из следующих опций:

- `Цель`: Объявляет зависимость с целью в рамках одного проекта.
- `Проект`: Объявляет зависимость с целью в другом проекте.
- `Framework`: Объявляет зависимость с бинарным фреймворком.
- `Библиотека`: Объявляет зависимость с бинарной библиотекой.
- `XCFramework`: Объявляет зависимость с бинарным XCFramework.
- `SDK`: Объявляет зависимость с системным SDK.
- `XCTest`: Объявляет зависимость с XCTest.

::: инфо ДЕПЕНДИЦИОННЫЕ УСЛОВИЯ
<!-- -->
Каждый тип зависимости принимает опцию `condition`, чтобы условно связать
зависимость в зависимости от платформы. По умолчанию зависимость связывается для
всех платформ, поддерживаемых целевой программой.
<!-- -->
:::

## Внешние зависимости {#external-dependencies}

Tuist также позволяет объявлять внешние зависимости в проекте.

### Пакеты Swift {#swift-packages}

Пакеты Swift - это рекомендуемый нами способ объявления зависимостей в вашем
проекте. Вы можете интегрировать их с помощью стандартного механизма интеграции
Xcode или с помощью интеграции на основе XcodeProj от Tuist.

#### Интеграция Туиста на основе XcodeProj {#tuists-xcodeprojbased-integration}

Интеграция по умолчанию в Xcode, хотя и является наиболее удобной, не обладает
гибкостью и контролем, необходимыми для средних и крупных проектов. Чтобы решить
эту проблему, Tuist предлагает интеграцию на основе XcodeProj, которая позволяет
интегрировать Swift-пакеты в ваш проект с помощью целей XcodeProj. Благодаря
этому мы можем не только предоставить вам больше контроля над интеграцией, но и
сделать ее совместимой с такими рабочими процессами, как
<LocalizedLink href="/guides/features/cache">кэширование</LocalizedLink> и
<LocalizedLink href="/guides/features/test/selective-testing">выборочный прогон тестов</LocalizedLink>.

Интеграция в XcodeProj, скорее всего, потребует больше времени для поддержки
новых функций Swift Package или дескриптора большего количества конфигураций
пакетов. Однако логика сопоставления между пакетами Swift и целями XcodeProj
имеет открытый исходный код и может быть дополнена сообществом. Это отличается
от интеграции по умолчанию в Xcode, которая является закрытой и поддерживается
Apple.

Чтобы добавить внешние зависимости, необходимо создать файл `Package.swift` либо
в разделе `Tuist/`, либо в корне проекта.

::: code-group
```swift [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription
    import ProjectDescriptionHelpers

    let packageSettings = PackageSettings(
        productTypes: [
            "Alamofire": .framework, // default is .staticFramework
        ]
    )

#endif

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
    ],
    targets: [
        .binaryTarget(
            name: "Sentry",
            url: "https://github.com/getsentry/sentry-cocoa/releases/download/8.40.1/Sentry.xcframework.zip",
            checksum: "db928e6fdc30de1aa97200576d86d467880df710cf5eeb76af23997968d7b2c7"
        ),
    ]
)
```
<!-- -->
:::

::: tip НАСТРОЙКИ ПАКЕТА
<!-- -->
Экземпляр `PackageSettings`, обернутый в директиву компилятора, позволяет
настроить интеграцию пакетов. Например, в приведенном выше примере он
используется для переопределения типа продукта, используемого по умолчанию для
пакетов. По умолчанию он не нужен.
<!-- -->
:::

> [Если ваш проект использует пользовательские конфигурации сборки
> (конфигурации, отличные от стандартных `Debug` и `Release`), вы должны указать
> их в `PackageSettings` с помощью `baseSettings`. Внешние зависимости должны
> знать о конфигурациях вашего проекта для корректной сборки. Например:
> 
> ```swift
> #if TUIST
>     import ProjectDescription
> 
>     let packageSettings = PackageSettings(
>         productTypes: [:],
>         baseSettings: .settings(configurations: [
>             .debug(name: "Base"),
>             .release(name: "Production")
>         ])
>     )
> #endif
> ```
> 
> Более подробную информацию см. в
> [#8345](https://github.com/tuist/tuist/issues/8345).

Файл `Package.swift` - это просто интерфейс для объявления внешних зависимостей,
и ничего больше. Именно поэтому в пакете не определяются цели или продукты.
После определения зависимостей вы можете выполнить следующую команду для
разрешения и извлечения зависимостей в каталог `Tuist/Dependencies`:

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

Как вы могли заметить, мы используем подход, похожий на
[CocoaPods](https://cocoapods.org)', где разрешение зависимостей - это отдельная
команда. Это дает пользователям контроль над тем, когда они хотят, чтобы
зависимости были разрешены и обновлены, и позволяет открыть проект в Xcode и
получить его готовым к компиляции. Это та область, где, по нашему мнению, опыт
разработчиков, предоставляемый интеграцией Apple с менеджером пакетов Swift, со
временем ухудшается по мере роста проекта.

Затем вы можете ссылаться на эти зависимости из целей проекта, используя тип
зависимости `TargetDependency.external`:

::: code-group
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone],
            product: .app,
            bundleId: "dev.tuist.app",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"],
            dependencies: [
                .external(name: "Alamofire"), // [!code ++]
            ]
        ),
    ]
)
```
<!-- -->
:::

::: info NO SCHEMES GENERATED FOR EXTERNAL PACKAGES
<!-- -->
**Схемы** не создаются автоматически для проектов Swift Package, чтобы сохранить
аккуратность списка схем. Вы можете создать их через пользовательский интерфейс
Xcode.
<!-- -->
:::

#### Интеграция Xcode по умолчанию {#xcodes-default-integration}

Если вы хотите использовать механизм интеграции Xcode по умолчанию, вы можете
передать список `пакетов` при создании проекта:

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

А затем ссылайтесь на них в своих целях:

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

Для макросов Swift и плагинов Build Tool необходимо использовать типы `.macro` и
`.plugin` соответственно.

::: Предупреждение Плагины SPM Build Tool
<!-- -->
Плагины инструментов сборки SPM должны быть объявлены с помощью механизма
[Xcode's default integration](#xcode-s-default-integration), даже если вы
используете Tuist's [XcodeProj-based
integration](#tuist-s-xcodeproj-based-integration) для ваших зависимостей
проекта.
<!-- -->
:::

Практическое применение плагина инструмента сборки SPM - это выполнение линтинга
кода на этапе сборки Xcode "Run Build Tool Plug-ins". В манифесте пакета это
определяется следующим образом:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Framework",
    products: [
        .library(name: "Framework", targets: ["Framework"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            plugins: [
                .plugin(name: "SwiftLint", package: "SwiftLintPlugin"),
            ]
        ),
    ]
)
```

Чтобы сгенерировать проект Xcode с плагином инструмента сборки, необходимо
объявить пакет в массиве `packages` манифеста проекта, а затем включить пакет с
типом `.plugin` в зависимости цели.

```swift
import ProjectDescription

let project = Project(
    name: "Framework",
    packages: [
        .remote(url: "https://github.com/SimplyDanny/SwiftLintPlugins", requirement: .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            dependencies: [
                .package(product: "SwiftLintBuildToolPlugin", type: .plugin),
            ]
        ),
    ]
)
```

### Карфаген {#carthage}

Поскольку [Carthage](https://github.com/carthage/carthage) выводит `frameworks`
или `xcframeworks`, вы можете запустить `carthage update`, чтобы вывести
зависимости в каталоге `Carthage/Build`, а затем использовать тип зависимости
`.framework` или `.xcframework` target, чтобы объявить зависимость в вашей цели.
Вы можете обернуть это в сценарий, который можно запустить перед генерацией
проекта.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

::: предупреждение BUILD AND TEST
<!-- -->
Если вы собираете и тестируете проект с помощью `xcodebuild build` и `tuist
test`, вам также необходимо убедиться, что зависимости, разрешённые Carthage,
присутствуют. Для этого перед сборкой или тестированием выполните команду
`carthage update`.
<!-- -->
:::

### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) ожидает наличия проекта Xcode для интеграции
зависимостей. Вы можете использовать Tuist для генерации проекта, а затем
выполнить `pod install` для интеграции зависимостей, создав рабочее
пространство, содержащее ваш проект и зависимости Pods. Это можно обернуть в
сценарий, который можно запустить перед генерацией проекта.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

::: warning
<!-- -->
Зависимости CocoaPods несовместимы с такими рабочими процессами, как `build` или
`test`, которые запускают `xcodebuild` сразу после генерации проекта. Они также
несовместимы с бинарным кэшированием и выборочным тестированием, поскольку
логика отпечатков пальцев не учитывает зависимости Pods.
<!-- -->
:::

## Статический или динамический {#static-or-dynamic}

Фреймворки и библиотеки могут быть связаны как статически, так и динамически,
**- выбор, который оказывает существенное влияние на такие аспекты, как размер
приложения и время загрузки**. Несмотря на свою важность, это решение часто
принимается без особого внимания.

**Общее правило** заключается в том, что в релизных сборках стоит по возможности
использовать статическую линковку для достижения быстрого времени запуска, а в
отладочных сборках – динамическую линковку, чтобы обеспечить быстрые итерации.

Проблема с переключением между статической и динамической линковкой в графе
проекта в Xcode нетривиальна, поскольку изменение имеет каскадный эффект на весь
граф (например, библиотеки не могут содержать ресурсы, статические фреймворки не
должны быть встроены). Apple пыталась решить проблему с помощью решений на этапе
компиляции, таких как автоматическое решение менеджера пакетов Swift между
статической и динамической линковкой или [Mergeable
Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries).
Однако это добавляет новые динамические переменные в граф компиляции, добавляя
новые источники недетерминизма и потенциально вызывая ненадежность некоторых
функций, таких как Swift Previews, которые полагаются на граф компиляции.

К счастью, Tuist концептуально сжимает сложность, связанную с переключением
между статическим и динамическим типом, и синтезирует
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">объединенные аксессоры</LocalizedLink>, которые являются стандартными для всех типов
связывания. В сочетании с
<LocalizedLink href="/guides/features/projects/dynamic-configuration">динамическими конфигурациями через переменные окружения</LocalizedLink>, вы можете передавать
тип связывания во время вызова и использовать это значение в ваших манифестах
для установки типа продукта ваших целей.

```swift
// Use the value returned by this function to set the product type of your targets.
func productType() -> Product {
    if case let .string(linking) = Environment.linking {
        return linking == "static" ? .staticFramework : .framework
    } else {
        return .framework
    }
}
```

Обратите внимание, что Tuist
<LocalizedLink href="/guides/features/projects/cost-of-convenience"> по умолчанию не использует удобство через неявную конфигурацию из-за своих затрат</LocalizedLink>. Это означает, что мы полагаемся на то, что вы зададите
тип линковки и любые дополнительные настройки сборки, которые иногда требуются,
например [`-ObjC` флаг
линкера](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184),
чтобы гарантировать правильность получаемых двоичных файлов. Поэтому наша
позиция заключается в предоставлении вам ресурсов, обычно в виде документации,
для принятия правильных решений.

::: совет ПРИМЕР: КОМПОЗИЦИОННАЯ АРХИТЕКТУРА
<!-- -->
Пакет Swift, который интегрируют многие проекты, - это [The Composable
Architecture](https://github.com/pointfreeco/swift-composable-architecture).
Более подробную информацию вы найдете в [этом
разделе](#the-composable-architecture).
<!-- -->
:::

### Сценарии {#scenarios}

Существуют сценарии, в которых установка статической или динамической линковки
нецелесообразна или нежелательна. Ниже приведен неполный список сценариев, в
которых может потребоваться сочетание статической и динамической привязки:

- **Приложения с расширениями:** Поскольку приложениям и их расширениям
  приходится совместно использовать код, вам может понадобиться сделать эти цели
  динамическими. В противном случае один и тот же код будет дублироваться и в
  приложении, и в расширении, что приведет к увеличению размера двоичного файла.
- **Предварительно скомпилированные внешние зависимости:** Иногда вам
  предоставляются предварительно скомпилированные двоичные файлы, которые могут
  быть статическими или динамическими. Статические двоичные файлы могут быть
  обернуты в динамические фреймворки или библиотеки для динамической компоновки.

При внесении изменений в граф Tuist проанализирует его и выдаст предупреждение,
если обнаружит "статический побочный эффект". Это предупреждение призвано помочь
вам выявить проблемы, которые могут возникнуть при статическом связывании цели,
которая транзитивно зависит от статической цели через динамические цели. Эти
побочные эффекты часто проявляются в виде увеличения размера бинарных файлов
или, в худшем случае, сбоев во время выполнения.

## Устранение неполадок {#troubleshooting}

### Зависимости Objective-C {#objectivec-dependencies}

При интеграции зависимостей Objective-C может потребоваться включение
определенных флагов в потребляющую цель, чтобы избежать сбоев во время
выполнения, как описано в [Apple Technical Q&A
QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html).

Поскольку система сборки и Tuist не имеют возможности определить, нужен ли этот
флаг, и поскольку он имеет потенциально нежелательные побочные эффекты, Tuist не
будет автоматически применять любой из этих флагов, и поскольку менеджер пакетов
Swift считает, что `-ObjC` должен быть включен через `.unsafeFlag`, большинство
пакетов не могут включить его как часть своих настроек связывания по умолчанию,
когда это необходимо.

Потребители зависимостей Objective-C (или внутренних целей Objective-C) должны
применять флаги `-ObjC` или `-force_load`, когда это необходимо, установив
`OTHER_LDFLAGS` на потребляющих целях.

### Firebase и другие библиотеки Google {#firebase-other-google-libraries}

Библиотеки Google с открытым исходным кодом, несмотря на их мощный потенциал,
могут быть трудно интегрированы в Tuist, поскольку они часто используют
нестандартную архитектуру и методы построения.

Вот несколько советов, которые могут понадобиться для интеграции Firebase и
других библиотек Google для платформы Apple:

#### Убедитесь, что `-ObjC` добавлен к `OTHER_LDFLAGS` {#ensure-objc-is-added-to-other_ldflags}

Многие библиотеки Google написаны на языке Objective-C. В связи с этим любая
потребляющая цель должна включать тег `-ObjC` в свои настройки сборки
`OTHER_LDFLAGS`. Его можно задать в файле `.xcconfig` или вручную указать в
настройках цели в манифестах Tuist. Пример:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

Более подробную информацию см. в разделе [Зависимости
Objective-C](#objective-c-dependencies) выше.

#### Установите тип продукта для `FBLPromises` на dynamic framework {#set-the-product-type-for-fblpromises-to-dynamic-framework}

Некоторые библиотеки Google зависят от `FBLPromises`, другой библиотеки Google.
Вы можете столкнуться с ошибкой, в которой упоминается `FBLPromises`, выглядящей
примерно так:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

Явное задание типа продукта `FBLPromises` на `.framework` в файле
`Package.swift` должно устранить проблему:

```swift [Tuist/Package.swift]
// swift-tools-version: 5.10

import PackageDescription

#if TUIST
import ProjectDescription
import ProjectDescriptionHelpers

let packageSettings = PackageSettings(
    productTypes: [
        "FBLPromises": .framework,
    ]
)
#endif

let package = Package(
...
```

### Композитная архитектура {#the-composable-architecture}

Как описано
[здесь](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)
и в разделе [Устранение неполадок](#troubleshooting), вам нужно установить
параметр сборки `OTHER_LDFLAGS` в значение `$(inherited) -ObjC` при статическом
связывании пакетов, что является типом связывания Tuist по умолчанию. В качестве
альтернативы вы можете переопределить тип продукта, чтобы пакет был
динамическим. При статическом связывании тестовые и прикладные цели обычно
работают без проблем, но предварительные просмотры SwiftUI не работают. Эту
проблему можно решить, связав все динамически. В приведенном ниже примере
[Sharing](https://github.com/pointfreeco/swift-sharing) также добавлен в
качестве зависимости, поскольку он часто используется вместе с The Composable
Architecture и имеет свои собственные [подводные камни
конфигурации](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032).

Следующая конфигурация свяжет все динамически - таким образом, приложение +
тестовые цели и предварительные просмотры SwiftUI будут работать.

::: наконечник СТАТИЧЕСКИЙ ИЛИ ДИНАМИЧЕСКИЙ
<!-- -->
Динамическое связывание не всегда рекомендуется. Подробнее см. в разделе
[Статическая или динамическая](#static-or-dynamic). В этом примере для простоты
все зависимости связаны динамически без условий.
<!-- -->
:::

```swift [Tuist/Package.swift]
// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import enum ProjectDescription.Environment
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    productTypes: [
        "CasePaths": .framework,
        "CasePathsCore": .framework,
        "Clocks": .framework,
        "CombineSchedulers": .framework,
        "ComposableArchitecture": .framework,
        "ConcurrencyExtras": .framework,
        "CustomDump": .framework,
        "Dependencies": .framework,
        "DependenciesTestSupport": .framework,
        "IdentifiedCollections": .framework,
        "InternalCollectionsUtilities": .framework,
        "IssueReporting": .framework,
        "IssueReportingPackageSupport": .framework,
        "IssueReportingTestSupport": .framework,
        "OrderedCollections": .framework,
        "Perception": .framework,
        "PerceptionCore": .framework,
        "Sharing": .framework,
        "SnapshotTesting": .framework,
        "SwiftNavigation": .framework,
        "SwiftUINavigation": .framework,
        "UIKitNavigation": .framework,
        "XCTestDynamicOverlay": .framework
    ],
    targetSettings: [
        "ComposableArchitecture": .settings(base: [
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ]),
        "Sharing": .settings(base: [
            "PRODUCT_NAME": "SwiftSharing",
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ])
    ]
)
#endif
```

::: warning
<!-- -->
Вместо `import Sharing` вам придется `import SwiftSharing`.
<!-- -->
:::

### Переходные статические зависимости просачиваются через `.swiftmodule` {#transitive-static-dependencies-leaking-through-swiftmodule}

Когда динамический фреймворк или библиотека зависят от статических через `import
StaticSwiftModule`, символы включаются в `.swiftmodule` динамического фреймворка
или библиотеки, что потенциально
<LocalizedLink href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1"> может привести к сбою компиляции</LocalizedLink>. Чтобы избежать этого,
необходимо импортировать статическую зависимость с помощью
<LocalizedLink href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</LocalizedLink>:

```swift
internal import StaticModule
```

::: info
<!-- -->
Уровень доступа к импорту был включен в Swift 6. Если вы используете более
старые версии Swift, то вместо этого вам нужно использовать
<LocalizedLink href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</LocalizedLink>:
<!-- -->
:::

```swift
@_implementationOnly import StaticModule
```
