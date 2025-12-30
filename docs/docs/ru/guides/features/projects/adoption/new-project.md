---
{
  "title": "Create a new project",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to create a new project with Tuist."
}
---
# Создание нового проекта {#create-a-new-project}

Самый простой способ начать работу с Tuist – использовать команду `tuist init`.
Эта команда запускает интерактивный интерфейс командной строки (CLI), который
проведёт вас через процесс настройки проекта. Когда появится соответствующий
запрос, обязательно выберите опцию создания «сгенерированного проекта».

Вы можете <LocalizedLink href="/guides/features/projects/editing">редактировать проект</LocalizedLink>, запустив `tuist edit`, и Xcode откроет проект, в котором
можно вносить изменения. Одним из созданных файлов будет `Project.swift`,
который содержит описание вашего проекта.Если вы знакомы с Swift Package
Manager, подумайте о нём как о `Package.swift`, но с терминологией, принятой для
проектов Xcode.

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

Кроме того, вы можете создать проект вручную. Мы рекомендуем делать это только в
том случае, если вы уже знакомы с Tuist и его концепциями. Первое, что нужно
сделать, – создать дополнительные папки для структуры проекта:

```bash
mkdir MyFramework
cd MyFramework
```

Затем создайте файл `Tuist.swift`, который будет настраивать Tuist и
использоваться для определения корневой папки проекта, а также файл
`Project.swift`, где будет объявлен ваш проект:

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
Tuist использует папку `Tuist/ ` для определения корня вашего проекта, а затем
ищет другие файлы манифеста в папках. Мы рекомендуем создать эти файлы в вашем
редакторе, и потом использовать `tuist edit` для редактирования проекта в Xcode.
<!-- -->
:::
