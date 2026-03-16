---
{
  "title": "Migrate a Swift Package",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects."
}
---
# 遷移 Swift 套件{#migrate-a-swift-package}

Swift Package Manager 最初是作為 Swift 程式碼的依賴項管理工具而出現，卻意外地解決了專案管理問題，並支援 Objective-C
等其他程式語言。由於該工具的設計初衷不同，若要藉此管理大規模專案，可能會面臨挑戰，因為它缺乏 Tuist 所具備的靈活性、效能與功能。
這一點在《[Scaling iOS at
Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2)》一文中已有精闢闡述，該文包含以下表格，比較了
Swift Package Manager 與原生 Xcode 專案的效能：

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

我們經常遇到開發者和組織質疑 Tuist 的必要性，認為 Swift Package Manager
也能承擔類似的專案管理角色。有些人嘗試進行遷移，事後卻發現開發體驗大幅下降。例如，重新命名一個檔案可能需要長達 15 秒才能重新索引。15 秒！

**蘋果是否會將 Swift Package Manager 打造成一個專為大規模環境設計的專案管理工具，目前尚屬未知。**
然而，我們尚未看到任何跡象顯示此事正在發生。事實上，我們看到的恰恰相反。他們正做出受 Xcode
啟發的決策，例如透過隱式配置來追求便利性，而這<LocalizedLink href="/guides/features/projects/cost-of-convenience">如您所知，</LocalizedLink>正是大規模環境下產生複雜性的根源。
我們認為，蘋果必須回歸第一性原理，重新審視某些在依賴項管理器層面上合理、但在專案管理器層面上卻不合適的決策，例如使用編譯語言作為定義專案的介面。

::: tip SPM AS JUST A DEPENDENCY MANAGER
<!-- -->
Tuist 將 Swift Package Manager
視為依賴項管理工具，而且它非常出色。我們使用它來解析依賴項並進行建置。我們不使用它來定義專案，因為它並非為此設計。
<!-- -->
:::

## 從 Swift Package Manager 遷移至 Tuist{#migrating-from-swift-package-manager-to-tuist}

`Swift Package Manager 與 Tuist 之間的相似之處，使得遷移過程相當直觀。主要差異在於，您將使用 Tuist 的 DSL
來定義專案，而非 Swift Package Manager 的 `Package.swift` 檔案` 。

首先，在您的`Package.swift` 檔案旁邊建立一個`Project.swift` 檔案。`Project.swift`
檔案將包含您的專案定義。以下是一個`Project.swift` 檔案的範例，該檔案定義了一個僅含單一目標的專案：

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

- **ProjectDescription**: 請改用`ProjectDescription` ，而非`PackageDescription` 。
- **專案：** 您將導出`專案` 實例，而非`套件` 實例。
- **Xcode 語言：** 您用來定義專案的基礎元素模仿了 Xcode 的語言，因此您會發現方案、目標和建置階段等項目。

接著建立一個名為 ``Tuist.swift` 的檔案（路徑為 `` `），內容如下：

```swift
import ProjectDescription

let tuist = Tuist()
```

`中的 Tuist.swift 檔案（` ）包含專案的設定，其路徑用作判定專案根目錄的參考依據。您可以參閱
<LocalizedLink href="/guides/features/projects/directory-structure">目錄結構</LocalizedLink>
文件，進一步了解 Tuist 專案的結構。

## 編輯專案{#editing-the-project}

您可以使用 <LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink> 在 Xcode 中編輯專案。此指令會產生一個 Xcode 專案，您可以開啟並開始進行開發。

```bash
tuist edit
```

視專案規模而定，您可以考慮一次性完成或分階段進行。我們建議先從小型專案著手，以熟悉 DSL
及工作流程。我們的建議是始終從最受依賴的目標開始，逐步處理至頂層目標。
