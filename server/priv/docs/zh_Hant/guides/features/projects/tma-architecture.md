---
{
  "title": "模組化架構 (TMA)",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解模組化架構 (TMA)，以及如何運用它來規劃你的專案結構。"
}
---
# 模組化架構 (TMA) {#the-modular-architecture-tma}

TMA 是一種架構方法，用於規劃應用程式結構以實現可擴展性、最佳化建置與測試週期，並確保團隊遵循良好實踐。其核心理念是透過建置獨立的模組功能，並使用清晰簡潔的 API 將它們相互連接，來構建你的應用程式。

這些指南介紹了該架構的原則，幫助你識別並將應用程式功能組織到不同的層級中。如果你決定採用此架構，它還提供了相關提示、工具和建議。

> [!NOTE]
> **Μfeatures**
>
> 此架構先前稱為 µFeatures。我們已將其重新命名為「模組化架構 (TMA)」，以更準確地反映其目的及背後的原則。


## 核心原則 {#core-principle}

開發人員應能夠快速**建置、測試和試用**其功能，且獨立於主應用程式之外，同時確保 Xcode 的功能（如 UI 預覽、程式碼補全和除錯）能可靠運作。

## 什麼是模組 {#what-is-a-module}

模組代表一個應用程式功能，由以下五個 Target（此處指 Xcode Target）組合而成：

- **Source：** 包含功能的原始碼（Swift、Objective-C、C++、JavaScript...）及其資源（圖片、字型、Storyboard、XIB）。
- **Interface：** 這是一個輔助 Target，包含功能的公開介面和模型。
- **Tests：** 包含功能的單元測試和整合測試。
- **Testing：** 提供可用於測試和範例應用程式的測試資料。它還提供模組類別和協定的 Mock 物件，供其他功能使用，後續我們將進一步說明。
- **Example：** 包含一個範例應用程式，開發人員可用於在特定條件下（不同語言、螢幕尺寸、設定）試用該功能。

我們建議遵循 Target 的命名慣例，藉助 Tuist 的 DSL，你可以在專案中強制執行此規範。

| Target | 相依性 | 內容 |
| ---- | ---- | ---- |
| `Feature` | `FeatureInterface` | 原始碼和資源 |
| `FeatureInterface` | - | 公開介面和模型 |
| `FeatureTests` | `Feature`, `FeatureTesting` | 單元和整合測試 |
| `FeatureTesting` | `FeatureInterface` | 測試資料和 Mock 物件 |
| `FeatureExample` | `FeatureTesting`, `Feature` | 範例應用程式 |

> [!TIP]
> **UI 預覽**
>
> `Feature` 可以將 `FeatureTesting` 用作開發資產，以啟用 UI 預覽


> [!WARNING]
> **使用編譯器指令代替測試 Target**
>
> 或者，你可以在為 `Debug` 編譯時，使用編譯器指令將測試資料和 Mock 物件包含在 `Feature` 或 `FeatureInterface` Target 中。這會簡化依賴圖，但最終你會編譯一些執行應用程式時不需要的程式碼。


## 為什麼需要模組 {#why-a-module}

### 清晰簡潔的 API {#clear-and-concise-apis}

當所有應用程式原始碼都位於同一個 Target 中時，很容易在程式碼中建立隱式相依性，最終導致眾所周知的「義大利麵式程式碼」。一切緊密耦合，狀態有時不可預測，引入新變更成為一場噩夢。當我們在獨立的 Target 中定義功能時，我們需要將設計公開 API 作為功能實作的一部分。我們需要決定哪些內容應該公開、如何消費我們的功能、哪些內容應該保持私有。我們可以更好地控制功能使用者如何使用該功能，並透過設計安全的 API 來強制執行良好實踐。

### 小型模組 {#small-modules}

[分而治之](https://en.wikipedia.org/wiki/Divide_and_conquer)。在小型模組中工作讓你更能專注，並能隔離測試和試用功能。此外，開發週期更快，因為我們進行更具選擇性的編譯，僅編譯讓功能運作所需的元件。只有在工作的最後階段，當我們需要將功能整合到應用程式中時，才需要編譯整個應用程式。

### 可重用性 {#reusability}

鼓勵使用 Framework 或 Library 在應用程式和其他產品（如擴充功能）之間重用程式碼。透過建置模組，重用它們相當直接。我們可以僅透過組合現有模組並添加 _（必要時）_ 平台特定的 UI 層，來建置 iMessage 擴充功能、Today Extension 或 watchOS 應用程式。

## 相依性 {#dependencies}

當一個模組依賴另一個模組時，它會針對其介面 Target 聲明相依性。這樣做有雙重好處。它防止一個模組的實作與另一個模組的實作耦合，並加速乾淨建置，因為只需編譯我們功能的實作，以及直接和傳遞相依性的介面。這種方法靈感來自 SwiftRock 的想法：[使用介面模組減少 iOS 建置時間](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets)。

依賴介面要求應用程式在執行時期建置實作圖，並將其依賴注入到需要的模組中。雖然 TMA 對如何執行此操作沒有強制規定，但我們建議使用不會增加建置時間間接性或使用非為此目的設計的平台 API 的依賴注入解決方案或模式。

## 產品類型 {#product-types}

在建置模組時，你可以為 Target 選擇**Library 和 Framework**，以及**靜態和動態連結**。沒有 Tuist 的情況下，做出此決定較為複雜，因為你需要手動設定依賴圖。然而，得益於 Tuist Projects，這不再是一個問題。

我們建議在開發期間使用動態 Library 或 Framework，並利用<.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">Bundle Accessors</.localized_link>將 Bundle 存取邏輯與 Target 的 Library 或 Framework 性質解耦。這對加快編譯時間和確保[SwiftUI 預覽](https://developer.apple.com/documentation/swiftui/previews-in-xcode)可靠運作至關重要。對於發布建置，則使用靜態 Library 或 Framework 以確保應用程式快速啟動。你可以利用<.localized_link href="/guides/features/projects/dynamic-configuration#configuration-through-environment-variables">動態設定</.localized_link>在產生時期變更產品類型：

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
> **可合併 Library**
>
> Apple 嘗試透過引入[可合併 Library](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)來減輕在靜態和動態 Library 之間切換的繁瑣。然而，這會引入建置時期的非確定性，導致你的建置無法重現且更難最佳化，因此我們不建議使用。


## 程式碼 {#code}

TMA 對於模組的程式碼架構和模式沒有強制規定。不過，我們希望根據我們的經驗分享一些提示：

- **善用編譯器是很好的。** 過度依賴編譯器可能會降低生產力，並導致某些 Xcode 功能（如預覽）運作不穩定。我們建議使用編譯器來強制執行良好實踐並及早發現錯誤，但不要達到讓程式碼更難閱讀和維護的程度。
- **謹慎使用 Swift Macro。** 它們非常強大，但也可能讓程式碼更難閱讀和維護。
- **擁抱平台和語言，不要對其進行抽象。** 試圖設計複雜的抽象層可能會適得其反。平台和語言本身已經足夠強大，無需額外的抽象層就能建置出色的應用程式。參考良好的程式設計和設計模式來建置你的功能。


## 資源 {#resources}

- [建置 µFeatures](https://speakerdeck.com/pepibumur/building-ufeatures)
- [Framework 導向程式設計](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [深入 Framework 和 Swift 之旅](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [利用 Framework 加速 iOS 開發 - 第 1 部分](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [Library 導向程式設計](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [建置現代 Framework](https://developer.apple.com/videos/play/wwdc2014/416/)
- [xcconfig 檔案非官方指南](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [靜態和動態 Library](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
