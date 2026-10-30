---
{
  "title": "專案",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "以 Swift 描述 Xcode 專案，並透過 Tuist 一致地產生專案。消除合併衝突、將依賴關係建模為圖表，並解鎖模組快取。"
}
---
# 生成專案 {#generated-projects}

Tuist 生成專案係一個可行嘅替代方案，幫你克服呢啲挑戰，同時將複雜度同成本維持喺可接受水平。佢將 Xcode 專案視為基本元素，確保對未來 Xcode 更新嘅韌性，並利用 Xcode 專案生成功能，為團隊提供以模組化為重點嘅宣告式 API。Tuist 使用專案定義來簡化模組化嘅複雜性，優化跨各種環境嘅工作流程（例如建置或測試），並促進同普及 Xcode 專案嘅演進。

## 點樣運作？ {#how-does-it-work}

要開始使用生成專案，你只需要使用 **Tuist 領域特定語言 (DSL)** 定義你嘅專案。這需要使用清單檔案，例如 `Workspace.swift` 或 `Project.swift`。如果你之前用過 Swift Package Manager，方法好相似。

一旦你定義咗專案，Tuist 就提供多種工作流程來管理同互動：

- **生成：** 呢個係基礎工作流程。用佢來建立與 Xcode 兼容嘅 Xcode 專案。
- **<.localized_link href="/cli/build">建置</.localized_link>：** 呢個工作流程唔單止生成 Xcode 專案，仲會使用 `xcodebuild` 來編譯佢。
- **<.localized_link href="/cli/test">測試</.localized_link>：** 運作方式同建置工作流程類似，唔單止生成 Xcode 專案，仲會使用 `xcodebuild` 來測試佢。

## Xcode 專案嘅挑戰 {#challenges-with-xcode-projects}

隨著 Xcode 專案增長，**組織可能會面臨生產力下降**，原因包括不可靠嘅增量建置、開發人員遇到問題時頻繁清除 Xcode 全域快取，以及脆弱嘅專案配置。為了保持快速嘅功能開發，組織通常會探索各種策略。

有啲組織選擇透過使用基於 JavaScript 嘅動態運行時（例如 [React Native](https://reactnative.dev/)）抽象化平台來繞過編譯器。雖然呢種方法可能有效，但佢 [令存取平台原生功能變得複雜](https://shopify.engineering/building-app-clip-react-native)。其他組織則選擇 **將程式碼庫模組化**，這有助於建立清晰嘅界限，使程式碼庫更易於處理並提高建置時間嘅可靠性。然而，Xcode 專案格式並非為模組化而設計，會導致隱式配置，好少人理解且經常發生衝突。這導致巴士因子偏低，雖然增量建置可能會改善，但當建置失敗時，開發人員仍然可能頻繁清除 Xcode 嘅建置快取（即衍生數據）。為咗解決呢個問題，有啲組織選擇 **放棄 Xcode 嘅建置系統** 並採用替代方案，例如 [Buck](https://buck.build/) 或 [Bazel](https://bazel.build/)。然而，這帶來 [高複雜度同維護負擔](https://bazel.build/migrate/xcode)。


## 替代方案 {#alternatives}

### Swift Package Manager {#swift-package-manager}

雖然 Swift Package Manager (SPM) 主要專注於依賴項，但 Tuist 提供咗一種不同嘅方法。使用 Tuist，你唔單止為 SPM 整合定義套件；你仲可以使用熟悉嘅概念（例如專案、工作區、目標同方案）來塑造你嘅專案。

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) 係一個專用嘅專案生成器，旨在減少協作 Xcode 專案中嘅衝突並簡化 Xcode 內部運作嘅一啲複雜性。然而，專案係使用可序列化格式（例如 [YAML](https://yaml.org/)）定義嘅。與 Swift 不同，這不允許開發人員在不引入額外工具嘅情況下基於抽象或檢查進行構建。雖然 XcodeGen 確實提供咗一種將依賴項映射到內部表示以進行驗證同優化嘅方法，但它仍然讓開發人員面對 Xcode 嘅細微差別。這可能使 XcodeGen 成為 [構建工具](https://github.com/MobileNativeFoundation/rules_xcodeproj) 嘅合適基礎（正如 Bazel 社區所見），但它對於旨在維持健康同高效環境嘅包容性專案演進來說並非最佳選擇。

### Bazel {#bazel}

[Bazel](https://bazel.build) 係一個先進嘅建置系統，以其遠端快取功能而聞名，並主要因呢項功能而喺 Swift 社區中獲得人氣。然而，鑑於 Xcode 及其建置系統嘅有限擴展性，用 Bazel 系統取代佢需要大量努力同維護。只有少數資源豐富嘅公司能夠承擔呢種開銷，從少數大力投資將 Bazel 與 Xcode 整合嘅公司名單就可以睇出。有趣嘅係，社區創建咗一個 [工具](https://github.com/MobileNativeFoundation/rules_xcodeproj)，使用 Bazel 嘅 XcodeGen 來生成 Xcode 專案。這導致咗一連串複雜嘅轉換：從 Bazel 檔案到 XcodeGen YAML，最後到 Xcode 專案。呢種多層間接性通常會使故障排除變得複雜，令問題更難診斷同解決。
