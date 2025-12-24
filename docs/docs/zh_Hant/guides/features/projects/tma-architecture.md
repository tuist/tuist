---
{
  "title": "The Modular Architecture (TMA)",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about The Modular Architecture (TMA) and how to structure your projects using it."
}
---
# 模組化架構 (TMA){#the-modular-architecture-tma}

TMA 是構建 Apple OS
應用程式的架構方法，可實現可擴展性、優化建立和測試週期，並確保您的團隊有良好的實踐。其核心理念是透過建立獨立的功能來建立您的應用程式，而這些功能則透過清晰簡潔的
API 相互連結。

這些指導方針介紹架構的原則，協助您識別和組織不同層級的應用程式功能。如果您決定使用此架構，它也會介紹提示、工具和建議。

::: info µFEATURES
<!-- -->
此架構之前稱為 µFeatures。我們將其重新命名為 The Modular Architecture (TMA)，以更好地反映其目的及其背後的原則。
<!-- -->
:::

## 核心原則{#core-principle}

開發人員應該能夠**，獨立於主應用程式，快速建立、測試並嘗試** 其功能，同時確保 UI 預覽、程式碼完成和除錯等 Xcode 功能可靠運作。

## 什麼是模組{#what-is-a-module}

模組代表應用程式功能，是下列五個目標的組合 (其中目標是指 Xcode 目標)：

- **來源：** 包含功能原始碼 (Swift、Objective-C、C++、JavaScript...) 及其資源
  (圖片、字型、storyboards、xibs)。
- **介面：** 它是一個伴隨目標，包含功能的公共介面和模型。
- **測試：** 包含功能單元與整合測試。
- **測試：** 提供可在測試和範例程式中使用的測試資料。它也提供模組類別和通訊協定的模組，這些模組可以被其他功能使用，我們稍後就會看到。
- **範例：** 包含一個範例應用程式，開發人員可使用該應用程式在特定條件（不同語言、螢幕尺寸、設定）下試用功能。

我們建議您遵循目標的命名慣例，由於 Tuist 的 DSL，您可以在專案中強制執行。

| 目標     | 依賴          | 內容      |
| ------ | ----------- | ------- |
| `特點`   | `功能介面`      | 原始碼與資源  |
| `功能介面` | -           | 公共介面與模型 |
| `功能測試` | `功能`,`功能測試` | 單元與整合測試 |
| `功能測試` | `功能介面`      | 測試資料和模擬 |
| `功能範例` | `功能測試`,`功能` | 應用範例    |

::: tip UI Previews
<!-- -->
`功能` 可以使用`FeatureTesting` 作為開發資產，以允許 UI 預覽
<!-- -->
:::

::: warning COMPILER DIRECTIVES INSTEAD OF TESTING TARGETS
<!-- -->
另外，您也可以在編譯`Debug` 時，使用編譯器指令在`Feature` 或`FeatureInterface`
目標中包含測試資料和模組。您可以簡化圖形，但最終您會編譯出執行應用程式時不需要的程式碼。
<!-- -->
:::

## 為什麼需要模組{#why-a-module}

### 清晰簡潔的 API{#clear-and-concise-apis}

當所有的應用程式原始碼都存放在相同的目標中時，很容易在程式碼中建立隱含的依賴關係，結果就是眾所皆知的意大利麵條程式碼。所有東西都是強連結的、狀態有時是不可預測的，而且引進新的變更會變成一場惡夢。當我們在獨立目標中定義功能時，我們需要設計公共
API
作為功能實作的一部分。我們需要決定什麼應該是公開的，我們的功能應該如何被使用，什麼應該保持私有。我們對於希望功能客戶端如何使用功能有更多的控制權，而且我們可以透過設計安全的
API 來強制執行良好的實作。

### 小型模組{#small-modules}

[分而治之](https://en.wikipedia.org/wiki/Divide_and_conquer)。以小模組的方式工作，可以讓您更專注，並獨立測試和嘗試功能。此外，由於我們的編譯更具選擇性，只編譯功能運作所需的元件，因此開發週期更快。只有在工作最後，需要將功能整合到應用程式時，才需要編譯整個應用程式。

### 重複使用性{#reusability}

我們鼓勵您使用框架或函式庫，在應用程式和其他產品（例如擴充套件）之間重複使用程式碼。透過建立模組來重複使用是相當直接的。我們只要結合現有的模組，並加入_(必要時)_
平台特定的 UI 層，就能建立 iMessage 延伸、Today 延伸或 watchOS 應用程式。

## 依賴{#dependencies}

當一個模組依賴於另一個模組時，它會宣告對其介面目標的依賴。這樣做有兩方面的好處。它可以防止一個模組的實作與另一個模組的實作耦合，而且可以加快簡潔的建置速度，因為他們只需要編譯我們功能的實作，以及直接和反式依賴的介面。這個方法的靈感來自
SwiftRock [Reducing iOS Build Times by Using Interface
Modules](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets)
的想法。

依賴介面需要應用程式在執行時建立實作圖形，並依賴注入到需要的模組中。雖然 TMA
對於如何做到這一點不持主見，但我們建議使用依賴注入解決方案或模式，或是不增加建置時間間接或使用非為此目的而設計的平台 API 的解決方案。

## 產品類型{#product-types}

在建立模組時，您可以選擇**函式庫和框架** ，以及**靜態和動態連結** 作為目標。如果沒有
Tuist，做出這個決定會比較複雜，因為您需要手動設定相依圖。不過，有了 Tuist Projects，這不再是問題。

我們建議在開發過程中使用動態函式庫或框架，使用
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">bundle accessors</LocalizedLink> 來將 bundle 存取邏輯與目標函式庫或框架的性質分離。這是快速編譯和確保 [SwiftUI
預覽](https://developer.apple.com/documentation/swiftui/previews-in-xcode)可靠運作的關鍵。而釋出版本建置的靜態函式庫或框架，則可確保應用程式快速啟動。您可以利用
<LocalizedLink href="/guides/features/projects/dynamic-configuration#configuration-through-environment-variables"> 動態配置</LocalizedLink>，在產生時變更產品類型：

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


::: warning MERGEABLE LIBRARIES
<!-- -->
Apple 嘗試透過引入 [mergeable
libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)
來減輕在靜態與動態函式庫之間切換的麻煩。然而，這會引進建立時的非決定性，使得您的建立不可重複，而且更難優化，因此我們不建議使用。
<!-- -->
:::

## 代碼{#code}

TMA 對於您模組的程式碼架構和模式不持任何意見。不過，我們想根據我們的經驗分享一些提示：

- **利用編譯器是非常好的。** 過度使用編譯器可能會導致無益的結果，並導致某些 Xcode 功能 (例如預覽)
  無法可靠地運作。我們建議使用編譯器來強制執行良好的實務並及早捕捉錯誤，但不要過度使用編譯器而導致程式碼更難閱讀和維護。
- **少用 Swift 巨集。** 它們可以非常強大，但也會讓程式碼更難閱讀和維護。
- **擁抱平台和語言，不要將它們抽象化。**
  試著想出更多的抽象層，結果可能會適得其反。平台和語言已經足夠強大到不需要額外的抽象層就能建立很棒的應用程式。使用良好的程式設計與設計模式作為建立功能的參考。

## 資源{#resources}

- [Building µFeatures](https://speakerdeck.com/pepibumur/building-ufeatures)
- [Framework Oriented
  Programming](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [A Journey into frameworks and
  Swift](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [利用框架加快我們在 iOS 上的開發速度 -
  第一部分](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)。
- [Library Oriented
  Programming](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [建立現代框架](https://developer.apple.com/videos/play/wwdc2014/416/)
- [xcconfig 檔案非官方指南](https://pewpewthespells.com/blog/xcconfig_guide.html)。
- [靜態與動態函式庫](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
