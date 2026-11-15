---
{
  "title": "遷移 Swift Package",
  "titleTemplate": ":title · 遷移 · 採用 · 專案 · 功能 · 指南 · Tuist",
  "description": "從 Swift Package Manager 的專案管理遷移至 Tuist。"
}
---
# 遷移 Swift Package {#migrate-a-swift-package}

Swift Package Manager 最初係為 Swift 程式碼而設嘅依賴管理工具，但無意中承擔咗項目管理同支援其他程式語言（例如 Objective-C）嘅角色。由於呢個工具係為另一個目的而設計，佢缺乏 Tuist 所提供嘅彈性、效能同能力，因此好難用佢嚟大規模管理項目。[Scaling iOS at Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2) 一文清楚說明咗呢一點，當中包含以下表格，比較 Swift Package Manager 同原生 Xcode 項目嘅效能：

<img style="max-width: 400px;" alt="比較使用 SPM 相對原生 Xcode 項目時效能倒退嘅表格" src="/images/guides/start/migrate/performance-table.webp">

我哋經常遇到開發者同機構質疑 Tuist 嘅必要性，認為 Swift Package Manager 可以擔任類似嘅項目管理角色。有些人嘗試遷移，後來先發現開發體驗嚴重下降。例如，重新命名一個檔案可能需要長達 15 秒來重新索引。15 秒呀！

**Apple 會否將 Swift Package Manager 打造成適合大規模使用嘅項目管理工具，仍然未可知。** 不過，我哋見唔到任何跡象顯示會發生呢件事。事實上，情況恰恰相反。佢哋作出受 Xcode 啟發嘅決定，例如透過隱式設定嚟達到便利，而<.localized_link href="/guides/features/projects/cost-of-convenience">正如你可能知道，</.localized_link>這正係大規模下產生複雜性嘅根源。我哋認為 Apple 需要回歸基本原則，重新審視一些作為依賴管理工具有意義、但作為項目管理工具卻不合理嘅決定，例如使用編譯型語言作為定義項目嘅介面。

> [!TIP]
> **SwiftPM 只作為依賴管理工具**
>
> Tuist 將 Swift Package Manager 視為依賴管理工具，而且佢做得好好。我哋用佢來解析同構建依賴項。我哋唔用佢來定義項目，因為佢並非為此而設計。如需並排比較，請參閱[Swift Package Manager vs Tuist](https://tuist.dev/compare/swift-package-manager)。


## 從 Swift Package Manager 遷移到 Tuist {#migrating-from-swift-package-manager-to-tuist}

Swift Package Manager 同 Tuist 之間嘅相似之處令遷移過程變得簡單直接。主要分別在於，你會使用 Tuist 嘅 DSL 而非 `Package.swift` 來定義你嘅項目。

首先，喺你嘅 `Package.swift` 檔案旁邊建立一個 `Project.swift` 檔案。`Project.swift` 檔案將包含你項目嘅定義。以下係一個 `Project.swift` 檔案嘅示例，定義咗一個單一目標嘅項目：

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

需要注意嘅幾點：

- **ProjectDescription**：你將使用 `ProjectDescription`，而非 `PackageDescription`。
- **Project：** 你將導出一個 `project` 實例，而非 `package` 實例。
- **Xcode 語言：** 你用嚟定義項目嘅基本元素模仿咗 Xcode 嘅語言，因此你會找到 scheme、目標同構建階段等。

然後建立一個 `Tuist.swift` 檔案，內容如下：

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift` 包含你項目嘅配置，其路徑用作確定項目根目錄嘅參考。你可以查閱<.localized_link href="/guides/features/projects/directory-structure">目錄結構</.localized_link>文件，以進一步了解 Tuist 項目嘅結構。

## 編輯項目 {#editing-the-project}

你可以使用 <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link> 喺 Xcode 中編輯項目。該命令會生成一個 Xcode 項目，你可以打開並開始工作。

```bash
tuist edit
```

視乎項目大小，你可以考慮一次性或增量方式使用。我哋建議從小型項目開始，以熟悉 DSL 同工作流程。我哋嘅建議始終係從被依賴最多嘅目標開始，逐步向上直至頂層目標。
