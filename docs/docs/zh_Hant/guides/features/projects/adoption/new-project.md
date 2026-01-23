---
{
  "title": "Create a new project",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to create a new project with Tuist."
}
---
# 建立新專案{#create-a-new-project}

使用 Tuist 建立新專案最直接的方式，是執行 ``` tuist init`
指令。此指令將啟動互動式命令列介面，引導您完成專案設定。當系統提示時，請務必選擇建立「生成式專案」的選項。

接著可透過執行`tuist
edit`<LocalizedLink href="/guides/features/projects/editing">編輯專案</LocalizedLink>，Xcode
將開啟專案編輯介面。其中生成的檔案包含`Project.swift` ，此檔案定義專案架構。若您熟悉 Swift Package Manager，可將其視為採用
Xcode 專案語法的`Package.swift` 。

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
我們刻意將可用範本清單保持簡短，以減少維護負擔。若您想建立非應用程式類型的專案（例如框架），可使用 ``` 作為起點，執行 `tuist init` `
生成專案後再依需求修改。
<!-- -->
:::

## 手動建立專案{#manually-creating-a-project}

您亦可手動建立專案。若您已熟悉 Tuist 及其概念，我們建議採用此方式。首先需為專案結構建立額外目錄：

```bash
mkdir MyFramework
cd MyFramework
```

` 接著建立 Tuist.swift 檔案（`），此檔案將配置 Tuist 並用於確定專案根目錄；另建立 Project.swift
檔案（`），用於宣告專案（` ）。

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
Tuist 透過`Tuist/` 目錄來判定專案根目錄，並從該處搜尋其他採用目錄通配符的清單檔案。建議您使用偏好的編輯器建立這些檔案，此後即可透過`tuist
edit` 指令以 Xcode 編輯專案。
<!-- -->
:::
