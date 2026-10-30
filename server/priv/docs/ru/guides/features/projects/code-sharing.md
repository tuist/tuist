---
{
  "title": "Совместное использование кода",
  "titleTemplate": ":title · Проекты · Возможности · Руководства · Tuist",
  "description": "Узнайте, как делиться кодом между файлами манифестов, чтобы уменьшить дублирование и обеспечить согласованность"
}
---
# Общий код {#code-sharing}

Одним из неудобств Xcode при работе с крупными проектами является то, что он не позволяет повторно использовать элементы проектов, кроме настроек сборки, через файлы `.xcconfig`. Возможность повторного использования определений проекта полезна по следующим причинам:

- Это упрощает **поддержку**, поскольку изменения можно применять в одном месте, и все проекты автоматически получают эти изменения.
- Это позволяет определять **соглашения**, которым могут следовать новые проекты.
- Проекты становятся более **единообразными**, поэтому вероятность ошибок сборки из-за несогласованности значительно снижается.
- Добавление нового проекта становится простой задачей, поскольку мы можем повторно использовать существующую логику.

Повторное использование кода между файлами манифестов в Tuist возможно благодаря концепции **хелперов описания проекта**.

> [!TIP]
> **Уникальное преимущество Tuist**
>
> Многие организации выбирают Tuist, потому что видят в хелперах описания проекта платформу для платформенных команд, позволяющую кодифицировать собственные соглашения и создать свой язык для описания проектов. Например, генераторы проектов на основе YAML вынуждены разрабатывать собственные проприетарные решения шаблонизации на YAML или заставлять организации строить свои инструменты поверх них.


## Хелперы описания проекта {#project-description-helpers}

Хелперы описания проекта — это Swift-файлы, которые компилируются в модуль `ProjectDescriptionHelpers`, доступный для импорта в файлах манифестов. Модуль компилируется из всех файлов в директории `Tuist/ProjectDescriptionHelpers`.

Вы можете импортировать их в файл манифеста, добавив оператор импорта в начало файла:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` доступны в следующих манифестах:
- `Project.swift`
- `Package.swift` (только при наличии флага компилятора `#TUIST`)
- `Workspace.swift`

## Пример {#example}

Приведённые ниже фрагменты показывают, как мы расширяем модель `Project`, добавляя статические конструкторы, и как используем их из файла `Project.swift`:

::: code-group
```swift [Tuist/Project+Templates.swift]
import ProjectDescription

extension Project {
  public static func featureFramework(name: String, dependencies: [TargetDependency] = []) -> Project {
    return Project(
        name: name,
        targets: [
            .target(
                name: name,
                destinations: .iOS,
                product: .framework,
                bundleId: "dev.tuist.\(name)",
                infoPlist: "\(name).plist",
                sources: ["Sources/\(name)/**"],
                resources: ["Resources/\(name)/**",],
                dependencies: dependencies
            ),
            .target(
                name: "\(name)Tests",
                destinations: .iOS,
                product: .unitTests,
                bundleId: "dev.tuist.\(name)Tests",
                infoPlist: "\(name)Tests.plist",
                sources: ["Sources/\(name)Tests/**"],
                resources: ["Resources/\(name)Tests/**",],
                dependencies: [.target(name: name)]
            )
        ]
    )
  }
}
```

```swift {2} [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.featureFramework(name: "MyFeature")
```
<!-- -->
:::

> [!TIP]
> **Инструмент для установления соглашений**
>
> Обратите внимание, как с помощью функции мы определяем соглашения об именах таргетов, идентификаторах бандла и структуре папок.
