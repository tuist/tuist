---
{
  "title": "Миграция проекта Xcode",
  "titleTemplate": ":title · Миграция · Внедрение · Проекты · Возможности · Руководства · Tuist",
  "description": "Узнайте, как перенести проект Xcode в проект Tuist."
}
---
# Миграция проекта Xcode {#migrate-an-xcode-project}

Если вы не <.localized_link href="/guides/features/projects/adoption/new-project">создаёте новый проект с помощью Tuist</.localized_link>, в котором случае всё настраивается автоматически, вам придётся описать ваши проекты Xcode, используя примитивы Tuist. Трудоёмкость этого процесса зависит от сложности ваших проектов.

Как вы, вероятно, знаете, со временем проекты Xcode могут стать запутанными и сложными: группы, не соответствующие структуре каталогов, файлы, общие для нескольких таргетов, или ссылки на несуществующие файлы (и это лишь некоторые примеры). Вся эта накопленная сложность затрудняет создание команды, которая могла бы надёжно выполнять миграцию проекта.

Кроме того, ручная миграция — отличный способ привести проекты в порядок и упростить их. За это будут благодарны не только разработчики вашего проекта, но и Xcode, который станет быстрее обрабатывать и индексировать их. После полного перехода на Tuist он обеспечит единообразное определение проектов и сохранит их простоту.

Чтобы облегчить эту работу, мы даём вам рекомендации, основанные на обратной связи от пользователей.

## Создание каркаса проекта {#create-project-scaffold}

Прежде всего создайте каркас для вашего проекта с помощью следующих файлов Tuist:

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

`Project.swift` — это манифест-файл, в котором вы определяете свой проект, а `Package.swift` — манифест-файл, в котором вы определяете зависимости. В файле `Tuist.swift` можно задать настройки Tuist, относящиеся к проекту.

> [!TIP]
> **Имя проекта с суффиксом -Tuist**
>
> Чтобы избежать конфликтов с существующим проектом Xcode, мы рекомендуем добавить суффикс `-Tuist` к имени проекта. Вы можете убрать его после полной миграции проекта на Tuist.


## Сборка и тестирование проекта Tuist в CI {#build-and-test-the-tuist-project-in-ci}

Чтобы убедиться в корректности миграции каждого изменения, мы рекомендуем расширить ваш конвейер непрерывной интеграции так, чтобы он собирал и тестировал проект, сгенерированный Tuist из вашего манифест-файла:

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## Вынесение настроек сборки проекта в файлы `.xcconfig` {#extract-the-project-build-settings-into-xcconfig-files}

Вынесите настройки сборки из проекта в файл `.xcconfig`, чтобы сделать проект легче и упростить миграцию. Для этого можно использовать следующую команду, которая извлекает настройки сборки из проекта в файл `.xcconfig`:


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

Затем обновите файл `Project.swift`, указав путь к только что созданному файлу `.xcconfig`:

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

Затем расширьте конвейер непрерывной интеграции, добавив выполнение следующей команды, чтобы гарантировать, что изменения настроек сборки вносятся непосредственно в файлы `.xcconfig`:

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## Вынесение зависимостей пакетов {#extract-package-dependencies}

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

> [!TIP]
> **Типы продуктов**
>
> Вы можете переопределить тип продукта для конкретного пакета, добавив его в словарь `productTypes` в структуре `PackageSettings`. По умолчанию Tuist считает все пакеты статическими фреймворками.


## Определение порядка миграции {#determine-the-migration-order}

Мы рекомендуем мигрировать таргеты, начиная с тех, от которых зависят больше всего, и заканчивая наименее зависимыми. Чтобы получить список таргетов проекта, отсортированный по количеству зависимостей, используйте следующую команду:

```bash
tuist migration list-targets -p Project.xcodeproj
```

Начните миграцию таргетов с верхней части списка, поскольку именно от них зависят остальные.


## Миграция таргетов {#migrate-targets}

Мигрируйте таргеты по одному. Мы рекомендуем создавать отдельный pull request для каждого таргета, чтобы изменения были проверены и протестированы до слияния.

### Вынесение настроек сборки таргета в файлы `.xcconfig` {#extract-the-target-build-settings-into-xcconfig-files}

Как и в случае с настройками сборки проекта, вынесите настройки сборки таргета в файл `.xcconfig`, чтобы сделать таргет легче и упростить миграцию. Для этого можно использовать следующую команду, которая извлекает настройки сборки из таргета в файл `.xcconfig`:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### Определение таргета в файле `Project.swift` {#define-the-target-in-the-projectswift-file}

Определите таргет в `Project.targets`:

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

> [!NOTE]
> **Тестовые таргеты**
>
> Если у таргета есть связанный тестовый таргет, его также следует определить в файле `Project.swift`, повторив те же шаги.


### Проверка миграции таргета {#validate-the-target-migration}

Выполните `tuist generate`, затем `xcodebuild build`, чтобы убедиться, что проект собирается, и `tuist test`, чтобы убедиться, что тесты проходят. Кроме того, вы можете использовать [xcdiff](https://github.com/bloomberg/xcdiff) для сравнения сгенерированного проекта Xcode с существующим, чтобы убедиться в корректности изменений.

### Повторение {#repeat}

Повторяйте процесс, пока все таргеты не будут полностью мигрированы. После завершения мы рекомендуем обновить конвейеры CI и CD, чтобы сборка и тестирование проекта выполнялись с помощью `tuist generate`, за которым следуют `xcodebuild build` и `tuist test`.

## Устранение неполадок {#troubleshooting}

### Ошибки компиляции из-за отсутствующих файлов. {#compilation-errors-due-to-missing-files}

Если файлы, связанные с таргетами вашего проекта Xcode, не находились целиком в каталоге файловой системы, представляющем таргет, вы можете получить проект, который не компилируется. Убедитесь, что список файлов после генерации проекта с помощью Tuist совпадает со списком файлов в проекте Xcode, и воспользуйтесь возможностью привести структуру файлов в соответствие со структурой таргетов.
