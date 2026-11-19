---
{
  "title": "遷移 Swift Package",
  "titleTemplate": ":title · 遷移 · 採用 · 專案 · 功能 · 指南 · Tuist",
  "description": "從 Swift Package Manager 的專案管理遷移至 Tuist。"
}
---
# 遷移 Swift Package {#migrate-a-swift-package}

Swift Package Manager 最初係作為 Swift 程式碼嘅依賴管理工具出現，但無意中變成咗解決專案管理同支援其他程式語言（例如 Objective-C）問題嘅方案。由於呢個工具設計初衷唔同，要佢大規模管理專案會比較困難，因為佢缺乏 Tuist 所提供嘅靈活性、效能同能力。[Scaling iOS at Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2) 一文清楚說明咗呢一點，文中包含以下表格，比較 Swift Package Manager 同原生 Xcode 專案嘅效能：

<img style="max-width: 400px;" alt="比較使用 SPM 相對原生 Xcode 專案時效能倒退嘅表格" src="/images/guides/start/migrate/performance-table.webp">

我哋經常遇到開發者同機構質疑 Tuist 嘅必要性，認為 Swift Package Manager 可以承擔類似嘅專案管理角色。有啲人嘗試遷移之後，先發現開發體驗明顯下降。例如，重新命名一個檔案可能需要長達 15 秒來重新建立索引。15 秒呀！

**Apple 會否將 Swift Package Manager 打造為適合大規模使用嘅專案管理工具，目前仍不確定。** 不過，我哋未見到任何相關跡象。事實上，情況似乎相反。佢哋作出受 Xcode 啟發嘅決定，例如透過隱式設定來實現便利性，而<.localized_link href="/guides/features/projects/cost-of-convenience">你可能知道，</.localized_link>這正係大規模應用時產生複雜性嘅根源。我哋認為，Apple 需要回歸基本原則，重新審視一啲作為依賴管理工具有意義、但作為專案管理工具卻唔合適嘅決定，例如使用編譯型語言作為定義專案嘅介面。

> [!TIP]
> **SwiftPM 僅作為依賴管理工具**
>
> Tuist 將 Swift Package Manager 視為依賴管理工具，而且佢做得好好。我哋用佢來解析同構建依賴項。我哋唔用佢來定義專案，因為佢並非為此而設計。如需並排比較，請參閱[Swift Package Manager vs Tuist](https://tuist.dev/compare/swift-package-manager)。


## 從 Swift Package Manager 遷移到 Tuist {#migrating-from-swift-package-manager-to-tuist}

Swift Package Manager 同 Tuist 之間嘅相似之處令遷移過程變得直接。主要分別在於，你會使用 Tuist 嘅 DSL 而非 `Package.swift` 來定義你嘅專案。

首先，喺你嘅 `Package.swift` 檔案旁邊建立一個 `Project.swift` 檔案。`Project.swift` 檔案將包含你專案嘅定義。以下係一個 `Project.swift` 檔案嘅示例，該檔案定義咗一個具單一 target 嘅專案：

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

需要注意嘅事項：

- **ProjectDescription**：唔使用 `PackageDescription`，而係使用 `ProjectDescription`。
- **Project：** 唔匯出 `package` 實例，而係匯出 `project` 實例。
- **Xcode 語言：** 你用來定義專案嘅基本元素模仿咗 Xcode 嘅語言，因此你會找到 schemes、targets 同 build phases 等。

然後建立一個具有以下內容嘅 `Tuist.swift` 檔案：

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift` 包含你專案嘅配置，其路徑用作確定專案根目錄嘅參考。你可以查看<.localized_link href="/guides/features/projects/directory-structure">目錄結構</.localized_link>文件，以了解更多關於 Tuist 專案結構嘅資訊。

## 編輯專案 {#editing-the-project}

你可以使用 <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link> 喺 Xcode 中編輯專案。該命令會生成一個 Xcode 專案，你可以打開並開始工作。

```bash
tuist edit
```

視乎專案大小，你可以考慮一次性或逐步使用。我哋建議從小型專案開始，以熟悉 DSL 同工作流程。我哋嘅建議始終係從被依賴最多嘅 target 開始，逐步向上直到頂層 target。
