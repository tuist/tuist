---
{
  "title": "專案",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "以 Swift 描述 Xcode 專案，並透過 Tuist 一致性地產生專案。消除合併衝突、將相依性建模為圖形，並啟用模組快取。"
}
---
# 生成的專案 {#generated-projects}

Tuist 生成的專案是一項可行的替代方案，有助於克服這些挑戰，同時將複雜度與成本維持在可接受的水準。它將 Xcode 專案視為基本要素，確保能應對未來的 Xcode 更新，並透過生成 Xcode 專案，為團隊提供以模組化為核心的宣告式 API。Tuist 使用專案定義來簡化模組化的複雜性、最佳化跨各種環境的建置或測試等工作流程，並促進且普及 Xcode 專案的演進。

## 運作方式？ {#how-does-it-work}

要開始使用生成的專案，你只需使用 **Tuist 的領域特定語言 (DSL)** 來定義你的專案。這需要使用如 `Workspace.swift` 或 `Project.swift` 等清單檔案。如果你曾經使用過 Swift Package Manager，這種做法非常類似。

一旦你定義了專案，Tuist 就提供多種工作流程來管理並與之互動：

- **Generate：** 這是基礎工作流程。使用它來建立與 Xcode 相容的 Xcode 專案。
- **<.localized_link href="/cli/build">Build</.localized_link>：** 此工作流程不僅會生成 Xcode 專案，還會使用 `xcodebuild` 來編譯它。
- **<.localized_link href="/cli/test">Test</.localized_link>：** 其運作方式與建置工作流程非常類似，不僅會生成 Xcode 專案，還會利用 `xcodebuild` 來測試它。

## Xcode 專案的挑戰 {#challenges-with-xcode-projects}

隨著 Xcode 專案規模擴大，**組織可能會面臨生產力下降**的情況，原因包括不可靠的增量建置、開發人員遇到問題時經常清除 Xcode 的全域快取，以及脆弱的專案設定。為了維持快速的特性開發，組織通常會探索各種策略。

有些組織選擇透過使用基於 JavaScript 的動態執行階段（例如 [React Native](https://reactnative.dev/)）抽象化平台來繞過編譯器。雖然這種方法可能有效，但它[讓存取平台的原生功能變得更加複雜](https://shopify.engineering/building-app-clip-react-native)。其他組織則選擇**將程式碼庫模組化**，這有助於建立明確的界限，使程式碼庫更易於處理，並提升建置時間的可靠性。然而，Xcode 專案格式並非為模組化而設計，會導致隱含的設定，很少有人理解且經常發生衝突。這會導致不良的巴士係數，而且雖然增量建置可能會改善，但當建置失敗時，開發人員仍可能經常清除 Xcode 的建置快取（即衍生資料）。為了解決這個問題，有些組織選擇**放棄 Xcode 的建置系統**，並採用像 [Buck](https://buck.build/) 或 [Bazel](https://bazel.build/) 等替代方案。然而，這伴隨著[高度的複雜性與維護負擔](https://bazel.build/migrate/xcode)。


## 替代方案 {#alternatives}

### Swift Package Manager {#swift-package-manager}

雖然 Swift Package Manager (SPM) 主要著重於相依性，但 Tuist 提供了不同的方法。使用 Tuist 時，你不只是為 SPM 整合定義套件；你會使用熟悉的概念（如專案、工作區、目標和方案）來塑造你的專案。

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) 是一個專用的專案生成器，旨在減少協作式 Xcode 專案中的衝突，並簡化 Xcode 內部運作的一些複雜性。然而，專案是使用可序列化的格式（如 [YAML](https://yaml.org/)）來定義。與 Swift 不同，這不允許開發人員在不加入額外工具的情況下，基於抽象化或檢查進行建構。雖然 XcodeGen 確實提供了一種將相依性對應到內部表示法以進行驗證和最佳化的方法，但它仍然讓開發人員暴露在 Xcode 的細微差異中。這可能使 XcodeGen 成為[建構工具](https://github.com/MobileNativeFoundation/rules_xcodeproj)的合適基礎，正如 Bazel 社群所見，但它對於旨在維持健康且具生產力環境的包容性專案演進來說並非最佳選擇。如果你目前使用 XcodeGen，[XcodeGen vs Tuist](https://tuist.dev/compare/xcodegen) 說明了哪些 Tuist 功能可與你現有的 XcodeGen 專案搭配使用；若要遷移至 Tuist 生成的專案，請參閱<.localized_link href="/guides/features/projects/adoption/migrate/xcodegen-project">遷移指南</.localized_link>。

### Bazel {#bazel}

[Bazel](https://bazel.build) 是一套先進的建置系統，以其遠端快取功能聞名，並在 Swift 社群中主要因這項能力而日益普及。然而，鑑於 Xcode 及其建置系統的可擴充性有限，將其替換為 Bazel 的系統需要大量的努力與維護。只有少數資源豐富的企業能夠承擔這種額外負擔，從那些投入大量資源將 Bazel 與 Xcode 整合的公司名單即可看出。有趣的是，社群建立了一個[工具](https://github.com/MobileNativeFoundation/rules_xcodeproj)，該工具使用 Bazel 的 XcodeGen 來生成 Xcode 專案。這導致了一連串複雜的轉換：從 Bazel 檔案到 XcodeGen YAML，最後再到 Xcode 專案。這種層層的間接性往往會讓疑難排解變得複雜，使問題更難以診斷和解決。
