---
{
  "title": "Миграция проекта с Bazel",
  "titleTemplate": ":title · Миграция · Внедрение · Проекты · Возможности · Руководства · Tuist",
  "description": "Узнайте, как перенести ваши проекты с Bazel на Tuist."
}
---
# Миграция проекта с Bazel {#migrate-a-bazel-project}

[Bazel](https://bazel.build) — это система сборки, которую Google открыл в 2015 году. Это мощный инструмент, позволяющий быстро и надежно собирать и тестировать программное обеспечение любого масштаба. Его используют крупные компании, такие как [Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/), [Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae) и [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel). Однако внедрение и поддержка требуют первоначальных (изучение технологии) и постоянных инвестиций (сопровождение обновлений Xcode). Хотя такой подход работает для организаций, рассматривающих его как сквозную задачу, он может не подойти тем, кто хочет сосредоточиться на разработке продукта. Например, мы видели случаи, когда команда iOS-платформы внедряла Bazel, но была вынуждена отказаться от него после ухода инженеров, возглавлявших эту инициативу. Еще одним фактором, усложняющим долгосрочную поддержку проектов на Bazel, является позиция Apple по поводу тесной связи между Xcode и системой сборки.

> [!TIP]
> **Уникальность Tuist — в тонком подходе**
>
> Вместо борьбы с Xcode и проектами Xcode, Tuist использует их преимущества. Те же концепции (например, цели, схемы, настройки сборки), знакомый язык (Swift) и простой, приятный процесс делают поддержку и масштабирование проектов задачей всей команды, а не только платформы iOS.


## Правила {#rules}

Bazel использует правила для определения процессов сборки и тестирования программного обеспечения. Правила пишутся на языке [Starlark](https://github.com/bazelbuild/starlark), похожем на Python. В Tuist в качестве языка конфигурации используется Swift, что дает разработчикам удобство автодополнения, проверки типов и валидации в Xcode. Например, следующее правило описывает сборку библиотеки Swift в Bazel:

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

Вот еще один пример, сравнивающий определение модульных тестов в Bazel и Tuist:

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

В Bazel можно использовать плагин [Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md) из набора [`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager), чтобы подключать зависимости через Swift Packages. Плагину требуется файл `Package.swift` как единственный источник истины для зависимостей. Интерфейс Tuist в этом плане похож на Bazel. Вы можете использовать команду `tuist install`, чтобы разрешить и загрузить зависимости пакета. После завершения разрешения зависимостей сгенерируйте проект командой `tuist generate`.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## Генерация проекта {#project-generation}

Сообщество предоставляет набор правил [rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj) для генерации проектов Xcode на основе проектов, объявленных в Bazel. В отличие от Bazel, где нужно добавлять конфигурацию в файл `BUILD`, Tuist не требует никакой дополнительной настройки. Достаточно выполнить `tuist generate` в корневой директории проекта, и Tuist сгенерирует для вас проект Xcode.
