---
{
  "title": "Create a new project",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to create a new project with Tuist."
}
---
# Создайте новый проект {#create-a-new-project}

Самый простой способ начать новый проект с помощью Tuist - использовать команду
`tuist init`. Эта команда запускает интерактивный CLI, который проведет вас
через настройку проекта. При появлении запроса обязательно выберите опцию
создания "сгенерированного проекта".

Затем вы можете
<LocalizedLink href="/guides/features/projects/editing">редактировать
проект</LocalizedLink>, запустив команду `tuist edit`, и Xcode откроет проект, в
котором вы можете его редактировать. Один из генерируемых файлов -
`Project.swift`, который содержит определение вашего проекта. Если вы знакомы с
менеджером пакетов Swift, думайте о нем как о `Package.swift`, но на языке
проектов Xcode.

::: кодовая группа
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
:::

> [!ПРИМЕЧАНИЕ] Мы намеренно сокращаем список доступных шаблонов, чтобы
> минимизировать затраты на обслуживание. Если вы хотите создать проект, который
> не представляет собой приложение, например фреймворк, вы можете использовать
> `tuist init` в качестве отправной точки, а затем изменить сгенерированный
> проект в соответствии с вашими потребностями.

## Создание проекта вручную {#manually-creating-a-project}

Кроме того, вы можете создать проект вручную. Мы рекомендуем делать это только в
том случае, если вы уже знакомы с Tuist и его концепциями. Первое, что вам нужно
будет сделать, - это создать дополнительные каталоги для структуры проекта:

```bash
mkdir MyFramework
cd MyFramework
```

Затем создайте файл `Tuist.swift`, который будет конфигурировать Tuist и
использоваться им для определения корневого каталога проекта, и файл
`Project.swift`, в котором будет объявлен ваш проект:

::: кодовая группа
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
:::

> [!ВАЖНО] Tuist использует каталог `Tuist/` для определения корня вашего
> проекта, а затем ищет другие файлы манифеста в каталогах. Мы рекомендуем
> создать эти файлы в выбранном вами редакторе, и с этого момента вы можете
> использовать `tuist edit` для редактирования проекта в Xcode.
