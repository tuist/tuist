---
{
  "title": "Code sharing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to share code across manifest files to reduce duplications and ensure consistency"
}
---
# Совместное использование кода {#code-sharing}

Одним из неудобств Xcode при работе с крупными проектами является то, что он не
позволяет повторно использовать элементы проектов, кроме настроек сборки, через
файлы `.xcconfig`. Возможность повторного использования определений проектов
полезна по следующим причинам:

- Это упрощает обслуживание **** , поскольку изменения можно применять в одном
  месте, и все проекты автоматически получают эти изменения.
- Это позволяет определить соглашения **** , которым могут соответствовать новые
  проекты.
- Проекты более **consistent** и поэтому вероятность сбоев сборки из-за
  несоответствий значительно меньше.
- Добавление новых проектов становится простой задачей, поскольку мы можем
  повторно использовать существующую логику.

Повторное использование кода в манифест-файлах возможно в Tuist благодаря
концепции помощников описания проекта **** .

::: tip A TUIST UNIQUE ASSET
<!-- -->
Многие организации любят Tuist, потому что видят в описании проекта платформу,
на которой команды могут кодифицировать свои собственные соглашения и придумать
свой собственный язык для описания своих проектов. Например, генераторы проектов
на основе YAML должны придумать свое собственное проприетарное решение для
шаблонов на основе YAML или заставить организации создавать свои инструменты на
его основе.
<!-- -->
:::

## Помощники по описанию проекта {#project-description-helpers}

Помощники описания проекта — это файлы Swift, которые компилируются в модуль
`ProjectDescriptionHelpers`, который могут импортировать файлы манифеста. Модуль
компилируется путем сбора всех файлов в каталоге
`Tuist/ProjectDescriptionHelpers`.

Вы можете импортировать их в файл манифеста, добавив оператор import в верхней
части файла:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` доступны в следующих манифестах:
- `Project.swift`
- `Package.swift` (только за флагом компилятора `#TUIST` )
- `Workspace.swift`

## Пример {#example}

В приведенных ниже фрагментах показано, как мы расширяем модель` проекта `,
чтобы добавить статические конструкторы, и как мы используем их из файла
`Project.swift`:

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

::: tip A TOOL TO ESTABLISH CONVENTIONS
<!-- -->
Обратите внимание, как с помощью функции мы определяем соглашения об именах
целей, идентификаторе пакета и структуре папок.
<!-- -->
:::
