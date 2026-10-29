---
{
  "title": "遷移 Swift Package",
  "titleTemplate": ":title · 遷移 · 採用 · 專案 · 功能 · 指南 · Tuist",
  "description": "從 Swift Package Manager 的專案管理遷移至 Tuist。"
}
---
# 遷移 Swift Package {#migrate-a-swift-package}

Swift Package Manager 最初是作為 Swift 程式碼的相依性管理工具出現，卻意外地承擔起專案管理與支援 Objective-C 等其他程式語言的角色。由於該工具的設計初衷不同，在大型專案中使用它來管理專案會面臨挑戰，因為它缺乏 Tuist 所提供的彈性、效能與強大功能。[Scaling iOS at Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2) 一文清楚說明了這一點，其中包含以下表格，比較了 Swift Package Manager 與原生 Xcode 專案的效能：

<img style="max-width: 400px;" alt="比較使用 SPM 相較於原生 Xcode 專案時效能退化的表格" src="/images/guides/start/migrate/performance-table.webp">

我們經常遇到開發者與組織質疑是否需要 Tuist，認為 Swift Package Manager 可以擔任類似的專案管理角色。有些人嘗試遷移後，才發現開發體驗大幅下滑。例如，重新命名一個檔案可能需要長達 15 秒才能完成重新索引。15 秒！

**Apple 是否會讓 Swift Package Manager 成為專為大規模設計的專案管理工具，目前仍不確定。** 然而，我們並未看到任何跡象顯示這正在發生。事實上，我們看到的是相反的情況。他們做出以 Xcode 為靈感的決策，例如透過隱式設定來達成便利性，而<.localized_link href="/guides/features/projects/cost-of-convenience">如你所知，</.localized_link>這正是大規模下產生複雜性的根源。我們認為，Apple 需要回歸基本原則，重新檢視一些作為相依性管理工具有意義、但作為專案管理工具並不合理的決策，例如使用編譯型語言作為定義專案的介面。

> [!TIP]
> **將 SPM 僅視為相依性管理工具**
>
> Tuist 將 Swift Package Manager 視為相依性管理工具，而且它在這方面表現出色。我們用它來解析並建置相依性。我們不會用它來定義專案，因為它並非為此設計。


## 從 Swift Package Manager 遷移至 Tuist {#migrating-from-swift-package-manager-to-tuist}

Swift Package Manager 與 Tuist 之間的相似性讓遷移過程變得直截了當。主要差異在於，你將使用 Tuist 的 DSL 而非 `Package.swift` 來定義專案。

首先，在 `Package.swift` 旁邊建立 `Project.swift` 檔案。`Project.swift` 檔案將包含你的專案定義。以下是一個 `Project.swift` 檔案的範例，定義了一個包含單一目標的專案：

```swift
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            sources: ["Sources/**/*.swift"]*
        ),
    ]
)
```

注意事項：

- **ProjectDescription**：你將使用 `ProjectDescription`，而非 `PackageDescription`。
- **Project：** 你將匯出 `project` 執行個體，而非 `package` 執行個體。
- **Xcode 語言：** 你用來定義專案的原語模仿了 Xcode 的語言，因此你會找到 Scheme、目標與建置階段等元素。

接著建立包含以下內容的 `Tuist.swift` 檔案：

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift` 包含你的專案設定，其路徑可作為判斷專案根目錄的參考。你可以查看<.localized_link href="/guides/features/projects/directory-structure">目錄結構</.localized_link>文件，進一步了解 Tuist 專案的結構。

## 編輯專案 {#editing-the-project}

你可以使用 <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link> 在 Xcode 中編輯專案。該指令會產生一個 Xcode 專案，你可以開啟並開始進行開發。

```bash
tuist edit
```

視專案規模而定，你可以考慮一次性或逐步採用。我們建議從小型專案開始，以熟悉 DSL 與工作流程。我們的建議始終是從被依賴最多的目標開始，一路向上處理到最上層的目標。
