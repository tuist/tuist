---
{
  "title": "Создание нового проекта",
  "titleTemplate": ":title · Внедрение · Проекты · Возможности · Руководства · Tuist",
  "description": "Узнайте, как создать новый проект с помощью Tuist."
}
---
# Создание нового проекта {#create-a-new-project}

Самый простой способ начать новый проект с Tuist — использовать команду `tuist init`. Эта команда запускает интерактивный CLI, который поможет вам настроить проект. Когда будет предложено, обязательно выберите опцию создания «сгенерированного проекта».

Затем вы можете <.localized_link href="/guides/features/projects/editing">отредактировать проект</.localized_link>, запустив `tuist edit`, и Xcode откроет проект, в котором вы сможете его редактировать. Одним из сгенерированных файлов является `Project.swift`, содержащий определение вашего проекта. Если вы знакомы со Swift Package Manager, воспринимайте его как `Package.swift`, но с терминологией проектов Xcode.

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

> [!NOTE]
> Мы намеренно оставляем список доступных шаблонов коротким, чтобы минимизировать затраты на поддержку. Если вы хотите создать проект, который не является приложением, например фреймворк, вы можете использовать `tuist init` в качестве отправной точки, а затем изменить сгенерированный проект под свои нужды.


## Ручное создание проекта {#manually-creating-a-project}

В качестве альтернативы вы можете создать проект вручную. Мы рекомендуем делать это только в том случае, если вы уже знакомы с Tuist и его концепциями. Первое, что вам нужно сделать, — создать дополнительные каталоги для структуры проекта:

```bash
mkdir MyFramework
cd MyFramework
```

Затем создайте файл `Tuist.swift`, который настроит Tuist и используется им для определения корневого каталога проекта, а также `Project.swift`, где будет объявлен ваш проект:

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

> [!WARNING]
> Tuist использует каталог `Tuist/` для определения корня вашего проекта, а оттуда ищет другие файлы манифестов, сканируя каталоги. Мы рекомендуем создавать эти файлы в вашем редакторе кода, а после этого вы можете использовать `tuist edit` для редактирования проекта в Xcode.
