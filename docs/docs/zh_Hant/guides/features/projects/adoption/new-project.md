---
{
  "title": "Create a new project",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to create a new project with Tuist."
}
---
# 建立新專案{#create-a-new-project}

使用 Tuist 開啟新專案的最直接方法是使用`tuist init` 指令。此指令會啟動互動式
CLI，引導您設定專案。出現提示時，請務必選擇建立「已產生專案」的選項。

然後，您可以 <LocalizedLink href="/guides/features/projects/editing"> 編輯專案</LocalizedLink>，執行`tuist edit` ，Xcode
就會開啟一個專案，您可以在其中編輯專案。其中一個產生的檔案是`Project.swift` ，其中包含專案的定義。如果您熟悉 Swift Package
Manager，請將此視為`Package.swift` ，但使用 Xcode 專案的行話。

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
我們刻意保持可用範本清單的簡短，以盡量減少維護開銷。如果您想要建立一個不代表應用程式的專案，例如框架，您可以使用`tuist init`
作為起點，然後根據您的需求修改產生的專案。
<!-- -->
:::

## 手動建立專案{#manually-creating-a-project}

或者，您也可以手動建立專案。我們建議只有在您已經熟悉 Tuist 及其概念的情況下才這樣做。您需要做的第一件事是為專案結構建立額外的目錄：

```bash
mkdir MyFramework
cd MyFramework
```

然後建立`Tuist.swift` 檔案，此檔案將設定 Tuist，並由 Tuist 用來決定專案的根目錄，以及`Project.swift`
，您的專案將在此宣告：

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
Tuist 會使用`Tuist/` 目錄來判斷您專案的根目錄，並從該目錄尋找 globbing 目錄的其他 manifest
檔案。我們建議您使用所選的編輯器建立這些檔案，從此之後，您就可以使用`tuist edit` 來使用 Xcode 編輯專案。
<!-- -->
:::
