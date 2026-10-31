---
{
  "title": "資訊清單",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "定義 Tuist 專案、工作區與產生設定的資訊清單檔案。"
}
---
# Manifest {#manifests}

Tuist 預設使用 Swift 檔案作為定義專案與工作區，以及設定產生流程的主要方式。這些檔案在整份文件中稱為**manifest 檔案**。

採用 Swift 的決定受到[Swift Package Manager](https://www.swift.org/documentation/package-manager/)啟發，後者同樣使用 Swift 檔案來定義套件。得益於使用 Swift，我們能利用編譯器驗證內容正確性，並在不同 manifest 檔案之間重複使用程式碼；同時也能借助 Xcode 的語法突顯、自動完成與驗證，提供一流的編輯體驗。

> [!NOTE]
> **快取**
>
> 由於 manifest 檔案是必須編譯的 Swift 檔案，Tuist 會快取編譯結果以加速解析流程。因此，你會發現首次執行 Tuist 時，產生專案可能需要較長時間。後續執行則會更快。


## Project.swift {#projectswift}

[`Project.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/project) manifest 用於宣告一個 Xcode 專案。專案會在 manifest 檔案所在目錄中產生，並以`name`屬性指定的名稱命名。

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
> manifest 根層級唯一應存在的變數是`let project = Project(...)`。若需要在 manifest 的不同部分重複使用程式碼，可以使用 Swift 函式。


## Workspace.swift {#workspaceswift}

預設情況下，Tuist 會產生包含正在產生的專案及其相依專案的[Xcode Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces)。若因任何原因你想要自訂工作區以加入額外專案或納入檔案與群組，可以透過定義[`Workspace.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/workspace) manifest 來達成。

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
> Tuist 會解析相依圖並將相依專案納入工作區。你無需手動加入它們。這對建置系統正確解析相依性是必要的。


### 多專案或單一專案 {#multi-or-monoproject}

常見的問題是應該在工作區中使用單一專案還是多個專案。在沒有 Tuist 的世界裡，單一專案設定往往會導致頻繁的 Git 衝突，因此鼓勵使用工作區。然而，由於我們不建議將 Tuist 產生的 Xcode 專案納入 Git 儲存庫，Git 衝突不再是問題。因此，選擇在工作區中使用單一或多個專案取決於你。

在 Tuist 專案中，我們傾向使用單一專案，因為冷啟動產生時間更快（需要編譯的 manifest 檔案較少），並且我們將<.localized_link href="/guides/features/projects/code-sharing">專案描述輔助工具</.localized_link>作為封裝單元。不過，你也可能希望以 Xcode 專案作為封裝單元來代表應用程式的不同領域，這更貼近 Xcode 建議的專案結構。

## Tuist.swift {#tuistswift}

Tuist 提供<.localized_link href="/contributors/principles#default-to-conventions">合理的預設值</.localized_link>以簡化專案設定。不過，你可以透過在專案根目錄定義[`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist)來自訂設定，Tuist 會藉此判斷專案的根目錄。

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
