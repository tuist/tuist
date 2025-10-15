---
{
  "title": "Create a new project",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to create a new project with Tuist."
}
---
# Создание нового проекта {#create-a-new-project}

Самый простой способ начать работу с Tuist — использовать команду `tuist init`.
Эта команда запускает интерактивный интерфейс командной строки (CLI), который
проведёт вас через процесс настройки проекта. Когда появится соответствующий
запрос, обязательно выберите опцию создания «сгенерированного проекта».

Вы можете [редактировать
проект]<LocalizedLink href="/guides/features/projects/editing">, запустив `tuist
edit`, и Xcode откроет проект, в котором можно вносить изменения. Одним из
созданных файлов будет `Project.swift`, который содержит описание вашего
проекта.Если вы знакомы с Swift Package Manager, подумайте о нём как о
`Package.swift`, но с терминологией, принятой для проектов Xcode.

::: code-group
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.MyApp",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["MyApp/Sources/**"],
            resources: ["MyApp/Resources/**"],
            dependencies: []
        ),
        .target(
            name: "MyAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.MyAppTests",
            infoPlist: .default,
            sources: ["MyApp/Tests/**"],
            resources: [],
            dependencies: [.target(name: "MyApp")]
        ),
    ]
)
```
<!-- -->
:::

::: info
<!-- -->
Мы намеренно поддерживаем короткий список доступных шаблонов, чтобы
минимизировать затраты на их сопровождение. Если вы хотите создать проект,
который не является приложением, например фреймворк, вы можете использовать
`tuist init` в качестве отправной точки, а затем изменить сгенерированный проект
под свои нужды.
<!-- -->
:::

## Создание проекта вручную {#manually-creating-a-project}

Alternatively, you can create the project manually. We recommend doing this only
if you're already familiar with Tuist and its concepts. The first thing that
you'll need to do is to create additional directories for the project structure:

```bash
mkdir MyFramework
cd MyFramework
```

Then create a `Tuist.swift` file, which will configure Tuist and is used by
Tuist to determine the root directory of the project, and a `Project.swift`,
where your project will be declared:

::: code-group
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyFramework",
    targets: [
        .target(
            name: "MyFramework",
            destinations: .macOS,
            product: .framework,
            bundleId: "dev.tuist.MyFramework",
            sources: ["MyFramework/Sources/**"],
            dependencies: []
        )
    ]
)
```
```swift [Tuist.swift]
import ProjectDescription

let tuist = Tuist()
```
<!-- -->
:::

::: warning
<!-- -->
Tuist uses the `Tuist/` directory to determine the root of your project, and
from there it looks for other manifest files globbing the directories. We
recommend creating those files with your editor of choice, and from that point
on, you can use `tuist edit` to edit the project with Xcode.
<!-- -->
:::
