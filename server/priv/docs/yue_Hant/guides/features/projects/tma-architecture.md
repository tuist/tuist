---
{
  "title": "模組化架構 (TMA)",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解模組化架構 (TMA) 以及如何使用它來組織你的專案。"
}
---
# 模組化架構（TMA）{#the-modular-architecture-tma}

TMA 是一種應用程式架構方法，旨在提升可擴展性、優化建置與測試週期，並確保團隊遵循良好實踐。其核心理念是透過建構獨立的功能模組，並以清晰簡潔的 API 將它們相互連接，從而構建你的應用程式。

這些指引介紹了該架構的原則，幫助你識別並將應用程式功能組織到不同層級。如果你決定採用此架構，這裡亦提供了相關提示、工具與建議。

> [!NOTE]
> **µFeatures**
>
> 此架構先前稱為 µFeatures。我們已將其重新命名為 The Modular Architecture (TMA)，以更準確反映其目的及背後的原則。


## 核心原則 {#core-principle}

開發者應能夠**快速建置、測試和試用**他們的功能，無需依賴主應用程式，同時確保 Xcode 功能（如 UI 預覽、程式碼補全和除錯）可靠運作。

## 什麼是模組 {#what-is-a-module}

模組代表一個應用程式功能，由以下五個 target（此處指 Xcode target）組合而成：

- **Source：** 包含功能的原始碼（Swift、Objective-C、C++、JavaScript...）及其資源（圖片、字型、Storyboard、xib）。
- **Interface：** 這是一個配套 target，包含功能的公開介面與模型。
- **Tests：** 包含功能的單元測試與整合測試。
- **Testing：** 提供可用於測試和範例應用程式的測試資料。它還提供模組類別與協定的 mock，供其他功能使用，稍後我們會詳細說明。
- **Example：** 包含一個範例應用程式，開發者可用於在特定條件下（不同語言、螢幕尺寸、設定）試用該功能。

我們建議為 target 遵循命名慣例，藉助 Tuist 的 DSL，你可以在專案中強制執行此規範。

| Target | 相依性 | 內容 |
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
> **使用編譯器指令而非測試 target**
>
> 或者，你可以在為`Debug`編譯時，使用編譯器指令將測試資料和 mock 包含在`Feature`或`FeatureInterface`target 中。這會簡化相依圖，但最終你會編譯一些運行應用程式時不需要的程式碼。


## 為何需要模組 {#why-a-module}

### 清晰簡潔的 API {#clear-and-concise-apis}

當所有應用程式原始碼都位於同一個 target 時，很容易在程式碼中建立隱式相依性，最終導致眾所周知的「義大利麵式程式碼」。所有內容緊密耦合，狀態有時難以預測，引入新變更成為噩夢。當我們在獨立 target 中定義功能時，我們需要作為功能實作的一部分來設計公開 API。我們需要決定哪些內容應公開、如何消費我們的功能、哪些內容應保持私有。我們可以更有效控制功能客戶如何使用該功能，並透過設計安全的 API 來強制執行良好實踐。

### 小型模組 {#small-modules}

[分而治之](https://en.wikipedia.org/wiki/Divide_and_conquer)。在小型模組中工作讓你更專注，並能隔離測試和試用功能。此外，開發週期更快，因為我們進行更具選擇性的編譯，只編譯使功能運作所需的元件。只有在工作的最後階段，當我们需要將功能整合到應用程式中時，才需要編譯整個應用程式。

### 可重用性 {#reusability}

鼓勵使用 framework 或 library 在不同應用程式及其他產品（如擴充功能）之間重用程式碼。透過建構模組，重用它們相當直接。我們可以僅透過組合現有模組並添加 _（必要時）_ 平台專屬的 UI 層，來建構 iMessage 擴充功能、Today Extension 或 watchOS 應用程式。

## 相依性 {#dependencies}

當一個模組依賴另一個模組時，它會針對其介面 target 聲明相依性。這樣做有雙重好處。它防止一個模組的實作與另一個模組的實作耦合，並加速乾淨建置，因為只需編譯我們功能的實作，以及直接和傳遞相依性的介面。此方法靈感來自 SwiftRock 的想法：[透過使用介面模組減少 iOS 建置時間](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets)。

依賴介面要求應用程式在運行時建構實作圖，並將其依賴注入到需要的模組中。雖然 TMA 對如何實現這一點沒有強制規定，但我們建議使用不會增加建置時間間接性或使用非為此目的設計的平台 API 的依賴注入解決方案或模式。

## 產品類型 {#product-types}

在建構模組時，你可以為 target 選擇**library 與 framework**，以及**靜態與動態連結**。沒有 Tuist 時，做出此決定較為複雜，因為你需要手動設定相依圖。然而，得益於 Tuist Projects，這不再是一個問題。

我們建議在開發期間使用動態 library 或 framework，並利用<.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">bundle accessor</.localized_link>將 bundle 存取邏輯與 target 的 library 或 framework 性質解耦。這對加快編譯時間和確保[SwiftUI Previews](https://developer.apple.com/documentation/swiftui/previews-in-xcode)可靠運作至關重要。對於發布建置，則使用靜態 library 或 framework 以確保應用程式快速啟動。你可以利用<.localized_link href="/guides/features/projects/dynamic-configuration#configuration-through-environment-variables">動態設定</.localized_link>在產生時期變更產品類型：

```bash
# You'll have to read the value of the variable from the manifest
# and use it to change the linking type
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
> **可合併 library**
>
> Apple 嘗試透過引入[可合併 library](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)來減輕在靜態與動態 library 之間切換的繁瑣。然而，這會引入建置時期的非確定性，導致你的建置無法重現且更難優化，因此我們不建議使用。


## 程式碼 {#code}

TMA 對模組的程式碼架構和模式沒有強制規定。不過，我們想根據經驗分享一些提示：

- **善用編譯器是好事。** 過度依賴編譯器可能會降低生產力，並導致某些 Xcode 功能（如預覽）運作不穩定。我們建議使用編譯器來強制執行良好實踐並及早發現錯誤，但不要過度到讓程式碼更難閱讀和維護。
- **謹慎使用 Swift Macros。** 它們功能強大，但也可能讓程式碼更難閱讀和維護。
- **擁抱平台和語言，不要抽象化它們。** 試圖設計複雜的抽象層可能會適得其反。平台和語言本身已足夠強大，無需額外抽象層即可建構出色的應用程式。參考良好的程式設計和設計模式來建構你的功能。


## 資源 {#resources}

- [建構 µFeatures](https://speakerdeck.com/pepibumur/building-ufeatures)
- [Framework 導向程式設計](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [深入 framework 與 Swift 之旅](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [利用 framework 加速 iOS 開發 - 第一部分](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [Library 導向程式設計](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [建構現代 Framework](https://developer.apple.com/videos/play/wwdc2014/416/)
- [xcconfig 檔案非官方指南](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [靜態與動態 Library](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
