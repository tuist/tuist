---
{
  "title": "Общий код",
  "titleTemplate": ":title · Проекты · Возможности · Руководства · Tuist",
  "description": "Узнайте, как делиться кодом между файлами манифестов, чтобы уменьшить дублирование и обеспечить согласованность"
}
---
# Общий код {#code-sharing}

Одним из неудобств Xcode при работе с крупными проектами является то, что он не позволяет повторно использовать элементы проектов, кроме настроек сборки через файлы `.xcconfig`. Возможность переиспользовать определения проектов полезна по следующим причинам:

- Это упрощает **поддержку**, потому что изменения можно применить в одном месте, и все проекты автоматически их получат.
- Это позволяет определить **соглашения**, которым могут следовать новые проекты.
- Проекты становятся более **согласованными**, поэтому вероятность сбоев сборки из-за несоответствий значительно снижается.
- Добавление новых проектов становится простой задачей, поскольку мы можем переиспользовать существующую логику.

Повторное использование кода между файлами манифестов в Tuist возможно благодаря концепции **помощников описания проекта**.

> [!TIP]
> **Уникальное преимущество Tuist**
>
> Многие организации выбирают Tuist, потому что видят в помощниках описания проекта платформу для платформенных команд, позволяющую кодифицировать собственные соглашения и создать свой язык описания проектов. Например, генераторы проектов на основе YAML вынуждены разрабатывать собственные проприетарные решения шаблонизации на YAML или заставлять организации строить свои инструменты поверх них.


## Помощники описания проекта {#project-description-helpers}

Помощники описания проекта — это файлы Swift, которые компилируются в модуль `ProjectDescriptionHelpers`, доступный для импорта в файлах манифестов. Модуль компилируется путем сбора всех файлов из директории `Tuist/ProjectDescriptionHelpers`.

Вы можете импортировать их в файл манифеста, добавив оператор импорта в начало файла:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` доступны в следующих манифестах:
- `Project.swift`
- `Package.swift` (только при использовании флага компилятора `#TUIST`)
- `Workspace.swift`

## Пример {#example}

Ниже приведены фрагменты кода, демонстрирующие, как мы расширяем модель `Project`, добавляя статические конструкторы, и как используем их из файла `Project.swift`:

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
> **Инструмент для внедрения соглашений**
>
> Обратите внимание, как с помощью функции мы определяем соглашения об именах таргетов, идентификаторах bundle и структуре папок.
