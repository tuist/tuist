---
{
  "title": "專案",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "以 Swift 描述 Xcode 專案，並透過 Tuist 一致地產生專案。消除合併衝突、將相依性建模為圖形，並解鎖模組快取。"
}
---
# 產生的專案 {#generated-projects}

Tuist 產生的專案是可行的替代方案，能協助克服這些挑戰，同時將複雜度與成本維持在可接受的水準。它將 Xcode 專案視為基本要素，確保面對未來 Xcode 更新時的韌性，並透過產生 Xcode 專案，為團隊提供以模組化為核心的宣告式 API。Tuist 使用專案宣告來簡化模組化的複雜性、最佳化跨各種環境的建置或測試等工作流程，並促進且普及 Xcode 專案的演進。

## 運作方式？ {#how-does-it-work}

要開始使用產生的專案，你只需使用 **Tuist 的領域特定語言 (DSL)** 來定義專案。這意味著使用如 `Workspace.swift` 或 `Project.swift` 等清單檔案。如果你曾使用過 Swift Package Manager，其做法非常相似。

定義好專案後，Tuist 提供多種工作流程來管理與互動：

- **產生：** 這是基礎工作流程。使用它來建立與 Xcode 相容的 Xcode 專案。
- **<.localized_link href="/cli/build">建置</.localized_link>：** 此工作流程不僅會產生 Xcode 專案，還會使用 `xcodebuild` 進行編譯。
- **<.localized_link href="/cli/test">測試</.localized_link>：** 運作方式與建置工作流程類似，不僅會產生 Xcode 專案，還會使用 `xcodebuild` 進行測試。

## Xcode 專案的挑戰 {#challenges-with-xcode-projects}

隨著 Xcode 專案規模擴大，**組織可能會面臨生產力下降**，原因包括增量建置不穩定、開發者在遇到問題時經常清除 Xcode 的全域快取，以及專案設定脆弱。為了維持快速的功能開發，組織通常會探索各種策略。

有些組織選擇透過使用基於 JavaScript 的動態執行時期（例如 [React Native](https://reactnative.dev/)）來抽象化平台，從而繞過編譯器。雖然這種方法可能有效，但會 [讓存取平台的原生功能變得複雜](https://shopify.engineering/building-app-clip-react-native)。其他組織則選擇 **將程式碼庫模組化**，這有助於建立明確的界限，讓程式碼庫更易於處理，並提升建置時間的可靠性。然而，Xcode 專案格式並非為模組化而設計，會導致隱含的設定（很少有人理解）以及頻繁的衝突。這會造成不良的巴士係數，而且雖然增量建置可能會改善，但當建置失敗時，開發者仍可能經常清除 Xcode 的建置快取（即衍生資料）。為了解決這個問題，有些組織選擇 **放棄 Xcode 的建置系統**，並採用如 [Buck](https://buck.build/) 或 [Bazel](https://bazel.build/) 等替代方案。然而，這會帶來 [高度的複雜性與維護負擔](https://bazel.build/migrate/xcode)。


## 替代方案 {#alternatives}

### Swift Package Manager {#swift-package-manager}

雖然 Swift Package Manager (SPM) 主要專注於相依性，但 Tuist 提供了不同的做法。使用 Tuist 時，你不只是為 SPM 整合定義套件；你還可以使用熟悉的概念（如專案、工作區、目標與方案）來塑造你的專案。

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) 是專用的專案產生器，旨在減少協作型 Xcode 專案中的衝突，並簡化 Xcode 內部運作的一些複雜性。然而，專案是使用可序列化的格式（如 [YAML](https://yaml.org/)）來定義。與 Swift 不同，這不允許開發者在不加入額外工具的情況下，建立在抽象層或檢查之上。雖然 XcodeGen 確實提供了一種將相依性對應到內部表示法以進行驗證與最佳化的方法，但它仍然讓開發者暴露於 Xcode 的細微差異中。這可能使 XcodeGen 成為 [建構工具](https://github.com/MobileNativeFoundation/rules_xcodeproj) 的合適基礎（如 Bazel 社群所見），但對於旨在維持健康且高效環境的包容性專案演進而言，並非最佳選擇。

### Bazel {#bazel}

[Bazel](https://bazel.build) 是一套先進的建置系統，以其遠端快取功能聞名，並在 Swift 社群中主要因這項能力而受到歡迎。然而，鑑於 Xcode 及其建置系統的可擴充性有限，以 Bazel 的系統取代它需要大量的努力與維護。只有少數資源豐富的企業能夠承擔這項額外負擔，從投入大量資源將 Bazel 與 Xcode 整合的精選企業名單即可看出。有趣的是，社群建立了一個 [工具](https://github.com/MobileNativeFoundation/rules_xcodeproj)，使用 Bazel 的 XcodeGen 來產生 Xcode 專案。這導致了一連串複雜的轉換：從 Bazel 檔案到 XcodeGen YAML，最後再到 Xcode 專案。這種多層的間接性往往會讓除錯變得複雜，使問題更難診斷與解決。
