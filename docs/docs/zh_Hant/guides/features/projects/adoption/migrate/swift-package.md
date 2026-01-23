---
{
  "title": "Migrate a Swift Package",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects."
}
---
# 遷移 Swift 套件{#migrate-a-swift-package}

Swift Package Manager 作為 Swift 程式碼的依賴管理工具，意外地解決了專案管理與支援 Objective-C
等其他程式語言的問題。由於該工具最初設計目的不同，若用於大規模專案管理將面臨挑戰，其靈活性、效能與功能皆不及 Tuist 所提供的解決方案。
此現象在[Bumble 的 iOS
擴展規模](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2)一文中得到精闢闡述，其中包含以下比較
Swift Package Manager 與原生 Xcode 專案效能的對照表：

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

我們經常遇到質疑 Tuist 必要性的開發者與組織，認為 Swift Package Manager
也能承擔類似的專案管理功能。有些團隊嘗試遷移後，才發現開發體驗大幅退化。舉例來說，重新索引一個檔案的重命名操作，可能耗時長達 15 秒。15 秒！

**蘋果是否會將 Swift Package Manager 打造成大規模專案管理工具尚屬未知。**
然而目前並無跡象顯示此計畫正在推進，實際情況恰恰相反。他們正採取類似 Xcode
的決策模式，例如透過隱式配置實現便利性——<LocalizedLink href="/guides/features/projects/cost-of-convenience">如您所知，</LocalizedLink>這正是大規模運作中問題的根源。
我們認為蘋果需回歸第一性原理，重新審視某些作為依賴管理器合理、但作為專案管理器卻不適用的決策——例如採用編譯語言作為定義專案的介面。

::: tip SPM AS JUST A DEPENDENCY MANAGER
<!-- -->
Tuist 將 Swift Package Manager
視為依賴管理工具，且表現優異。我們運用它來解析依賴關係並進行建置，但不會用它來定義專案，因為其設計初衷並非如此。
<!-- -->
:::

## 從 Swift Package Manager 遷移至 Tuist{#migrating-from-swift-package-manager-to-tuist}

Swift Package Manager 與 Tuist 之間的相似性使遷移過程相當直觀。主要差異在於您將使用 Tuist 的 DSL
來定義專案，而非透過`Package.swift` 進行設定。

首先，在您的`Package.swift` 檔案旁建立`Project.swift` 檔案。該`Project.swift`
檔案將包含專案定義。以下為定義單一目標專案的範例`Project.swift` 檔案：

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

- ** `ProjectDescription**: 請改用`ProjectDescription` ，而非` PackageDescription 。
- **專案：** 您將匯出的是`專案` 實例，而非`套件` 實例。
- **Xcode 語言：** 您用來定義專案的原始語法模仿 Xcode 的語言，因此您會發現方案、目標、建置階段等元素。

接著建立名為 Tuist.swift 的檔案（位於`目錄下），內容如下：`

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift` 包含專案設定，其路徑將作為判定專案根目錄的參照依據。您可參閱
<LocalizedLink href="/guides/features/projects/directory-structure">目錄結構</LocalizedLink>文件以深入了解
Tuist 專案的架構。

## 編輯專案{#editing-the-project}

您可使用 <LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink> 在 Xcode 中編輯專案。此指令將生成可開啟並開始作業的 Xcode 專案。

```bash
tuist edit
```

根據專案規模，您可選擇一次性或分階段執行。建議從小型專案開始熟悉 DSL 與工作流程。我們的建議是：從最依賴的目標開始，逐步向上推演至頂層目標。
