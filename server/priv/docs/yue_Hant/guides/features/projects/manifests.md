---
{
  "title": "清單檔案",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "定義 Tuist 專案、工作區及生成設定的清單檔案。"
}
---
# 清單 {#manifests}

Tuist 預設使用 Swift 檔案作為定義專案、工作區以及設定產生流程的主要方式。整份文件中將這些檔案稱為**清單檔案**。

選擇使用 Swift 的靈感來自於[Swift Package Manager](https://www.swift.org/documentation/package-manager/)，它同樣使用 Swift 檔案來定義套件。得益於使用 Swift，我們可以利用編譯器來驗證內容的正確性，並在不同的清單檔案之間重複使用程式碼；同時也能借助 Xcode 提供的語法高亮、自動完成和驗證功能，帶來一流的編輯體驗。

> [!NOTE]
> **快取**
>
> 由於清單檔案是需要編譯的 Swift 檔案，Tuist 會快取編譯結果以加速解析過程。因此，你會發現首次執行 Tuist 時，產生專案可能需要較長時間。後續執行則會更快。


## Project.swift {#projectswift}

[`Project.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/project)清單用於宣告一個 Xcode 專案。專案會在清單檔案所在的同一目錄中產生，名稱由`name`屬性指定。

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
> 清單根層級唯一應該存在的變數是`let project = Project(...)`。如果你需要在清單的不同部分重複使用程式碼，可以使用 Swift 函式。


## Workspace.swift {#workspaceswift}

預設情況下，Tuist 會產生一個包含正在產生的專案及其依賴專案的[Xcode Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces)。如果出於任何原因你想自訂工作區以添加額外專案或包含檔案與群組，可以透過定義[`Workspace.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/workspace)清單來實現。

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
> Tuist 會解析依賴圖並將依賴項的專案包含在工作區中。你無需手動添加它們。這對建構系統正確解析依賴關係是必要的。


### 多專案或單一專案 {#multi-or-monoproject}

常見的一個問題是：應該在工作區中使用單一專案還是多個專案？在沒有 Tuist 的世界裡，單一專案設置往往會導致頻繁的 Git 衝突，因此鼓勵使用工作區。然而，由於我們不建議將 Tuist 產生的 Xcode 專案納入 Git 儲存庫，Git 衝突就不再是問題。因此，選擇在工作區中使用單一專案還是多個專案取決於你。

在 Tuist 專案中，我們傾向於使用單一專案，因為冷啟動產生時間更快（需要編譯的清單檔案較少），並且我們利用<.localized_link href="/guides/features/projects/code-sharing">專案描述輔助工具</.localized_link>作為封裝單元。不過，你可能希望使用 Xcode 專案作為封裝單元來代表應用程式的不同領域，這更符合 Xcode 建議的專案結構。

## Tuist.swift {#tuistswift}

Tuist 提供<.localized_link href="/contributors/principles#default-to-conventions">合理的預設值</.localized_link>以簡化專案設定。不過，你可以透過在專案根目錄定義[`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist)來自訂設定，Tuist 會用它來確定專案的根目錄。

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
