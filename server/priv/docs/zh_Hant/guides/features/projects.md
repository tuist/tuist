---
{
  "title": "專案",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "以 Swift 描述 Xcode 專案，並透過 Tuist 一致地產生專案。消除合併衝突、將相依性建模為圖形，並解鎖模組快取。"
}
---
# 產生的專案 {#generated-projects}

Tuist 產生的專案是可行的替代方案，能協助克服這些挑戰，同時將複雜度與成本維持在可接受的水準。它將 Xcode 專案視為核心元素，確保面對未來 Xcode 更新時的韌性，並透過產生 Xcode 專案，為團隊提供以模組化為核心的宣告式 API。Tuist 利用專案定義簡化模組化的複雜性、最佳化跨環境的建置或測試等工作流程，並促進且普及 Xcode 專案的演進。

## 運作方式？ {#how-does-it-work}

要開始使用產生的專案，你只需使用 **Tuist 的領域特定語言 (DSL)** 定義專案。這需要使用如 `Workspace.swift` 或 `Project.swift` 等清單檔案。如果你曾經使用過 Swift Package Manager，做法非常相似。

定義專案後，Tuist 提供多種工作流程來管理與互動：

- **產生：** 這是基礎工作流程。使用它來建立與 Xcode 相容的 Xcode 專案。
- **<.localized_link href="/cli/build">建置</.localized_link>：** 此工作流程不僅會產生 Xcode 專案，還會使用 `xcodebuild` 進行編譯。
- **<.localized_link href="/cli/test">測試</.localized_link>：** 運作方式與建置工作流程類似，不僅會產生 Xcode 專案，還會使用 `xcodebuild` 進行測試。

## Xcode 專案的挑戰 {#challenges-with-xcode-projects}

隨著 Xcode 專案規模擴大，**組織可能會面臨生產力下降**，原因包括不可靠的增量建置、開發者在遇到問題時經常清除 Xcode 的全域快取，以及脆弱的專案設定。為了維持快速的功能開發，組織通常會探索各種策略。

有些組織選擇透過 JavaScript 基礎的動態執行期（例如 [React Native](https://reactnative.dev/)）抽象化平台來繞過編譯器。雖然這種方法可能有效，但會 [讓存取平台的原生功能變得複雜](https://shopify.engineering/building-app-clip-react-native)。其他組織則選擇 **將程式碼庫模組化**，這有助於建立明確的界限，讓程式碼庫更易於維護，並提升建置時間的可靠性。然而，Xcode 專案格式並非為模組化設計，會導致隱含的設定，很少有人理解且經常發生衝突。這會造成關鍵人員依賴風險；雖然增量建置可能改善，但當建置失敗時，開發者仍可能經常清除 Xcode 的建置快取（即 derived data）。為了解決這個問題，有些組織選擇 **放棄 Xcode 的建置系統**，並採用如 [Buck](https://buck.build/) 或 [Bazel](https://bazel.build/) 等替代方案。但這會帶來 [高度的複雜性與維護負擔](https://bazel.build/migrate/xcode)。


## 替代方案 {#alternatives}

### Swift Package Manager {#swift-package-manager}

雖然 Swift Package Manager (SPM) 主要專注於相依性，但 Tuist 提供不同的做法。使用 Tuist 時，你不只是為 SPM 整合定義套件；你還可以使用熟悉的觀念（如專案、工作區、目標與配置）來塑造你的專案。

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) 是專用的專案產生器，旨在減少協作型 Xcode 專案中的衝突，並簡化 Xcode 內部運作的一些複雜性。然而，專案是使用如 [YAML](https://yaml.org/) 等可序列化格式定義。與 Swift 不同，這不允許開發者在不引入額外工具的情況下基於抽象或檢查進行建構。雖然 XcodeGen 確實提供將相依性對應至內部表示法以進行驗證與最佳化的方式，但它仍讓開發者暴露於 Xcode 的細微差異中。這可能使 XcodeGen 成為 [建構工具](https://github.com/MobileNativeFoundation/rules_xcodeproj) 的合適基礎，如同 Bazel 社群所見，但它對於旨在維持健康且具生產力環境的包容性專案演進並非最佳選擇。如果你目前使用 XcodeGen，[XcodeGen 與 Tuist 比較](https://tuist.dev/compare/xcodegen) 說明了哪些 Tuist 功能可與你現有的 XcodeGen 專案搭配使用；若要遷移至 Tuist 產生的專案，請參閱 <.localized_link href="/guides/features/projects/adoption/migrate/xcodegen-project">遷移指南</.localized_link>。

### Bazel {#bazel}

[Bazel](https://bazel.build) 是一套先進的建置系統，以其遠端快取功能聞名，並在 Swift 社群中主要因這項能力而受到歡迎。然而，鑑於 Xcode 及其建置系統的可擴充性有限，將其替換為 Bazel 的系統需要大量的努力與維護。只有少數資源充足的公司能夠承擔這項額外負擔，從那些投入大量資源將 Bazel 與 Xcode 整合的公司名單即可看出。有趣的是，社群建立了一個 [工具](https://github.com/MobileNativeFoundation/rules_xcodeproj)，使用 Bazel 的 XcodeGen 來產生 Xcode 專案。這導致一連串複雜的轉換：從 Bazel 檔案到 XcodeGen YAML，最後再到 Xcode 專案。這種多層間的接往往會讓除錯變得複雜，使問題更難診斷與解決。
