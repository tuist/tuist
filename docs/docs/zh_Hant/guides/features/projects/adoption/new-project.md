---
{
  "title": "Create a new project",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to create a new project with Tuist."
}
---
# 建立新專案{#create-a-new-project}

使用 Tuist 建立新專案最直接的方式，是執行`tuist init`
指令。此指令會啟動一個互動式命令列介面，引導您完成專案設定。當系統提示時，請務必選擇建立「生成式專案」的選項。

接著，您可以執行`tuist edit` 來
<LocalizedLink href="/guides/features/projects/editing">編輯專案</LocalizedLink>，Xcode
便會開啟一個專案供您進行編輯。生成的檔案之一是`Project.swift` ，其中包含您專案的定義。如果您熟悉 Swift Package
Manager，可以將其視為`Package.swift` ，但採用了 Xcode 專案的術語。

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
我們刻意將可用範本清單保持簡短，以減少維護負擔。若您想建立不屬於應用程式的專案（例如框架），可使用`tuist init` 作為起點，並根據需求修改生成的專案。
<!-- -->
:::

## 手動建立專案{#manually-creating-a-project}

此外，您也可以手動建立專案。我們建議僅在您已熟悉 Tuist 及其相關概念時才採取此做法。首先，您需要為專案結構建立額外的目錄：

```bash
mkdir MyFramework
cd MyFramework
```

接著建立一個`Tuist.swift` 檔案，該檔案將用於配置 Tuist，並供 Tuist 藉此確定專案的根目錄；同時建立一個`Project.swift`
檔案，您的專案將在此處宣告：

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
Tuist 會使用`Tuist/` 目錄來確定專案的根目錄，並從該處透過通配符搜尋其他 manifests
檔案。我們建議您使用偏好的編輯器建立這些檔案，之後即可使用`tuist edit` 透過 Xcode 編輯專案。
<!-- -->
:::
