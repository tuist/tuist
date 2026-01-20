---
{
  "title": "Manifests",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the manifest files that Tuist uses to define projects and workspaces and configure the generation process."
}
---
# 表現{#manifests}

Tuist 預設以 Swift 檔案作為定義專案和工作區以及設定產生程序的主要方式。這些檔案在整個文件中被稱為**manifest files** 。

使用 Swift 的決定是受到 [Swift Package
Manager](https://www.swift.org/documentation/package-manager/) 的啟發，它也使用 Swift
檔案來定義套件。由於使用 Swift，我們可以利用編譯器來驗證內容的正確性，並在不同的清單檔案中重複使用程式碼，而 Xcode
則可利用語法高亮、自動完成和驗證功能，提供一流的編輯體驗。

::: info CACHING
<!-- -->
由於清单文件是需要编译的 Swift 文件，Tuist 会缓存编译结果以加快解析过程。因此，您會發現第一次執行 Tuist
時，產生專案的時間可能會稍長。之後的執行將會更快。
<!-- -->
:::

## Project.swift{#projectswift}

<LocalizedLink href="/references/project-description/structs/project">`Project.swift`</LocalizedLink>
manifest 宣告了一個 Xcode 專案。專案會在清單檔案所在的同一個目錄中產生，其名稱會在`name` 屬性中顯示。

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
唯一應該在 manifest 根部的變數是`let project = Project(...)` 。如果您需要在清单的各个部分重用代码，可以使用 Swift
函数。
<!-- -->
:::

## 工作區.swift{#workspaceswift}

預設情況下，Tuist 會產生一個 [Xcode
Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces)
包含正在產生的專案及其相依專案。如果基於任何原因，您想要自訂工作區以新增其他專案或包含檔案與群組，您可以透過定義
<LocalizedLink href="/references/project-description/structs/workspace">`Workspace.swift`</LocalizedLink>
清单來達成。

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
Tuist 會解析相依性圖形，並將相依性的專案包含在工作區中。您不需要手動包含它們。這是建立系統正確解析相依性所必需的。
<!-- -->
:::

### 多專案或單專案{#multi-or-monoproject}

一個經常出現的問題是在工作區中使用單一專案還是多專案。在沒有 Tuist 的世界裡，單一專案的設定會導致頻繁的 Git
衝突，因此我們鼓勵使用工作區。但是，由於我們不建議在 Git 倉庫中包含 Tuist 生成的 Xcode 專案，因此 Git
衝突不是問題。因此，在工作區中使用單一專案或多個專案的決定權在您。

在 Tuist 專案中，我們傾向使用單一專案，因為冷生成時間較快（需要編譯的manifest檔案較少），而且我們利用
<LocalizedLink href="/guides/features/projects/code-sharing">Project description helpers</LocalizedLink> 作為封裝單位。然而，您可能希望使用 Xcode 專案作為封裝單位，以代表應用程式的不同領域，這與 Xcode
所推薦的專案結構更為接近。

## Tuist.swift{#tuistswift}

Tuist 提供了
<LocalizedLink href="/contributors/principles.html#default-to-conventions">合理的預設值</LocalizedLink>來簡化專案配置。不過，您可以透過在專案根目錄定義
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
來自訂配置，Tuist 會使用它來判斷專案的根目錄。

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
