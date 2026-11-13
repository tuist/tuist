---
{
  "title": "Зависимости",
  "titleTemplate": ":title · Проекты · Возможности · Руководства · Tuist",
  "description": "Узнайте, как объявлять зависимости в проекте Tuist."
}
---
# Зависимости {#dependencies}

По мере роста проекта его часто разделяют на несколько таргетов, чтобы совместно использовать код, определять границы и ускорять сборки. Наличие нескольких таргетов означает определение зависимостей между ними, формирующих **граф зависимостей**, который также может включать внешние зависимости.

## Графы, закодированные в XcodeProj {#xcodeprojcodified-graphs}

Из-за особенностей архитектуры Xcode и XcodeProj поддержка графа зависимостей может быть трудоёмкой и подверженной ошибкам задачей. Вот несколько примеров проблем, с которыми вы можете столкнуться:

- Поскольку система сборки Xcode помещает все продукты проекта в одну директорию в Derived Data, таргеты могут импортировать продукты, которые им не должны быть доступны. Сборки могут завершаться ошибкой в CI, где чаще используются чистые сборки, или позже при использовании другой конфигурации.
- Транзитивные динамические зависимости таргета необходимо копировать в любую из директорий, указанных в настройке сборки `LD_RUNPATH_SEARCH_PATHS`. Если этого не сделать, таргет не сможет найти их во время выполнения. Это легко продумать и настроить при небольшом графе, но становится проблемой по мере его роста.
- Когда таргет линкует статический [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle), ему требуется дополнительный этап сборки, чтобы Xcode обработал бандл и извлёк правильный бинарный файл для текущей платформы и архитектуры. Этот этап сборки не добавляется автоматически, и его легко забыть добавить.

Выше приведены лишь несколько примеров, но за годы мы столкнулись со многими другими. Представьте, что вам нужна команда инженеров для поддержки графа зависимостей и обеспечения его корректности. Или, что ещё хуже, что все сложности разрешаются во время сборки закрытой системой сборки, которую вы не можете контролировать или настраивать. Звучит знакомо? Именно такой подход Apple использовала в Xcode и XcodeProj, который унаследовал Swift Package Manager.

Мы убеждены, что граф зависимостей должен быть **явным** и **статичным**, потому что только тогда его можно **валидировать** и **оптимизировать**. С Tuist вы сосредотачиваетесь на описании того, что от чего зависит, а мы берём на себя остальное. Сложности и детали реализации скрыты от вас.

В следующих разделах вы узнаете, как объявлять зависимости в вашем проекте.

> [!TIP]
> **Валидация графа**
>
> Tuist проверяет граф при генерации проекта, чтобы убедиться в отсутствии циклов и корректности всех зависимостей. Благодаря этому любая команда может участвовать в развитии графа зависимостей, не опасаясь его нарушить.


## Локальные зависимости {#local-dependencies}

Таргеты могут зависеть от других таргетов в том же или других проектах, а также от бинарных файлов. При создании экземпляра `Target` вы можете передать аргумент `dependencies` с одним из следующих вариантов:

- `Target`: Объявляет зависимость от таргета в том же проекте.
- `Project`: Объявляет зависимость от таргета в другом проекте.
- `Framework`: Объявляет зависимость от бинарного фреймворка.
- `Library`: Объявляет зависимость от бинарной библиотеки.
- `XCFramework`: Объявляет зависимость от бинарного XCFramework.
- `SDK`: Объявляет зависимость от системного SDK.
- `XCTest`: Объявляет зависимость от XCTest.
- `Macro`: Объявляет зависимость от таргета Swift Macro, определённого в том же проекте (см. [Swift Macros](#swift-macros)).

> [!NOTE]
> **Условия зависимостей**
>
> Каждый тип зависимости принимает опцию `condition` для условного линкования зависимости в зависимости от платформы. По умолчанию зависимость линкуется для всех платформ, которые поддерживает таргет.


## Внешние зависимости {#external-dependencies}

Tuist также позволяет объявлять внешние зависимости в вашем проекте.

### Swift Packages {#swift-packages}

Swift Packages — это наш рекомендуемый способ объявления зависимостей в проекте. Вы можете интегрировать их, используя механизм интеграции по умолчанию в Xcode или интеграцию Tuist на основе XcodeProj.

#### Интеграция Tuist на основе XcodeProj {#tuists-xcodeprojbased-integration}

Интеграция по умолчанию в Xcode, хотя и является наиболее удобной, не обеспечивает гибкости и контроля, необходимых для средних и крупных проектов. Чтобы решить эту проблему, Tuist предлагает интеграцию на основе XcodeProj, которая позволяет интегрировать Swift Packages в ваш проект, используя таргеты XcodeProj. Благодаря этому мы не только даём вам больше контроля над интеграцией, но и обеспечиваем совместимость с такими рабочими процессами, как <.localized_link href="/guides/features/cache">кэширование</.localized_link> и <.localized_link href="/guides/features/selective-testing">селективные прогоны тестов</.localized_link>.

Интеграция через XcodeProj, скорее всего, потребует больше времени для поддержки новых возможностей Swift Package или обработки дополнительных конфигураций пакетов. Однако логика сопоставления между Swift Packages и таргетами XcodeProj имеет открытый исходный код, и сообщество может вносить в неё свой вклад. Это отличается от интеграции по умолчанию в Xcode, которая имеет закрытый исходный код и поддерживается Apple.

Чтобы добавить внешние зависимости, вам нужно создать файл `Package.swift` либо в директории `Tuist/`, либо в корне проекта.

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

> [!TIP]
> **Настройки пакета**
>
> Экземпляр `PackageSettings`, обернутый в директиву компилятора, позволяет настроить способ интеграции пакетов. Например, в приведённом выше примере он используется для переопределения типа продукта по умолчанию для пакетов. По умолчанию он вам не понадобится. Вы также можете использовать его для настройки ожидаемых подписей для бинарных таргетов SwiftPM через `expectedSignatures`.


### Подписи бинарных таргетов

Если локальный или удалённый Swift-пакет предоставляет бинарный таргет XCFramework, вы можете настроить его ожидаемую подпись, используя `PackageSettings.expectedSignatures`:

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        expectedSignatures: [
            "SelfSignedXCFramework": .selfSigned(
                fingerprint: "EF61C3C0339FC84805357AFEC2E0BB0E6A0D5EE64165B333F934BF9E282785BC"
            ),
        ]
    )
#endif
```

> [!IMPORTANT] CUSTOM BUILD CONFIGURATIONS
> Если ваш проект использует пользовательские конфигурации сборки (конфигурации, отличные от стандартных `Debug` и `Release`), вы должны указать их в `PackageSettings`, используя `baseSettings`. Внешним зависимостям необходимо знать о конфигурациях вашего проекта для корректной сборки. Например:
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
> Подробнее см. [#8345](https://github.com/tuist/tuist/issues/8345).

Файл `Package.swift` служит только интерфейсом для объявления внешних зависимостей и ничем более. Поэтому вы не определяете в пакете никакие таргеты или продукты. После определения зависимостей вы можете выполнить следующую команду, чтобы разрешить и загрузить зависимости в директорию `Tuist/Dependencies`:

```bash
tuist install
# Resolving and fetching dependencies.
# Installing Swift Package Manager dependencies.
```

Как вы, возможно, заметили, мы используем подход, аналогичный [CocoaPods](https://cocoapods.org), где разрешение зависимостей выполняется отдельной командой. Это дает пользователям контроль над тем, когда разрешать и обновлять зависимости, а также позволяет открыть проект в Xcode в состоянии, готовом к компиляции. Мы считаем, что в этом аспекте опыт разработчика, предоставляемый интеграцией Apple со Swift Package Manager, со временем ухудшается по мере роста проекта.

Затем из таргетов вашего проекта вы можете ссылаться на эти зависимости, используя тип зависимости `TargetDependency.external`:

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
                .external(name: "Alamofire"),
            ]
        ),
    ]
)
```
<!-- -->
:::

> [!NOTE]
> **Схемы не генерируются для внешних пакетов**
>
> **Схемы** не создаются автоматически для проектов Swift Package, чтобы список схем оставался чистым. Вы можете создать их через интерфейс Xcode.


#### Интеграция Xcode по умолчанию {#xcodes-default-integration}

Если вы хотите использовать механизм интеграции Xcode по умолчанию, вы можете передать список `packages` при создании экземпляра проекта:

```swift
let project = Project(name: "MyProject", packages: [
    .package(url: "https://github.com/krzyzanowskim/CryptoSwift", .exact("1.8.0"))
])
```

А затем сослаться на них из ваших таргетов:

```swift
let target: Target = .target(name: "MyTarget", destinations: .iOS, product: .framework, bundleId: "dev.tuist.MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

При интеграции Swift Macro или Build Tool Plugin из внешнего Swift-пакета через интеграцию Xcode по умолчанию объявляйте их с типами `.macro` и `.plugin` соответственно. Макросы также можно использовать через [интеграцию Tuist на основе XcodeProj](#tuists-xcodeprojbased-integration), а если вы хотите определить собственный Swift-макрос вместо использования макроса из пакета, см. раздел [Swift Macros](#swift-macros).

> [!WARNING]
> **Плагины инструментов сборки SPM**
>
> Плагины инструментов сборки SPM должны быть объявлены с использованием механизма [интеграции Xcode по умолчанию](#xcodes-default-integration), даже если вы используете [интеграцию Tuist на основе XcodeProj](#tuists-xcodeprojbased-integration) для зависимостей вашего проекта.

Плагины инструментов сборки SPM — это программы на Swift, которые Xcode и SwiftPM выполняют для обнаружения конкретных команд сборки, которые должны выполняться для таргета. Эти команды могут зависеть от графа пакетов, файлов таргета, рабочего каталога плагина, разрешенных инструментов плагина и выходных данных, объявленных плагином. Некоторые плагины также генерируют файлы, которые должны стать частью сборки того же таргета.

Интеграция Tuist на основе XcodeProj сопоставляет продукты пакетов с нативными таргетами Xcode, когда сопоставление является статическим, например для библиотек, бинарных файлов, исполняемых файлов и макросов. Плагины инструментов сборки не имеют эквивалентного примитива в нативном проекте Xcode вне интеграции SwiftPM в Xcode. Хотя плагин в конечном итоге может запускать исполняемый файл, вызов этого исполняемого файла из обычного этапа сборки скрипта не эквивалентен запуску плагина: Tuist сначала должен оценить Swift-код плагина, воспроизвести контекст плагина SwiftPM, обнаружить команды, смоделировать объявленные входные и выходные данные и добавить любые сгенерированные файлы в граф таргета перед тем, как Xcode запланирует сборку.

По этой причине объявление пакета с плагином только в `Tuist/Package.swift` и его использование через `.external(name:)` не поддерживается. Поддерживаемая альтернатива — объявить пакет в `Project.packages` и добавить продукт плагина к потребляющему таргету с помощью `.package(product:type: .plugin)`. Это сохраняет привязку плагина к сгенерированному проекту Xcode как зависимости продукта Swift Package, поэтому Xcode и SwiftPM могут запускать его с нативным контекстом плагина.

Компромисс заключается в том, что Xcode владеет этой интеграцией плагина:

- Xcode разрешает и собирает пакет плагина через свою интеграцию SwiftPM.
- Пакет отображается в сгенерированном проекте как ссылка на Swift Package, а не как внешний таргет, сгенерированный Tuist.
- Tuist не может предоставить плагину тот же уровень контроля, валидации, кэширования и поведения выборочного тестирования, который он предоставляет для статически сопоставленных продуктов пакетов.
- Сборки в CI и локальные сборки должны разрешать разрешение пакетов Xcode для этих пакетов плагинов.

Из-за этих последствий мы обычно не рекомендуем использовать плагины инструментов сборки SPM в проектах Tuist. По возможности предпочтите скрипт этапа сборки, объявленный в таргете, или запускайте инструмент из скрипта вне сгенерированного проекта Xcode перед вызовом Tuist или Xcode.

Практическим применением плагина инструмента сборки SPM является выполнение линтинга кода во время этапа сборки Xcode «Run Build Tool Plug-ins». Чтобы сгенерировать проект Xcode с сохранением плагина инструмента сборки, объявите пакет в массиве `packages` манифеста проекта, а затем включите пакет с типом `.plugin` в зависимости таргета.

```swift
import ProjectDescription

let project = Project(
    name: "Framework",
    packages: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.56.1"),
    ],
    targets: [
        .target(
            name: "Framework",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.Framework",
            dependencies: [
                .package(product: "SwiftLintBuildToolPlugin", type: .plugin),
            ]
        ),
    ]
)
```

### Carthage {#carthage}

Поскольку [Carthage](https://github.com/carthage/carthage) выводит `frameworks` или `xcframeworks`, вы можете выполнить `carthage update`, чтобы вывести зависимости в директорию `Carthage/Build`, а затем использовать тип зависимости таргета `.framework` или `.xcframework` для объявления зависимости в вашем таргете. Вы можете обернуть это в скрипт, который можно запустить перед генерацией проекта.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING]
> **Сборка и тестирование**
>
> Если вы собираете и тестируете свой проект через `xcodebuild build` и `tuist test`, вам аналогичным образом нужно убедиться, что зависимости, разрешенные Carthage, присутствуют, выполнив команду `carthage update` перед сборкой или тестированием.


### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) ожидает проект Xcode для интеграции зависимостей. Вы можете использовать Tuist для генерации проекта, а затем выполнить `pod install`, чтобы интегрировать зависимости, создав рабочее пространство, содержащее ваш проект и зависимости Pods. Вы можете обернуть это в скрипт, который можно запустить перед генерацией проекта.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING]
> Зависимости CocoaPods не совместимы с рабочими процессами, такими как `build` или `test`, которые выполняют `xcodebuild` сразу после генерации проекта. Они также не совместимы с бинарным кэшированием и выборочным тестированием, поскольку логика создания отпечатков не учитывает зависимости Pods.


## Swift Macros {#swift-macros}

Существует два различных сценария работы с [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) в проекте Tuist, и стоит четко указать, какой из них вы используете:

- **Использование макроса, определенного во внешнем Swift-пакете.** Оба механизма интеграции поддерживают макросы. При использовании [интеграции Tuist на основе XcodeProj](#tuists-xcodeprojbased-integration) вы объявляете пакет в `Tuist/Package.swift` и зависите от него с помощью `.external(name:)` — Tuist сопоставляет продукт макроса с нативным таргетом. При использовании [интеграции Xcode по умолчанию](#xcodes-default-integration) вы объявляете зависимость с помощью `.package(product:type: .macro)`. В отличие от плагинов инструментов сборки, макросы не ограничены интеграцией Xcode по умолчанию.
- **Определение собственного макроса** как части вашего проекта — например, в общей библиотеке внутри монорепозитория. Вам не нужен для этого `Package.swift`: в Tuist есть первоклассный тип продукта `.macro`, поэтому вы можете объявить таргет макроса напрямую в ваших манифестах.

### Определение собственного макроса {#defining-your-own-macro}

Макрос Swift — это плагин компилятора: исполняемый файл, который компилятор Swift загружает и запускает во время компиляции. Tuist моделирует это нативно с помощью типа продукта `.macro`. Хотя Apple не предоставляет тип таргета Swift Macro в проектах Xcode, Tuist включает его, генерируя таргет инструмента командной строки, подключая его как зависимость к таргетам, использующим макрос, и добавляя флаг `-load-plugin-executable` в их настройки компилятора Swift. Вся эта настройка выполняется автоматически.

Типичный макрос разделен на два таргета: таргет **плагина**, реализующий макрос (`product: .macro`), и таргет **библиотеки**, объявляющий публичный интерфейс макроса (объявления `@attached`/`@freestanding`) и зависящий от плагина через `.macro(name:)`. Поскольку плагин выполняется на машине сборки, его таргет предназначен только для хоста (macOS).

Реализация макроса зависит от [swift-syntax](https://github.com/swiftlang/swift-syntax), которую вы объявляете как обычную внешнюю зависимость в `Tuist/Package.swift`:

```swift [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0"),
    ]
)
```

Затем вы можете определить таргеты плагина и библиотеки макроса напрямую в вашем проекте:

```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyLibrary",
    targets: [
        // The compiler plugin that implements the macro. macOS-only, since it
        // runs on the build machine at compile time.
        .target(
            name: "MyMacrosImplementation",
            destinations: [.mac],
            product: .macro,
            bundleId: "dev.tuist.MyMacrosImplementation",
            sources: ["Sources/MyMacrosImplementation/**"],
            dependencies: [
                .external(name: "SwiftSyntax"),
                .external(name: "SwiftSyntaxMacros"),
                .external(name: "SwiftCompilerPlugin"),
            ]
        ),
        // The library that exposes the macro declarations to consumers and
        // depends on the plugin via `.macro(name:)`.
        .target(
            name: "MyLibrary",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.MyLibrary",
            sources: ["Sources/MyLibrary/**"],
            dependencies: [
                .macro(name: "MyMacrosImplementation"),
            ]
        ),
    ]
)
```

Любой таргет, подключающий `MyLibrary`, теперь может использовать макрос — Tuist распространяет плагин, чтобы компилятор мог его загрузить.


## Статическая или динамическая линковка {#static-or-dynamic}

Фреймворки и библиотеки могут быть связаны либо статически, либо динамически, **что существенно влияет на такие аспекты, как размер приложения и время запуска**. Несмотря на важность этого решения, оно часто принимается без должного рассмотрения.

**Общее правило** заключается в том, что вы хотите, чтобы как можно больше компонентов было связано статически в релизных сборках для быстрого запуска, и как можно больше компонентов было связано динамически в отладочных сборках для быстрой итерации.

Сложность переключения между статической и динамической линковкой в графе проекта заключается в том, что в Xcode это нетривиально, поскольку изменение имеет каскадный эффект на весь граф (например, библиотеки не могут содержать ресурсы, статические фреймворки не нужно встраивать). Apple пыталась решить эту проблему с помощью решений на этапе компиляции, таких как автоматический выбор между статической и динамической линковкой в Swift Package Manager или [Mergeable Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries). Однако это добавляет новые динамические переменные в граф компиляции, создавая новые источники недетерминированности и потенциально делая ненадежными некоторые функции, такие как Swift Previews, которые полагаются на граф компиляции.

К счастью, Tuist концептуально упрощает сложность, связанную с переключением между статической и динамической линковкой, и синтезирует <.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">аксессоры бандлов</.localized_link>, которые являются стандартными для всех типов линковки. В сочетании с <.localized_link href="/guides/features/projects/dynamic-configuration">динамическими конфигурациями через переменные окружения</.localized_link> вы можете передавать тип линковки во время вызова и использовать это значение в ваших манифестах для установки типа продукта ваших таргетов.

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

Обратите внимание, что Tuist <.localized_link href="/guides/features/projects/cost-of-convenience">не использует удобство по умолчанию через неявную конфигурацию из-за связанных с этим затрат</.localized_link>. Это означает, что мы полагаемся на то, что вы сами установите тип линковки и любые дополнительные настройки сборки, которые иногда требуются, например, [флаг линковщика `-ObjC`](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184), чтобы гарантировать корректность результирующих бинарных файлов. Поэтому наша позиция заключается в предоставлении вам ресурсов, обычно в виде документации, для принятия правильных решений.

> [!TIP]
> **Пример: The Composable Architecture**
>
> Swift-пакет, который интегрируют многие проекты, — это [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture). Подробнее см. в [этом разделе](#the-composable-architecture).


### Сценарии {#scenarios}

Существуют сценарии, где установка линковки исключительно на статическую или динамическую невозможна или нецелесообразна. Ниже приведен неполный список сценариев, где вам может потребоваться смешать статическую и динамическую линковку:

- **Приложения с расширениями:** Поскольку приложения и их расширения должны разделять код, вам, возможно, потребуется сделать эти таргеты динамическими. В противном случае один и тот же код будет дублироваться как в приложении, так и в расширении, что приведет к увеличению размера бинарного файла.
- **Предварительно скомпилированные внешние зависимости:** Иногда вам предоставляются предварительно скомпилированные бинарные файлы, которые являются либо статическими, либо динамическими. Статические бинарные файлы можно обернуть в динамические фреймворки или библиотеки для динамической линковки.

При внесении изменений в граф Tuist проанализирует его и выдаст предупреждение, если обнаружит «статический побочный эффект». Это предупреждение предназначено для помощи в выявлении проблем, которые могут возникнуть при статической линковке таргета, который транзитивно зависит от статического таргета через динамические таргеты. Эти побочные эффекты часто проявляются в виде увеличения размера бинарного файла или, в худших случаях, сбоев во время выполнения.

## Устранение неполадок {#troubleshooting}

### Зависимости Objective-C {#objectivec-dependencies}

При интеграции зависимостей Objective-C может потребоваться включение определенных флагов в потребляющий таргет, чтобы избежать сбоев во время выполнения, как подробно описано в [Apple Technical Q&A QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html).

Поскольку система сборки и Tuist не имеют возможности определить, необходим ли флаг, и поскольку флаг может иметь нежелательные побочные эффекты, Tuist не применяет эти флаги автоматически. Кроме того, поскольку Swift Package Manager считает, что `-ObjC` включается через `.unsafeFlag`, большинство пакетов не могут включать его в свои настройки линковки по умолчанию, когда это требуется.

Потребители зависимостей Objective-C (или внутренние таргеты Objective-C) должны применять флаги `-ObjC` или `-force_load`, когда это необходимо, устанавливая `OTHER_LDFLAGS` в потребляющих таргетах.

### Firebase и другие библиотеки Google {#firebase-other-google-libraries}

Библиотеки Google с открытым исходным кодом, хотя и мощные, могут быть сложны для интеграции в Tuist, поскольку они часто используют нестандартную архитектуру и техники сборки.

Вот несколько советов, которые могут потребоваться для интеграции Firebase и других библиотек Google для платформ Apple:

#### Убедитесь, что `-ObjC` добавлен в `OTHER_LDFLAGS` {#ensure-objc-is-added-to-other_ldflags}

Многие библиотеки Google написаны на Objective-C. Из-за этого любому потребляющему таргету необходимо включать тег `-ObjC` в настройку сборки `OTHER_LDFLAGS`. Это можно задать в файле `.xcconfig` или указать вручную в настройках таргета в манифестах Tuist. Пример:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

Подробнее см. раздел [Зависимости Objective-C](#objectivec-dependencies) выше.

#### Установите тип продукта для `FBLPromises` как динамический фреймворк {#set-the-product-type-for-fblpromises-to-dynamic-framework}

Некоторые библиотеки Google зависят от `FBLPromises`, другой библиотеки Google. Вы можете столкнуться со сбоем, упоминающим `FBLPromises`, который выглядит примерно так:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

Явное указание типа продукта `FBLPromises` как `.framework` в вашем файле `Package.swift` должно исправить проблему:

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

### The Composable Architecture {#the-composable-architecture}

Как описано [здесь](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184) и в разделе [устранения неполадок](#troubleshooting), вам нужно установить настройку сборки `OTHER_LDFLAGS` в значение `$(inherited) -ObjC` при статической линковке пакетов, которая является типом линковки по умолчанию в Tuist. В качестве альтернативы вы можете переопределить тип продукта пакета на динамический. При статической линковке таргеты тестов и приложений обычно работают без проблем, но предпросмотры SwiftUI не работают. Это можно решить, используя динамическую линковку для всего. В примере ниже [Sharing](https://github.com/pointfreeco/swift-sharing) также добавлен как зависимость, поскольку он часто используется вместе с The Composable Architecture и имеет свои собственные [особенности конфигурации](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032).

Следующая конфигурация будет линковать всё динамически, поэтому таргеты приложения и тестов, а также предпросмотры SwiftUI будут работать.

> [!TIP]
> **Статическая или динамическая линковка**
>
> Динамическая линковка рекомендуется не всегда. См. раздел [Статическая или динамическая линковка](#static-or-dynamic) для получения дополнительной информации. В этом примере все зависимости линкуются динамически без условий для простоты.


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

> [!WARNING]
> Вместо `import Sharing` вам нужно будет использовать `import SwiftSharing`.


### Транзитивные статические зависимости просачиваются через `.swiftmodule` {#transitive-static-dependencies-leaking-through-swiftmodule}

Когда динамический фреймворк или библиотека зависит от статических через `import StaticSwiftModule`, символы включаются в `.swiftmodule` динамического фреймворка или библиотеки, что потенциально <.localized_link href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">может привести к сбою компиляции</.localized_link>. Чтобы этого избежать, вам нужно импортировать статическую зависимость, используя <.localized_link href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</.localized_link>:

```swift
internal import StaticModule
```

> [!NOTE]
> Уровень доступа при импорте был добавлен в Swift 6. Если вы используете более старые версии Swift, вам нужно использовать <.localized_link href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</.localized_link> вместо этого:


```swift
@_implementationOnly import StaticModule
```
