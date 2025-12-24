---
{
  "title": "Migrate a Swift Package",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects."
}
---
# 遷移 Swift 套件{#migrate-a-swift-package}

Swift Package Manager 是作為 Swift 程式碼的相依性管理器而出現的，它無意中發現自己解決了管理專案的問題，並支援
Objective-C 等其他程式語言。由於這個工具的設計目的不同，要使用它來管理規模化的專案可能會很有挑戰性，因為它缺乏 Tuist
所提供的彈性、效能和功能。這一點在【Scaling iOS at
Bumble】(https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2)一文中得到了很好的體現，其中包括下表對
Swift Package Manager 和原生 Xcode 專案性能的比較：

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

我們經常遇到開發人員和組織質疑是否需要 Tuist，因為 Swift Package Manager
也可以扮演類似的專案管理角色。有些人冒險進行遷移，但後來卻發現他們的開發人員體驗顯著下降。例如，重新命名檔案可能需要 15 秒才能重新索引。15 秒！

**Apple 是否會讓 Swift Package Manager 成為專為大型專案而設計的管理程式，目前還不確定。**
然而，我們並沒有看到任何跡象顯示這正在發生。事實上，我們看到的恰恰相反。他們正在做一些受到 Xcode
啟發的決定，例如透過隱含的配置來達到便利性，<LocalizedLink href="/guides/features/projects/cost-of-convenience">如您所知，</LocalizedLink>這正是規模複雜性的來源。我們認為蘋果應該遵循第一原則，重新檢視一些作為依賴管理者而非專案管理者的決策，例如使用編譯語言作為定義專案的介面。

::: tip SPM AS JUST A DEPENDENCY MANAGER
<!-- -->
Tuist 將 Swift Package Manager
視為相依性管理器，而且是很棒的相依性管理器。我們用它來解決相依性並建立相依性。我們不用它來定義專案，因為它不是為此而設計的。
<!-- -->
:::

## 從 Swift 套件管理員遷移至 Tuist{#migrating-from-swift-package-manager-to-tuist}

Swift Package Manager 與 Tuist 之間的相似性讓遷移過程變得簡單直接。主要差別在於您將使用 Tuist 的 DSL
定義專案，而非`Package.swift` 。

首先，在`Package.swift` 檔案旁建立`Project.swift` 檔案。`Project.swift`
檔案將包含專案的定義。以下是`Project.swift` 檔案的範例，它定義了一個只有單一目標的專案：

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

有些事情需要注意：

- **ProjectDescription** ：不使用`PackageDescription` ，而使用`ProjectDescription` 。
- **專案：** 您匯出的不是`套件` 範例，而是`專案` 範例。
- **Xcode 語言：** 您用來定義專案的基元會模仿 Xcode 的語言，因此您會發現方案、目標和建立階段等等。

然後建立`Tuist.swift` 檔案，內容如下：

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift` 包含專案的設定，其路徑可作為判定專案根目錄的參考。您可以查看
<LocalizedLink href="/guides/features/projects/directory-structure"> 目錄結構</LocalizedLink>文件，瞭解更多關於 Tuist 專案結構的資訊。

## 編輯專案{#editing-the-project}

您可以使用 <LocalizedLink href="/guides/features/projects/editing">`tuist edit`</LocalizedLink> 在 Xcode 中編輯專案。該指令會產生一個 Xcode 專案，您可以開啟並開始工作。

```bash
tuist edit
```

根據專案的大小，您可以考慮一次過使用或逐步使用。我們建議您先從小型專案開始，以熟悉 DSL 和工作流程。我們的建議是從最依賴的目標開始，一直到頂層目標。
