---
{
  "title": "模組化架構（TMA）",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解模組化架構（TMA），以及如何運用它來組織你的專案。"
}
---
# 模組化架構（TMA）{#the-modular-architecture-tma}

TMA 是一種應用程式架構方法，旨在提升可擴展性、優化建置與測試週期，並確保團隊遵循良好實踐。其核心理念是透過建構獨立功能，並以清晰簡潔的 API 相互連接，來打造你的應用程式。

這些指引介紹了該架構的原則，協助你識別並將應用程式功能組織到不同層級。如果你決定採用此架構，它亦提供提示、工具與建議。

> [!NOTE]
> **Μfeatures**
>
> 此架構先前稱為 µFeatures。我們已將其更名為 The Modular Architecture（TMA），以更準確反映其目的與背後的原則。


## 核心原則 {#core-principle}

開發者應能**快速建置、測試及試用**其功能，無需依賴主應用程式，同時確保 Xcode 功能（如 UI 預覽、程式碼補全與偵錯）可靠運作。

## 什麼是模組 {#what-is-a-module}

模組代表一項應用程式功能，由以下五個 target 組成（此處 target 指 Xcode target）：

- **Source：** 包含功能的原始碼（Swift、Objective-C、C++、JavaScript...）及其資源（圖片、字型、storyboard、xib）。
- **Interface：** 這是配套 target，包含功能的公開介面與模型。
- **Tests：** 包含功能的單元測試與整合測試。
- **Testing：** 提供可用於測試與範例應用程式的測試資料。它亦提供模組類別與協定的 mock，供其他功能使用，稍後會進一步說明。
- **Example：** 包含一個範例應用程式，開發者可在特定條件下（不同語言、螢幕尺寸、設定）試用該功能。

我們建議為 target 遵循命名慣例，藉助 Tuist 的 DSL，你可以在專案中強制執行此規範。

| Target | Dependencies | Content |
| ---- | ---- | ---- |
| `Feature` | `FeatureInterface` | 原始碼與資源 |
| `FeatureInterface` | - | 公開介面與模型 |
| `FeatureTests` | `Feature`, `FeatureTesting` | 單元與整合測試 |
| `FeatureTesting` | `FeatureInterface` | 測試資料與 mock |
| `FeatureExample` | `FeatureTesting`, `Feature` | 範例應用程式 |

> [!TIP]
> **UI 預覽**
>
> `Feature`可以將`FeatureTesting`用作 Development Asset，以支援 UI 預覽


> [!WARNING]
> **使用編譯器指令而非 Testing Target**
>
> 或者，你可以在為`Debug`編譯時，使用編譯器指令將測試資料與 mock 納入`Feature`或`FeatureInterface`target。這會簡化依賴圖，但最終會編譯一些執行應用程式時不需要的程式碼。


## 為何需要模組 {#why-a-module}

### 清晰簡潔的 API {#clear-and-concise-apis}

當所有應用程式原始碼都放在同一個 target 時，很容易在程式碼中建立隱式依賴，最終導致眾所周知的「義大利麵式程式碼」。一切緊密耦合，狀態有時難以預測，引入新變更會變成噩夢。當我們在獨立 target 中定義功能時，必須在實作功能的過程中設計公開 API。我們需要決定哪些內容應公開、功能應如何被呼叫，以及哪些內容應保持私有。我們能更有效控制功能客戶如何使用該功能，並透過設計安全的 API 來強制執行良好實踐。

### 小型模組 {#small-modules}

[分而治之](https://en.wikipedia.org/wiki/Divide_and_conquer)。在小型模組中工作，讓你更能專注，並能隔離地測試與試用功能。此外，開發週期大幅加快，因為編譯更具選擇性，只編譯讓功能運作所需的元件。只有在工作的最後階段，當需要將功能整合到應用程式時，才需要編譯整個應用程式。

### 可重用性 {#reusability}

鼓勵使用 framework 或 library 在不同應用程式及其他產品（如 extension）之間重用程式碼。透過建構模組，重用變得相當直接。我們可以僅組合現有模組，並在 _必要時_ 加入平台專屬的 UI 層，來建構 iMessage extension、Today Extension 或 watchOS 應用程式。

## Dependencies {#dependencies}

當一個模組依賴另一個模組時，它會針對該模組的 interface target 宣告依賴。這樣做有雙重好處：防止一個模組的實作與另一個模組的實作耦合，並加速 clean build，因為只需編譯我們功能的實作，以及直接與間接依賴的介面。此方法靈感來自 SwiftRock 的[透過使用 Interface Modules 減少 iOS 建置時間](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets)概念。

依賴介面要求應用程式在執行時期建構實作圖，並將依賴注入到需要的模組中。雖然 TMA 對如何實現此事持中立態度，但我們建議使用不會增加建置時期間接性或使用非為此目的設計的平台 API 的依賴注入解決方案或模式。

## Product types {#product-types}

在建構模組時，你可以為 target 選擇**library 與 framework**，以及**靜態與動態連結**。沒有 Tuist 時，做出此決定較為複雜，因為你需要手動設定依賴圖。然而，得益於 Tuist Projects，這已不再是問題。

我們建議在開發期間使用動態 library 或 framework，並透過<.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">bundle accessors</.localized_link>將 bundle 存取邏輯與 target 的 library 或 framework 性質解耦。這對加快編譯速度及確保[SwiftUI Previews](https://developer.apple.com/documentation/swiftui/previews-in-xcode)可靠運作至關重要。對於 release build，則使用靜態 library 或 framework，以確保應用程式快速啟動。你可以利用<.localized_link href="/guides/features/projects/dynamic-configuration#configuration-through-environment-variables">dynamic configuration</.localized_link>在建置產生時期變更 product type：

```bash
# You'll have to read the value of the variable from the manifest {#youll-have-to-read-the-value-of-the-variable-from-the-manifest}
# and use it to change the linking type {#and-use-it-to-change-the-linking-type}
TUIST_PRODUCT_TYPE=static-library tuist generate
```

```swift
// You can place this in your manifest files or helpers
// and use the returned value when instantiating targets.
func productType() -> Product {
    if case let .string(productType) = Environment.productType {
        return productType == "static-library" ? .staticLibrary : .framework
    } else {
        return .framework
    }
}
```


> [!WARNING]
> **Mergeable Libraries**
>
> Apple 嘗試透過引入[mergeable libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)來減輕在靜態與動態 library 之間切換的繁瑣。然而，這會引入建置時期的非確定性，導致你的建置無法重現且更難優化，因此我們不建議使用。


## Code {#code}

TMA 對模組的程式碼架構與模式持中立態度。不過，我們想根據經驗分享一些提示：

- **善用編譯器是好事。** 過度依賴編譯器可能會適得其反，並導致某些 Xcode 功能（如 previews）運作不穩定。我們建議利用編譯器來強制執行良好實踐並及早捕捉錯誤，但不要過度到讓程式碼更難閱讀與維護。
- **謹慎使用 Swift Macros。** 它們功能強大，但也可能讓程式碼更難閱讀與維護。
- **擁抱平台與語言，不要將其抽象化。** 試圖設計複雜的抽象層可能會適得其反。平台與語言本身已足夠強大，無需額外抽象層即可建構出色的應用程式。以良好的程式設計與設計模式為參考來建構你的功能。


## Resources {#resources}

- [Building µFeatures](https://speakerdeck.com/pepibumur/building-ufeatures)
- [Framework Oriented Programming](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [A Journey into frameworks and Swift](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [Leveraging frameworks to speed up our development on iOS - Part 1](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [Library Oriented Programming](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [Building Modern Frameworks](https://developer.apple.com/videos/play/wwdc2014/416/)
- [The Unofficial Guide to xcconfig files](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [Static and Dynamic Libraries](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
