---
{
  "title": "Manifests",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the manifest files that Tuist uses to define projects and workspaces and configure the generation process."
}
---
# 清單{#manifests}

Tuist 預設以 Swift 檔案作為定義專案與工作區、配置生成流程的主要方式。此類檔案在文件中統稱為「**」清單檔案（詳見** ）。

採用 Swift 的決策靈感源自 [Swift Package
Manager](https://www.swift.org/documentation/package-manager/)，該工具同樣使用 Swift
檔案定義套件。得益於 Swift 的應用，我們能運用編譯器驗證內容正確性，並在不同清單檔案間重複使用程式碼；同時藉由 Xcode
提供的語法標示、自動完成與驗證功能，實現一流的編輯體驗。

::: info CACHING
<!-- -->
由於清單檔案是需要編譯的 Swift 檔案，Tuist 會快取編譯結果以加速解析流程。因此您會發現，初次執行 Tuist
時生成專案可能耗時較長，後續執行將更為迅速。
<!-- -->
:::

## Project.swift{#projectswift}

<LocalizedLink href="/references/project-description/structs/project">`Project.swift`</LocalizedLink>
程式清單宣告一個 Xcode 專案。該專案將生成於程式清單檔案所在目錄，其名稱取自`name` 屬性所指定的名稱。

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```


::: warning ROOT VARIABLES
<!-- -->
清單根層級僅應包含變數：`let project = Project(...)` 若需在清單各處重複使用程式碼，可採用 Swift 函式。
<!-- -->
:::

## 工作區.swift{#workspaceswift}

預設情況下，Tuist 會生成一個 [Xcode
工作區](https://developer.apple.com/documentation/xcode/projects-and-workspaces)，其中包含正在生成的專案及其依賴項的專案。若因任何原因需要自訂工作區以新增專案或包含檔案與群組，可透過定義
<LocalizedLink href="/references/project-description/structs/workspace">`Workspace.swift`</LocalizedLink>
清單檔案來實現。

```swift
// Workspace.swift
import ProjectDescription

let workspace = Workspace(
    name: "App-Workspace",
    projects: [
        "./App", // Path to directory containing the Project.swift file
    ]
)
```

::: info
<!-- -->
Tuist 將解析依賴關係圖，並將依賴項目的專案納入工作區。您無需手動包含這些項目。此步驟對於建置系統正確解析依賴關係至關重要。
<!-- -->
:::

### 多專案或單一專案{#multi-or-monoproject}

常見疑問在於工作區應採用單一專案或多專案架構。在未導入 Tuist 的環境中，單一專案設定易引發頻繁 Git
衝突，此時建議使用工作區管理。然而，由於我們不建議將 Tuist 生成的 Xcode 專案納入 Git 儲存庫，Git
衝突問題便不復存在。因此，工作區採用單一或多專案架構，可依實際需求自行決定。

在 Tuist 專案中，我們採用單一專案架構，因其冷啟動時間較短（需編譯的清單檔案較少），並運用
<LocalizedLink href="/guides/features/projects/code-sharing">專案描述輔助工具</LocalizedLink>作為封裝單位。然而，您可能希望使用
Xcode 專案作為封裝單位來呈現應用程式的不同領域，此做法更貼近 Xcode 建議的專案結構。

## Tuist.swift{#tuistswift}

`Tuist 提供 <LocalizedLink
href="/contributors/principles.html#default-to-conventions">合理的預設值</LocalizedLink>以簡化專案設定。但您可透過在專案根目錄定義
<LocalizedLink href="/references/project-description/structs/tuist"> Tuist.swift
中的 </LocalizedLink>`來自訂設定，Tuist 將以此檔案判定專案根目錄。

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
