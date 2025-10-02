---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# Перенос проекта Xcode {#migrate-an-xcode-project}

Если вы не <LocalizedLink href="/guides/start/new-project">создаете новый проект
с помощью Tuist</LocalizedLink>, в этом случае все настраивается автоматически,
вам придется определять свои проекты Xcode, используя примитивы Tuist. Насколько
утомительным будет этот процесс, зависит от того, насколько сложными будут ваши
проекты.

Как вы, вероятно, знаете, проекты Xcode со временем могут стать беспорядочными и
сложными: группы, которые не соответствуют структуре каталогов, файлы, которые
совместно используются для разных целей, или ссылки на файлы, которые указывают
на несуществующие файлы (и это только некоторые из них). Все эти накопленные
сложности мешают нам предоставить команду, которая надежно мигрирует проект.

Более того, ручная миграция - это отличное упражнение для очистки и упрощения
ваших проектов. За это будут благодарны не только разработчики в вашем проекте,
но и Xcode, который будет быстрее обрабатывать и индексировать их. Когда вы
полностью перейдете на Tuist, он позаботится о том, чтобы проекты были
последовательно определены и оставались простыми.

Чтобы облегчить эту работу, мы даем вам несколько рекомендаций, основанных на
отзывах пользователей.

## Создайте эшафот проекта {#create-project-scaffold}

Прежде всего, создайте строительные леса для своего проекта с помощью следующих
файлов Tuist:

::: кодовая группа

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
:::

`Project.swift` - это файл манифеста, в котором вы определяете свой проект, а
`Package.swift` - это файл манифеста, в котором вы определяете свои зависимости.
Файл `Tuist.swift` - это файл, в котором вы можете определить настройки Tuist
для вашего проекта.

> [!СОВЕТ] ИМЯ ПРОЕКТА С СУФФИКСОМ -TUIST Чтобы избежать конфликтов с
> существующим проектом Xcode, мы рекомендуем добавить к имени проекта суффикс
> `-Tuist`. Вы можете отказаться от него, когда полностью переведете проект на
> Tuist.

## Сборка и тестирование проекта Tuist в CI {#build-and-test-the-tuist-project-in-ci}

Чтобы убедиться, что перенос каждого изменения будет корректным, мы рекомендуем
расширить вашу непрерывную интеграцию для сборки и тестирования проекта,
созданного Tuist на основе вашего файла манифеста:

```bash
tuist install
tuist generate
tuist build -- ...{xcodebuild flags} # or tuist test
```

## Извлеките настройки сборки проекта в файлы `.xcconfig` {#extract-the-project-build-settings-into-xcconfig-files}

Извлеките настройки сборки из проекта в файл `.xcconfig`, чтобы сделать проект
более компактным и удобным для миграции. Вы можете использовать следующую
команду для извлечения настроек сборки из проекта в файл `.xcconfig`:


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

Затем обновите файл `Project.swift`, чтобы он указывал на файл `.xcconfig`,
который вы только что создали:

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

Затем расширьте конвейер непрерывной интеграции и выполните следующую команду,
чтобы изменения настроек сборки вносились непосредственно в файлы `.xcconfig`:

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## Извлечение зависимостей пакетов {#extract-package-dependencies}

Извлеките все зависимости вашего проекта в файл `Tuist/Package.swift`:

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

> [!TIP] ТИПЫ ПРОДУКТОВ Вы можете переопределить тип продукта для конкретного
> пакета, добавив его в словарь `productTypes` в структуре `PackageSettings`. По
> умолчанию Tuist предполагает, что все пакеты являются статическими
> фреймворками.


## Определите порядок миграции {#determine-the-migration-order}

Мы рекомендуем переносить цели от наиболее зависимых к наименее зависимым. Вы
можете использовать следующую команду, чтобы перечислить цели проекта,
отсортированные по количеству зависимостей:

```bash
tuist migration list-targets -p Project.xcodeproj
```

Начните переносить цели из верхней части списка, поскольку именно они являются
наиболее зависимыми.


## Перенос целей {#migrate-targets}

Переносите цели по одной. Мы рекомендуем делать запрос на притяжение для каждой
цели, чтобы обеспечить проверку и тестирование изменений перед их слиянием.

### Извлеките настройки целевой сборки в файлы `.xcconfig` {#extract-the-target-build-settings-into-xcconfig-files}

Как и в случае с настройками сборки проекта, извлеките настройки целевой сборки
в файл `.xcconfig`, чтобы сделать целевую сборку более компактной и облегчить ее
перенос. Вы можете использовать следующую команду для извлечения настроек сборки
из целевого файла в файл `.xcconfig`:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### Определите цель в файле `Project.swift` {#define-the-target-in-the-projectswift-file}

Определите цель в разделе `Project.targets`:

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

> [!ПРИМЕЧАНИЕ] ТЕСТОВЫЕ ЦЕЛИ Если у цели есть связанная с ней тестовая цель, ее
> также следует определить в файле `Project.swift`, повторив те же шаги.

### Проверка целевой миграции {#validate-the-target-migration}

Запустите `tuist build` и `tuist test`, чтобы убедиться, что проект собран и
тесты пройдены. Кроме того, вы можете использовать
[xcdiff](https://github.com/bloomberg/xcdiff) для сравнения сгенерированного
проекта Xcode с существующим проектом, чтобы убедиться в правильности изменений.

### Повторите {#repeat}

Повторяйте, пока все цели не будут полностью перенесены. После этого мы
рекомендуем обновить конвейеры CI и CD для сборки и тестирования проекта с
помощью команд `tuist build` и `tuist test`, чтобы воспользоваться
преимуществами скорости и надежности, которые обеспечивает Tuist.

## Устранение неполадок {#troubleshooting}

### Ошибки компиляции из-за отсутствия файлов. {#compilation-errors-due-to-missing-files}

Если файлы, связанные с целями проекта Xcode, не все содержатся в каталоге
файловой системы, представляющем цель, вы можете получить проект, который не
компилируется. Убедитесь, что список файлов после генерации проекта с помощью
Tuist совпадает со списком файлов в проекте Xcode, и воспользуйтесь возможностью
привести структуру файлов в соответствие со структурой цели.
