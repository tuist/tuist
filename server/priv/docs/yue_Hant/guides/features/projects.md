---
{
  "title": "專案",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "以 Swift 描述 Xcode 專案，並使用 Tuist 一致地產生它們。消除合併衝突、將依賴關係建模為圖表，並解鎖模組快取。"
}
---
# 生成嘅專案 {#generated-projects}

Tuist 生成嘅專案係一個可行嘅替代方案，可以幫你克服呢啲挑戰，同時將複雜度同成本維持喺可接受嘅水平。佢將 Xcode 專案視為基本元素，確保對未來 Xcode 更新嘅韌性，並利用 Xcode 專案生成功能，為團隊提供以模組化為重點嘅宣告式 API。Tuist 使用專案定義來簡化模組化嘅複雜性，優化跨各種環境嘅工作流程（例如編譯或測試），並促進同普及 Xcode 專案嘅演進。

## 點樣運作？ {#how-does-it-work}

要開始使用生成嘅專案，你只需要使用 **Tuist 嘅領域特定語言 (DSL)** 來定義你嘅專案。這意味著要使用如 `Workspace.swift` 或 `Project.swift` 等清單檔案。如果你之前用過 Swift Package Manager，做法好相似。

一旦你定義咗專案，Tuist 就提供多種工作流程來管理同互動：

- **生成：** 這是一個基礎工作流程。用它來建立一個與 Xcode 兼容嘅 Xcode 專案。
- **<.localized_link href="/cli/build">編譯</.localized_link>：** 此工作流程不僅會生成 Xcode 專案，還會使用 `xcodebuild` 來編譯它。
- **<.localized_link href="/cli/test">測試</.localized_link>：** 運作方式類似編譯工作流程，此功能不僅會生成 Xcode 專案，還會利用 `xcodebuild` 來測試它。

## Xcode 專案面臨嘅挑戰 {#challenges-with-xcode-projects}

隨著 Xcode 專案增長，**組織可能會面臨生產力下降**，原因包括增量編譯不可靠、開發人員遇到問題時頻繁清除 Xcode 的全域快取，以及脆弱的專案配置。為了保持快速的功能開發，組織通常會探索各種策略。

有些組織選擇透過使用基於 JavaScript 的動態運行時（例如 [React Native](https://reactnative.dev/)）抽象化平台來繞過編譯器。雖然這種方法可能有效，但它 [令存取平台的原生功能變得複雜](https://shopify.engineering/building-app-clip-react-native)。其他組織則選擇 **將代碼庫模組化**，這有助於建立清晰的邊界，使代碼庫更易於處理並提高編譯時間的可靠性。然而，Xcode 專案格式並非為模組化而設計，會導致隱式配置，只有少數人理解且經常發生衝突。這導致巴士因子較差，雖然增量編譯可能會改善，但當編譯失敗時，開發人員仍可能頻繁清除 Xcode 的編譯快取（即衍生數據）。為了解決這個問題，一些組織選擇 **放棄 Xcode 的編譯系統** 並採用如 [Buck](https://buck.build/) 或 [Bazel](https://bazel.build/) 等替代方案。然而，這帶來了 [高複雜度同維護負擔](https://bazel.build/migrate/xcode)。


## 替代方案 {#alternatives}

### Swift Package Manager {#swift-package-manager}

雖然 Swift Package Manager (SPM) 主要專注於依賴項，但 Tuist 提供了不同的方法。使用 Tuist，你不只是為 SPM 集成定義包；你還可以使用熟悉的觀念（如專案、工作區、目標同方案）來塑造你的專案。

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) 是一個專門的專案生成器，旨在減少協作 Xcode 專案中的衝突並簡化 Xcode 內部運作的一些複雜性。然而，專案是使用如 [YAML](https://yaml.org/) 等可序列化格式定義的。與 Swift 不同，這不允許開發人員在不引入額外工具的情況下基於抽象或檢查進行構建。雖然 XcodeGen 確實提供了一種將依賴項映射到內部表示以進行驗證和優化的方法，但它仍然讓開發人員暴露於 Xcode 的細微差別中。這可能使 XcodeGen 成為 [構建工具](https://github.com/MobileNativeFoundation/rules_xcodeproj) 的合適基礎，正如在 Bazel 社區中所見，但它對於旨在維持健康和富有成效環境的包容性專案演進來說並非最佳選擇。

### Bazel {#bazel}

[Bazel](https://bazel.build) 是一個先進的編譯系統，以其遠程快取功能而聞名，主要在 Swift 社區中因這項能力而受到歡迎。然而，鑑於 Xcode 及其編譯系統的有限可擴展性，用 Bazel 的系統替換它需要大量的努力和維護。只有少數資源豐富的公司能夠承擔這種開銷，從那些大力投資將 Bazel 與 Xcode 集成的公司名單中可見一斑。有趣的是，社區創建了一個 [工具](https://github.com/MobileNativeFoundation/rules_xcodeproj)，該工具使用 Bazel 的 XcodeGen 來生成 Xcode 專案。這導致了一個複雜的轉換鏈：從 Bazel 文件到 XcodeGen YAML，最後到 Xcode 專案。這種多層次的間接性往往會使故障排除變得複雜，令問題更難診斷和解決。
