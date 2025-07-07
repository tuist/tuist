---
title: Создание нового проекта
titleTemplate: :title · Adoption · Projects · Features · Guides · Tuist
description: Научитесь создавать новый проект с помощью Tuist.
---

# Создание нового проекта {#create-a-new-project}

Самый простой способ начала знакомства с Tuist – использовать команду `tuist init`. Эта команда запускает интерактивный интерфейс командной строки, который поможет вам настроить ваш проект. При появлении соответствующего запроса обязательно выберите опцию создания «сгенерированного проекта».

Вы можете <LocalizedLink href="/guides/features/projects/editing">редактировать</LocalizedLink> проект запустив `tuist edit` и Xcode откроет проект для редактирования. Одним из созданых файлов будет `Project.swift`, который содержит описание вашего проекта. Если вы знакомы с Swift Package Manager, то это похоже с `Package.swift`, но для настройки проектов Xcode.

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
            bundleId: "io.tuist.MyApp",
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
            bundleId: "io.tuist.MyAppTests",
            infoPlist: .default,
            sources: ["MyApp/Tests/**"],
            resources: [],
            dependencies: [.target(name: "MyApp")]
        ),
    ]
)
```

:::

> [!NOTE]
> Мы намеренно держим список доступных шаблонов коротким, чтобы свести к минимуму затраты на их поддержку. Если вы хотите создать проект, который не является приложением, например, фреймворк, вы можете использовать `tuist init` в качестве отправной точки, а затем модифицировать созданный проект в соответствии с вашими нуждами.

## Создание проекта вручную {#manually-creating-a-project}

Также, вы можете создать проект вручную. Мы рекомендуем делать это только, если вы уже знакомы с Tuist и его концепциями. Первое, что вам нужно будет сделать – создать дополнительные папки для структуры проекта:

```bash
mkdir MyFramework
cd MyFramework
```

Затем создайте файл `Tuist.swift`, который будет настраивать Tuist и использоваться для определения корневой папки проекта, а также файл `Project.swift`, где будет объявлен ваш проект:

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
            bundleId: "io.tuist.MyFramework",
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

:::

> [!IMPORTANT]
> Tuist использует папку `Tuist/` для определения корня вашего проекта, а затем ищет другие файлы манифеста в папках. Мы рекомендуем создать эти файлы в вашем редакторе, и потом использовать `tuist edit` для редактирования проекта в Xcode.
