---
{
  "title": "Code sharing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to share code across manifest files to reduce duplications and ensure consistency"
}
---
# Совместное использование кодов {#code-sharing}

Одно из неудобств Xcode при работе с большими проектами заключается в том, что
он не позволяет повторно использовать элементы проектов, кроме настроек сборки,
через файлы `.xcconfig`. Возможность повторного использования определений
проектов полезна по следующим причинам:

- Это облегчает обслуживание **** , поскольку изменения могут быть применены в
  одном месте, и все проекты получают их автоматически.
- Это позволяет определить соглашения **** , которым могут соответствовать новые
  проекты.
- Проекты более **последовательны**, поэтому вероятность сбоев из-за
  несогласованности значительно меньше.
- Добавление новых проектов становится простой задачей, поскольку мы можем
  повторно использовать существующую логику.

Повторное использование кода в файлах манифеста возможно в Tuist благодаря
концепции помощников описания проекта **** .

::: tip A TUIST UNIQUE ASSET
<!-- -->
Многие организации любят Tuist, потому что видят в помощниках описания проектов
платформу для команд, которые могут кодифицировать свои собственные соглашения и
придумать свой собственный язык для описания своих проектов. Например,
генераторам проектов на основе YAML приходится придумывать свои собственные
шаблоны на основе YAML или заставлять организации создавать на их основе свои
инструменты.
<!-- -->
:::

## Помощники в описании проекта {#project-description-helpers}

Помощники описания проекта - это файлы Swift, которые компилируются в модуль
`ProjectDescriptionHelpers`, который могут импортировать файлы манифеста. Модуль
компилируется путем сбора всех файлов в каталоге
`Tuist/ProjectDescriptionHelpers`.

Вы можете импортировать их в свой файл манифеста, добавив оператор импорта в
верхней части файла:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` доступен в следующих манифестах:
- `Project.swift`
- `Package.swift` (только за флагом компилятора `#TUIST` )
- `Workspace.swift`

## Пример {#example}

Приведенные ниже фрагменты содержат пример того, как мы расширяем модель
`Project` для добавления статических конструкторов и как мы используем их из
файла `Project.swift`:

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
Обратите внимание, как с помощью этой функции мы определяем соглашения об имени
целей, идентификаторе пакета и структуре папок.
<!-- -->
:::
