---
{
  "title": "建立新專案",
  "titleTemplate": ":title · 採用 · 專案 · 功能 · 指南 · Tuist",
  "description": "瞭解如何使用 Tuist 建立新專案。"
}
---
# 建立新專案 {#create-a-new-project}

使用 Tuist 啟動新專案最直接的方式是執行 `tuist init` 指令。此指令會啟動互動式 CLI，引導你完成專案設定。出現提示時，請務必選擇建立「generated project」的選項。

接著你可以<.localized_link href="/guides/features/projects/editing">編輯專案</.localized_link>，執行 `tuist edit` 後，Xcode 會開啟一個讓你編輯專案的專案。其中一個產生的檔案是 `Project.swift`，它包含你的專案定義。如果你熟悉 Swift Package Manager，可以把它想成是 `Package.swift`，但採用 Xcode 專案的語彙。

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
> 我們刻意將可用範本清單保持簡短，以降低維護負擔。如果你想建立的專案不是應用程式（例如 framework），可以使用 `tuist init` 作為起點，然後修改產生的專案以符合你的需求。


## 手動建立專案 {#manually-creating-a-project}

或者，你也可以手動建立專案。我們建議僅在你已熟悉 Tuist 及其概念時才這麼做。你需要做的第一件事是為專案結構建立額外的目錄：

```bash
mkdir MyFramework
cd MyFramework
```

接著建立 `Tuist.swift` 檔案，它會設定 Tuist，並供 Tuist 用來判斷專案的根目錄；同時建立 `Project.swift`，用於宣告你的專案：

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
> Tuist 使用 `Tuist/` 目錄來判斷專案的根目錄，並從該處透過 glob 搜尋其他 manifest 檔案。我們建議使用你慣用的編輯器建立這些檔案，之後即可使用 `tuist edit` 在 Xcode 中編輯專案。
