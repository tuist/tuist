---
{
  "title": "Migrate a Bazel project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from Bazel to Tuist."
}
---
# Миграция проекта Bazel {#migrate-a-bazel-project}

[Bazel](https://bazel.build) – это система сборки, которую Google сделала с
открытым исходным кодом в 2015 году. Это мощный инструмент, позволяющий быстро и
надёжно собирать и тестировать программное обеспечение любого масштаба.
Некоторые крупные компании, такие как
[Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/),
[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae)
и [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel), используют его,
однако для внедрения и сопровождения требуются как первоначальные затраты
(например, изучение технологии), так и постоянные инвестиции (например,
отслеживание обновлений Xcode). Такой подход подходит организациям, которые
рассматривают систему сборки как сквозной аспект разработки, но может быть не
лучшим выбором для тех, кто хочет сосредоточиться на развитии продукта.
Например, нам встречались компании, где команда iOS-платформы внедрила Bazel, но
впоследствии отказалась от него после ухода инженеров, руководивших этим
процессом. Позиция Apple относительно тесной связи между Xcode и системой сборки
– ещё один фактор, который со временем усложняет поддержку проектов на Bazel.

::: tip УНИКАЛЬНОСТЬ TUIST ЗАКЛЮЧАЕТСЯ В ЕГО УТОНЧЕННОСТИ
<!-- -->
Вместо того чтобы бороться с Xcode и Xcode-проектами, Tuist принимает их.
Используя те же концепции (например, target, схемы, настройки сборки), знакомый
язык (Swift) и обеспечивая простой и приятный процесс работы, Tuist делает
поддержку и масштабирование проектов общей задачей команды, а не только команды
iOS-платформы.
<!-- -->
:::

## Правила {#rules}

Bazel использует правила для определения того, как собирать и тестировать
программное обеспечение. Эти правила пишутся на
[Starlark](https://github.com/bazelbuild/starlark) – языке, похожем на Python.
Tuist использует Swift в качестве языка конфигурации, который предоставляет
разработчикам удобство работы с функциями автодополнения, проверки типов и
валидации в Xcode. Например, следующее правило описывает, как собрать библиотеку
Swift в Bazel:

::: code-group
```txt [BUILD (Bazel)]
swift_library(
    name = "MyLibrary.library",
    srcs = glob(["**/*.swift"]),
    module_name = "MyLibrary"
)
```

```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(name: "MyLibrary", product: .staticLibrary, sources: ["**/*.swift"])
    ]
)
```
<!-- -->
:::

Вот ещё один пример, сравнивающий то, как определяются модульные тесты в Bazel и
Tuist:

::: code-group
```txt [BUILD (Bazel)]
ios_unit_test(
    name = "MyLibraryTests",
    bundle_id = "dev.tuist.MyLibraryTests",
    minimum_os_version = "16.0",
    test_host = "//MyApp:MyLibrary",
    deps = [":MyLibraryTests.library"],
)

```
```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(
            name: "MyLibraryTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.MyLibraryTests",
            sources: "Tests/MyLibraryTests/**",
            dependencies: [
                .target(name: "MyLibrary"),
            ]
        )
    ]
)
```
<!-- -->
:::


## Зависимости Swift Package Manager {#swift-package-manager-dependencies}

В Bazel вы можете использовать плагин
[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager)
[Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md) для
подключения Swift-пакетов в качестве зависимостей. Плагину требуется файл
`Package.swift` в качестве основного источника данных о зависимостях. Интерфейс
Tuist в этом смысле схож с Bazel: вы можете использовать команду `tuist install`
для разрешения и загрузки зависимостей пакета. После завершения этого процесса
можно сгенерировать проект с помощью команды `tuist generate`.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## Генерация проекта {#project-generation}

Сообщество предоставляет набор правил
[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj) для
генерации Xcode-проектов на основе проектов, определённых в Bazel. В отличие от
Bazel, где необходимо добавить конфигурацию в файл `BUILD`, Tuist не требует
никакой дополнительной настройки. Вы можете запустить команду `tuist generate`в
корневом каталоге проекта – Tuist сгенерирует Xcode-проект автоматически.
