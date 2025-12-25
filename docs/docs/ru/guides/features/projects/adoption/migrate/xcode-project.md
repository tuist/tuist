---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# Миграция Xcode-проекта {#migrate-an-xcode-project}

Если вы не
<LocalizedLink href="/guides/features/projects/adoption/new-project">создаёте новый проект с помощью Tuist</LocalizedLink>, где всё настраивается
автоматически, вам придётся описать свои Xcode-проекты, используя примитивы
Tuist. Насколько утомительным будет этот процесс, зависит от сложности ваших
проектов.

Как вы, вероятно, знаете, со временем Xcode-проекты могут становиться
запутанными и сложными: группы не соответствуют структуре каталогов, одни и те
же файлы используются в разных targets, а ссылки на файлы указывают на
несуществующие объекты (и это лишь некоторые примеры). Вся эта накопившаяся
сложность не позволяет реализовать команду, которая могла бы надёжно выполнить
миграцию проекта.

Более того, ручная миграция – это отличный способ провести очистку и упростить
ваши проекты. Этому будут рады не только разработчики, работающие над проектом,
но и сам Xcode, который будет быстрее обрабатывать и индексировать их. После
полного перехода на Tuist он гарантирует, что проекты будут определены
единообразно и останутся простыми.

С целью упростить этот процесс мы подготовили несколько рекомендаций, основанных
на отзывах пользователей.

## Создание структуры проекта {#create-project-scaffold}

Прежде всего создайте структуру (scaffold) для вашего проекта, добавив следующие
файлы Tuist:

::: code-group

```js [Tuist.swift]
import ProjectDescription

let tuist = Tuist()
```

```js [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyApp-Tuist",
    targets: [
        /** Targets will go here **/
    ]
)
```

```js [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
    ]
)
```
<!-- -->
:::

`Project.swift` – это файл манифеста, в котором вы будете описывать свой проект,
а `Package.swift` – файл манифеста, в котором определяются зависимости. Файл
`Tuist.swift` используется для задания настроек Tuist, относящихся к вашему
проекту.

::: tip ИМЯ ПРОЕКТА С СУФФИКСОМ -TUIST
<!-- -->
Чтобы избежать конфликтов с существующим Xcode-проектом, мы рекомендуем добавить
суффикс `-Tuist` к имени проекта. После полной миграции проекта на Tuist этот
суффикс можно удалить.
<!-- -->
:::

## Сборка и тестирование проекта Tuist в CI {#build-and-test-the-tuist-project-in-ci}

Чтобы убедиться, что каждое изменение, внесённое в процессе миграции, корректно,
мы рекомендуем расширить процесс непрерывной интеграции (CI), добавив сборку и
тестирование проекта, сгенерированного Tuist из манифеста:

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## Вынос настроек сборки проекта в файлы `.xcconfig` {#extract-the-project-build-settings-into-xcconfig-files}

Вынесите настройки сборки из проекта в файл `.xcconfig`, чтобы сделать проект
легче и упростить его миграцию. Вы можете использовать следующую команду, чтобы
извлечь настройки сборки из проекта в файл `.xcconfig`:


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

Затем обновите файл `Project.swift`, указав в нём путь к только что созданному
файлу `.xcconfig`:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
        .release(name: "Release", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
    ]),
    targets: [
        /** Targets will go here **/
    ]
)
```

Затем расширьте пайплайн непрерывной интеграции, добавив выполнение следующей
команды, чтобы убедиться, что изменения настроек сборки вносятся непосредственно
в файлы `.xcconfig`:

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## Вынос зависимостей пакетов {#extract-package-dependencies}

Вынесите все зависимости вашего проекта в файл `Tuist/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
        .package(url: "https://github.com/onevcat/Kingfisher", .upToNextMajor(from: "7.12.0")) // [!code ++]
    ]
)
```

::: tip ТИПЫ ПРОДУКТОВ
<!-- -->
Вы можете переопределить тип продукта для конкретного пакета, добавив его в
словарь `productTypes` внутри структуры `PackageSettings`. По умолчанию Tuist
предполагает, что все пакеты являются статическими фреймворками.
<!-- -->
:::


## Определение порядка миграции {#determine-the-migration-order}

Мы рекомендуем выполнять миграцию targets, начиная с тех, от которых зависят
другие, и заканчивая теми, которые зависят меньше всего. Вы можете использовать
следующую команду, чтобы вывести список targets проекта, отсортированный по
количеству зависимостей:

```bash
tuist migration list-targets -p Project.xcodeproj
```

Начните миграцию targets с верхней части списка, так как именно от них зависит
наибольшее количество других targets.


## Миграция targets {#migrate-targets}

Мигрируйте targets по одной. Мы рекомендуем создавать отдельный pull request для
каждого target, чтобы убедиться, что изменения были проверены и протестированы
перед их слиянием.

### Вынос настроек сборки targets в файлы `.xcconfig` {#extract-the-target-build-settings-into-xcconfig-files}

Так же, как и с настройками сборки проекта, вынесите настройки сборки target в
файл `.xcconfig`, чтобы сделать target проще и облегчить её миграцию. Вы можете
использовать следующую команду, чтобы извлечь настройки сборки target в файл
`.xcconfig`:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### Определение target в файле `Project.swift` {#define-the-target-in-the-projectswift-file}

Определите target в `Project.targets`:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/Project.xcconfig"),
        .release(name: "Release", xcconfig: "./xcconfigs/Project.xcconfig"),
    ]),
    targets: [
        .target( // [!code ++]
            name: "TargetX", // [!code ++]
            destinations: .iOS, // [!code ++]
            product: .framework, // [!code ++] // or .staticFramework, .staticLibrary...
            bundleId: "dev.tuist.targetX", // [!code ++]
            sources: ["Sources/TargetX/**"], // [!code ++]
            dependencies: [ // [!code ++]
                /** Dependencies go here **/ // [!code ++]
                /** .external(name: "Kingfisher") **/ // [!code ++]
                /** .target(name: "OtherProjectTarget") **/ // [!code ++]
            ], // [!code ++]
            settings: .settings(configurations: [ // [!code ++]
                .debug(name: "Debug", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
                .debug(name: "Release", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
            ]) // [!code ++]
        ), // [!code ++]
    ]
)
```

::: info ТЕСТОВЫЕ TARGETS
<!-- -->
Если у target есть связанная тестовая target, её также следует определить в
файле `Project.swift`, повторив те же шаги.
<!-- -->
:::

### Проверка миграции target {#validate-the-target-migration}

Запустите `tuist generate`, затем `xcodebuild build`, чтобы убедиться, что
проект собран, и `tuist test`, чтобы убедиться, что тесты пройдены. Кроме того,
вы можете использовать [xcdiff](https://github.com/bloomberg/xcdiff) для
сравнения сгенерированного проекта Xcode с существующим проектом, чтобы
убедиться в правильности изменений.

### Повторение {#repeat}

Повторяйте, пока все цели не будут полностью перенесены. После этого мы
рекомендуем обновить конвейеры CI и CD для сборки и тестирования проекта с
помощью `tuist generate`, затем `xcodebuild build` и `tuist test`.

## Устранение неполадок {#troubleshooting}

### Ошибки компиляции из-за отсутствующих файлов. {#compilation-errors-due-to-missing-files}

Если файлы, связанные с targets вашего Xcode-проекта, не находятся в отдельной
директории файловой системы, соответствующей каждой target, проект может не
скомпилироваться. Убедитесь, что список файлов после генерации проекта с помощью
Tuist совпадает со списком файлов в Xcode-проекте, и воспользуйтесь этой
возможностью, чтобы привести структуру файлов в соответствие со структурой
targets.
