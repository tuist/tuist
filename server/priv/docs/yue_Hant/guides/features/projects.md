---
{
  "title": "專案",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "以 Swift 描述 Xcode 專案，並透過 Tuist 一致地產生專案。消除合併衝突、將依賴關係建模為圖表，並解鎖模組快取。"
}
---
# 生成項目 {#generated-projects}

Tuist 生成項目係一個可行嘅替代方案，可以幫你克服呢啲挑戰，同時將複雜性同成本維持喺可接受水平。佢將 Xcode 項目視為基本元素，確保對未來 Xcode 更新嘅韌性，並利用 Xcode 項目生成功能，為團隊提供以模組化為重點嘅宣告式 API。Tuist 使用項目聲明簡化模組化嘅複雜性、優化跨各種環境嘅工作流程（例如編譯或測試），並促進同普及 Xcode 項目嘅演進。

## 點樣運作？ {#how-does-it-work}

要開始使用生成項目，你只需要使用 **Tuist 領域特定語言 (DSL)** 定義你嘅項目。這需要使用清單文件，例如 `Workspace.swift` 或 `Project.swift`。如果你之前用過 Swift Package Manager，方法非常相似。

一旦你定義咗項目，Tuist 就提供多種工作流程嚟管理同互動：

- **生成：** 這係一個基礎工作流程。用它來創建與 Xcode 兼容嘅 Xcode 項目。
- **<.localized_link href="/cli/build">編譯</.localized_link>：** 此工作流程不僅生成 Xcode 項目，還使用 `xcodebuild` 進行編譯。
- **<.localized_link href="/cli/test">測試</.localized_link>：** 操作方式類似編譯工作流程，不僅生成 Xcode 項目，還使用 `xcodebuild` 進行測試。

## Xcode 項目嘅挑戰 {#challenges-with-xcode-projects}

隨著 Xcode 項目增長，**組織可能會面臨生產力下降**，原因包括增量編譯不可靠、開發人員遇到問題時頻繁清除 Xcode 全局緩存，以及項目配置脆弱。為保持快速功能開發，組織通常會探索各種策略。

有些組織選擇通過使用基於 JavaScript 嘅動態運行時（例如 [React Native](https://reactnative.dev/)）抽象平台來繞過編譯器。雖然這種方法可能有效，但它 [令訪問平台原生功能變得複雜](https://shopify.engineering/building-app-clip-react-native)。其他組織選擇 **將代碼庫模組化**，這有助於建立清晰邊界，使代碼庫更易於處理並提高編譯時間嘅可靠性。然而，Xcode 項目格式並非為模組化而設計，會導致隱式配置，只有少數人理解且經常出現衝突。這導致巴士因子低，雖然增量編譯可能會改善，但當編譯失敗時，開發人員仍可能頻繁清除 Xcode 嘅編譯緩存（即 derived data）。為解決這個問題，有些組織選擇 **放棄 Xcode 嘅構建系統** 並採用替代品，例如 [Buck](https://buck.build/) 或 [Bazel](https://bazel.build/)。然而，這帶來 [高複雜性同維護負擔](https://bazel.build/migrate/xcode)。


## 替代方案 {#alternatives}

### Swift Package Manager {#swift-package-manager}

雖然 Swift Package Manager (SPM) 主要專注於依賴項，但 Tuist 提供另一種方法。使用 Tuist，你不只係為 SPM 集成定義包；你使用熟悉嘅概念（如項目、工作區、目標同方案）來塑造你嘅項目。

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) 係一個專用項目生成器，旨在減少協作 Xcode 項目中嘅衝突並簡化 Xcode 內部運作嘅一些複雜性。然而，項目使用可序列化格式（例如 [YAML](https://yaml.org/)）定義。與 Swift 不同，這不允許開發人員在不引入額外工具嘅情況下基於抽象或檢查進行構建。雖然 XcodeGen 確實提供一種將依賴項映射到內部表示以進行驗證同優化嘅方法，但它仍然使開發人員暴露於 Xcode 嘅細微差別。這可能使 XcodeGen 成為 [構建工具](https://github.com/MobileNativeFoundation/rules_xcodeproj) 嘅合適基礎，正如 Bazel 社區所見，但它對於旨在維持健康同高效環境嘅包容性項目演進並非最佳選擇。如果你今天使用 XcodeGen，[XcodeGen vs Tuist](https://tuist.dev/compare/xcodegen) 解釋咗哪些 Tuist 功能適用於你現有嘅 XcodeGen 項目；要遷移到 Tuist 生成項目，請參閱 <.localized_link href="/guides/features/projects/adoption/migrate/xcodegen-project">遷移指南</.localized_link>。

### Bazel {#bazel}

[Bazel](https://bazel.build) 係一個先進嘅構建系統，以其遠程緩存功能而聞名，主要因為此功能而在 Swift 社區中獲得歡迎。然而，鑑於 Xcode 及其構建系統嘅有限擴展性，用 Bazel 系統替換它需要大量努力同維護。只有少數資源豐富嘅公司能夠承擔這種開銷，從那些大力投資將 Bazel 與 Xcode 集成嘅公司名單中就可見一斑。有趣的是，社區創建咗一個 [工具](https://github.com/MobileNativeFoundation/rules_xcodeproj)，使用 Bazel 嘅 XcodeGen 來生成 Xcode 項目。這導致一個複雜嘅轉換鏈：從 Bazel 文件到 XcodeGen YAML，最後到 Xcode 項目。這種多層間接往往使故障排除變得複雜，令問題更難診斷同解決。
