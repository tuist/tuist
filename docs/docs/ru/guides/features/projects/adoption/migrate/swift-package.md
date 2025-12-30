---
{
  "title": "Migrate a Swift Package",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects."
}
---
# Миграция Swift-пакета {#migrate-a-swift-package}

Swift Package Manager появился как менеджер зависимостей для Swift-кода, который
со временем непреднамеренно стал решать задачи управления проектами и поддержки
других языков программирования, таких как Objective-C. Поскольку инструмент
создавался с другой целью, его использование для управления крупными проектами
может быть затруднено, потому что ему не хватает гибкости, производительности и
возможностей, которые предоставляет Tuist. Это хорошо отражено в статье [Scaling
iOS at
Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2), где
приведена таблица, сравнивающая производительность Swift Package Manager и
нативных Xcode-проектов:

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

Мы часто сталкиваемся с разработчиками и организациями, которые оспаривают
необходимость использования Tuist, полагая, что Swift Package Manager может
выполнять аналогичную роль в управлении проектами. Некоторые решаются на переход
и позже осознают, что их опыт разработки значительно ухудшился. Например,
переиндексация файла после его переименования может занять до 15 секунд. 15
секунд!

**Пока неясно, превратит ли Apple Swift Package Manager в универсальный менеджер
проектов. ** Однако мы не видим никаких признаков того, что это происходит. На
самом деле, мы видим прямо противоположное. Они принимают решения, основанные на
Xcode, например, добиваются удобства с помощью неявных конфигураций, которые
<LocalizedLink href="/guides/features/projects/cost-of-convenience">, как вы, наверное, знаете,</LocalizedLink> являются источником сложностей при
масштабировании. Мы считаем, что Apple следовало бы вернуться к основополагающим
принципам и пересмотреть некоторые решения, которые имели смысл для менеджера
зависимостей, но не для менеджера проектов, например, использование
компилируемого языка в качестве интерфейса для определения проектов.

::: tip SPM КАК ПРОСТО МЕНЕДЖЕР ЗАВИСИМОСТЕЙ
<!-- -->
Tuist рассматривает Swift Package Manager как менеджер зависимостей, и это
отличный менеджер. Мы используем его для разрешения и сборки зависимостей. Мы не
используем его для определения проектов, потому что он не предназначен для
этого.
<!-- -->
:::

## Миграция с Swift Package Manager на Tuist {#migrating-from-swift-package-manager-to-tuist}

Сходство между Swift Package Manager и Tuist упрощает процесс миграции. Основное
различие заключается в том, что вместо `Package.swift` вы будете описывать свои
проекты с помощью DSL Tuist.

Сначала создайте файл `Project.swift` рядом с файлом `Package.swift`. Файл
`Package.swift` будет содержать описание вашего проекта. Ниже приведён пример
файла `Package.swift`, в котором определяется проект с единственной целью:

```swift
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            sources: ["Sources/**/*.swift"]*
        ),
    ]
)
```

Некоторые моменты, на которые следует обратить внимание:

- **ProjectDescription**: Вместо `PackageDescription`, вы будете использовать
  `ProjectDescription`.
- **Project**: вместо экспорта экземпляра `package` вы будете использовать
  экземпляр `project`.
- **Язык Xcode**: Примитивы, используемые для определения проекта, повторяют
  язык Xcode, поэтому вы найдете схемы, цели и этапы сборки, среди прочего.

Затем создайте файл `Tuist.swift` со следующим содержимым:

```swift
import ProjectDescription

let tuist = Tuist()
```

Файл `Tuist.swift` содержит конфигурацию вашего проекта, а путь к нему служит
ссылкой для определения корня проекта. Подробнее о структуре проектов Tuist
можно узнать в документе
<LocalizedLink href="/guides/features/projects/directory-structure">directory structure</LocalizedLink>.

## Редактирование проекта {#editing-the-project}

Вы можете использовать команду
<LocalizedLink href="/guides/features/projects/editing">`tuist edit`</LocalizedLink> для редактирования проекта в Xcode. Эта команда
сгенерирует проект Xcode, который можно открыть и начать с ним работу.

```bash
tuist edit
```

В зависимости от размера проекта вы можете выполнить миграцию целиком или
поэтапно. Мы рекомендуем начать с небольшого проекта, чтобы познакомиться с DSL
и рабочим процессом. Наш совет – всегда начинать с цели, от которой зависят
другие, и постепенно переходить к целям верхнего уровня.
