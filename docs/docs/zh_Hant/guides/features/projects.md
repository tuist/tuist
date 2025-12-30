---
{
  "title": "Projects",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn about Tuist's DSL for defining Xcode projects."
}
---
# 產生的專案{#generated-projects}

Generated 是一種可行的替代方案，它有助於克服這些挑戰，同時將複雜性和成本保持在可接受的水平。它將 Xcode 專案視為基本元素，確保對未來 Xcode
更新的彈性，並利用 Xcode 專案產生功能，為團隊提供以模組化為重點的宣告式 API。Tuist
使用專案宣告來簡化模組化的複雜性**、優化跨不同環境的建置或測試等工作流程，並促進 Xcode 專案的演進與民主化。

## 如何運作？{#how-does-it-work}

要開始使用產生的專案，您只需要使用**Tuist 的特定領域語言 (DSL)** 定義專案。這需要使用清單檔案，例如`Workspace.swift`
或`Project.swift` 。如果您之前使用過 Swift Package Manager，方法就非常類似。

定義專案後，Tuist 提供各種工作流程來管理專案並與之互動：

- **生成：** 這是一個基礎工作流程。使用它來建立與 Xcode 相容的 Xcode 專案。
- **<LocalizedLink href="/guides/features/build">Build</LocalizedLink>：**
  此工作流程不僅會產生 Xcode 專案，也會運用`xcodebuild` 來編譯它。
- **<LocalizedLink href="/guides/features/test">Test</LocalizedLink>：**
  操作方式與建立工作流程很相似，這不僅會產生 Xcode 專案，還會利用`xcodebuild` 來測試它。

## Xcode 專案的挑戰{#challenges-with-xcode-projects}

隨著 Xcode 專案的成長，**組織可能會因為幾個因素而面臨生產力下降的問題** ，這些因素包括不可靠的增量建置、開發人員遇到問題時頻繁清除 Xcode
的全域快取記憶體，以及脆弱的專案配置。為了維持快速的功能開發，組織通常會探索各種策略。

有些組織選擇繞過編譯器，使用基於 JavaScript 的動態執行時來抽象平台，例如 [React
Native](https://reactnative.dev/)。雖然這種方法可能有效，但卻
[使存取平台原生功能變得複雜](https://shopify.engineering/building-app-clip-react-native)。其他組織則選擇**模組化程式碼庫**
，這有助於建立明確的邊界，使程式碼庫更容易操作，並提高建立時間的可靠性。然而，Xcode
專案格式並非專為模組化而設計，其結果是幾乎無法理解的隱含組態以及頻繁的衝突。這會導致總線因素不佳，雖然增量建置可能會有所改善，但開發人員仍可能會在建置失敗時，頻繁清除
Xcode 的建置快取記憶體 (即衍生資料)。為了解決這個問題，有些組織選擇**放棄 Xcode 的建立系統** ，並採用
[Buck](https://buck.build/) 或 [Bazel](https://bazel.build/) 等替代方案。然而，這樣做會帶來
[高複雜性和維護負擔](https://bazel.build/migrate/xcode)。


## 替代方案{#alternatives}

### Swift 套件管理員{#swift-package-manager}

Swift Package Manager (SPM) 主要著重於相依性，而 Tuist 則提供不同的方法。有了 Tuist，您不只是定義 SPM
整合的套件；您還可以使用熟悉的專案、工作區、目標和方案等概念來塑造您的專案。

### XcodeGen{#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) 是一個專用的專案產生器，旨在減少協作式 Xcode
專案中的衝突，並簡化 Xcode 內部運作的一些複雜性。但是，專案是使用 [YAML](https://yaml.org/) 之類的序列化格式定義的。與
Swift 不同的是，這不允許開發人員在不結合額外工具的情況下建立抽象或檢查。雖然 XcodeGen
確實提供了一種方式，可將依賴關係映射到內部表示，以進行驗證和最佳化，但它仍會讓開發人員暴露於 Xcode 的細微差異中。這可能會讓 XcodeGen 成為
[建立工具](https://github.com/MobileNativeFoundation/rules_xcodeproj)（如 Bazel
社群所見）的合適基礎，但對於以維持健康且具生產力的環境為目標的包容性專案演進而言，這並非最佳選擇。

### Bazel{#bazel}

[Bazel](https://bazel.build) 是一個先進的建立系統，以其遠端快取功能而聞名，在 Swift 社群中也很受歡迎。然而，鑑於 Xcode
及其建置系統的擴充能力有限，以 Bazel 的系統取代 Xcode
需要大量的努力與維護。只有少數資源豐富的公司才能負擔得起這筆開銷，這從精選的公司名單中可以看出，這些公司都投入大量資金將 Bazel 與 Xcode
整合在一起。有趣的是，社群創造了一個
[工具](https://github.com/MobileNativeFoundation/rules_xcodeproj)，採用 Bazel 的
XcodeGen 來產生 Xcode 專案。這導致了一連串複雜的轉換：從 Bazel 檔案到 XcodeGen YAML，最後再到 Xcode
專案。這樣的分層間接通常會使故障排除變得複雜，使問題的診斷和解決更具挑戰性。
