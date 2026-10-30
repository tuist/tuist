---
{
  "title": "建立新專案",
  "titleTemplate": ":title · 採用 · 專案 · 功能 · 指南 · Tuist",
  "description": "學習如何使用 Tuist 建立新專案。"
}
---
# 建立新專案 {#create-a-new-project}

使用 Tuist 開始新專案最直接嘅方法，就係執行 `tuist init` 指令。呢個指令會啟動一個互動式 CLI，引導你設定專案。當系統提示時，請務必選擇建立「generated project」嘅選項。

之後你可以 <.localized_link href="/guides/features/projects/editing">編輯專案</.localized_link>，執行 `tuist edit`，Xcode 就會開啟一個專案俾你編輯。其中一個生成嘅檔案係 `Project.swift`，包含咗你專案嘅定義。如果你熟悉 Swift Package Manager，可以將佢想像成 `Package.swift`，但用嘅係 Xcode 專案嘅術語。

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
> 我哋刻意保持可用範本清單簡短，以減低維護負擔。如果你想建立唔係應用程式嘅專案（例如 framework），可以用 `tuist init` 作為起點，然後修改生成嘅專案以符合你嘅需求。


## 手動建立專案 {#manually-creating-a-project}

另外，你亦可以手動建立專案。我哋建議只喺你已經熟悉 Tuist 同其概念時才咁做。你需要做嘅第一件事，就係為專案結構建立額外目錄：

```bash
mkdir MyFramework
cd MyFramework
```

然後建立 `Tuist.swift` 檔案，用嚟設定 Tuist，並讓 Tuist 確定專案嘅根目錄；同時建立 `Project.swift`，喺入面宣告你嘅專案：

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
> Tuist 使用 `Tuist/` 目錄來確定你專案嘅根目錄，並從那裡透過 globbing 搜尋其他 manifest 檔案。我哋建議用你鍾意嘅編輯器建立呢啲檔案，之後就可以用 `tuist edit` 透過 Xcode 編輯專案。
