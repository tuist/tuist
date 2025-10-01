---
{
  "title": "Migrate a Bazel project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from Bazel to Tuist."
}
---
# Перенесите проект Bazel {#migrate-a-bazel-project}

[Bazel](https://bazel.build) - это система сборки, которую Google выложила в
открытый доступ в 2015 году. Это мощный инструмент, позволяющий быстро и надежно
создавать и тестировать программное обеспечение любого размера. Некоторые
крупные организации, такие как
[Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/),
[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae)
или [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel), используют его,
однако он требует предварительных (то есть изучения технологии) и постоянных
инвестиций (то есть слежения за обновлениями Xcode) для внедрения и поддержки.
Хотя это и подходит некоторым организациям, которые относятся к этому как к
сквозной задаче, это может быть не лучшим вариантом для других, которые хотят
сосредоточиться на разработке своих продуктов. Например, мы видели организации,
в которых команда разработчиков платформы iOS внедрила Bazel и была вынуждена
отказаться от него после того, как инженеры, возглавлявшие эту работу, покинули
компанию. Позиция Apple относительно тесной связи между Xcode и системой сборки
- еще один фактор, который затрудняет поддержку проектов Bazel в течение долгого
времени.

> [!СОВЕТ] УНИКАЛЬНОСТЬ TUIST ЛЕЖИТ В ЕГО ОСОБЕННОСТЯХ Вместо того чтобы
> бороться с Xcode и проектами Xcode, Tuist принимает их. Это те же концепции
> (например, цели, схемы, настройки сборки), знакомый язык (например, Swift),
> простой и приятный опыт, который делает поддержку и масштабирование проектов
> делом каждого, а не только команды платформы iOS.

## Правила {#rules}

Bazel использует правила для определения того, как создавать и тестировать
программное обеспечение. Правила написаны на
[Starlark](https://github.com/bazelbuild/starlark), языке, похожем на Python.
Tuist использует Swift в качестве языка конфигурации, что обеспечивает
разработчикам удобство использования функций автодополнения, проверки типов и
валидации Xcode. Например, следующее правило описывает, как создать
Swift-библиотеку в Bazel:

::: кодовая группа
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
:::

Вот еще один пример, но уже сравнительный: как определять модульные тесты в
Bazel и Tuist:

:::код-группа
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
:::


## Зависимости менеджера пакетов Swift {#swift-package-manager-dependencies}

В Bazel вы можете использовать
[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager)
[Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md)
плагин для использования Swift-пакетов в качестве зависимостей. Плагин требует
`Package.swift` в качестве источника истины для зависимостей. В этом смысле
интерфейс Tuist похож на интерфейс Bazel. Вы можете использовать команду `tuist
install` для разрешения и извлечения зависимостей пакета. После завершения
разрешения вы можете сгенерировать проект с помощью команды `tuist generate`.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## Генерация проекта {#project-generation}

Сообщество предоставляет набор правил,
[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj),
для генерации проектов Xcode на основе проектов, объявленных Bazel. В отличие от
Bazel, где вам нужно добавить некоторую конфигурацию в файл `BUILD`, Tuist не
требует никакой конфигурации вообще. Вы можете запустить `tuist generate` в
корневом каталоге вашего проекта, и Tuist сгенерирует для вас Xcode-проект.
