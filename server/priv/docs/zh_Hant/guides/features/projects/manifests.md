---
{
  "title": "資訊清單",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "定義 Tuist 專案、工作區與產生設定的資訊清單檔案。"
}
---
# Manifests {#manifests}

Tuist 預設使用 Swift 檔案作為定義專案與工作區，以及設定產生流程的主要方式。這些檔案在文件中稱為**資訊清單檔案**。

採用 Swift 的決定受到[Swift Package Manager](https://www.swift.org/documentation/package-manager/)的啟發，後者也使用 Swift 檔案來定義套件。得益於使用 Swift，我們可以借助編譯器驗證內容的正確性，並在不同資訊清單檔案之間重複使用程式碼；同時也能利用 Xcode 提供的語法突顯、自動完成與驗證功能，帶來一流的編輯體驗。

> [!NOTE]
> **快取**
>
> 由於 manifest 檔案是需要編譯的 Swift 檔案，Tuist 會快取編譯結果以加速解析流程。因此，你會發現首次執行 Tuist 時，產生專案所需的時間可能稍長。後續執行則會更快。


## Project.swift {#projectswift}

[`Project.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/project)資訊清單用於宣告一個 Xcode 專案。專案會產生在資訊清單檔案所在的同一目錄中，並以`name`屬性所指定的名稱命名。

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```


> [!WARNING]
> **根層級變數**
>
> 資訊清單根層級唯一應存在的變數是`let project = Project(...)`。若需要在資訊清單的不同部分重複使用程式碼，可以使用 Swift 函式。


## Workspace.swift {#workspaceswift}

預設情況下，Tuist 會產生一個包含正在產生的專案及其相依專案的[Xcode Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces)。如果因任何原因需要自訂工作區以新增其他專案或加入檔案與群組，可以透過定義[`Workspace.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/workspace)資訊清單來達成。

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

> [!NOTE]
> Tuist 會解析相依圖，並將相依專案納入工作區中。你無需手動加入它們。這對於建置系統正確解析相依性是必要的。


### 多專案或單一專案 {#multi-or-monoproject}

常見的問題是應該在工作區中使用單一專案還是多個專案。在沒有 Tuist 的情境下，單一專案設定容易導致頻繁的 Git 衝突，因此通常建議使用工作區。然而，由於我們不建議將 Tuist 產生的 Xcode 專案納入 Git 儲存庫，Git 衝突並非問題。因此，選擇在工作區中使用單一專案或多個專案取決於你的決定。

在 Tuist 專案中，我們傾向使用單一專案，因為冷啟動產生速度較快（需要編譯的資訊清單檔案較少），並且我們將<.localized_link href="/guides/features/projects/code-sharing">專案描述輔助工具</.localized_link>作為封裝單元。不過，你也可能希望將 Xcode 專案作為封裝單元，以代表應用程式的不同領域，這更符合 Xcode 建議的專案結構。

## Tuist.swift {#tuistswift}

Tuist 提供<.localized_link href="/contributors/principles#default-to-conventions">合理的預設值</.localized_link>以簡化專案設定。不過，你可以透過在專案根目錄定義[`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist)來自訂設定，Tuist 會藉此判斷專案的根目錄。

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
