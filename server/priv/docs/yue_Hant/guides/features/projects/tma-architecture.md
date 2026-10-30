---
{
  "title": "模組化架構（TMA）",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "了解模組化架構（TMA），以及如何運用它來規劃你的專案結構。"
}
---
# 模組化架構 (TMA) {#the-modular-architecture-tma}

TMA 係一種應用程式架構方法，旨在提升可擴展性、優化編譯同測試週期，並確保團隊遵循良好實踐。其核心理念係透過構建獨立功能，並使用清晰簡潔嘅 API 將佢哋互聯，從而開發你嘅應用程式。

呢份指南介紹咗該架構嘅原則，幫你識別並將應用程式功能組織到唔同層級。如果你決定採用呢種架構，佢亦提供咗提示、工具同建議。

> [!NOTE]
> **Μfeatures**
>
> 呢個架構以前稱為 µFeatures。我哋將佢重新命名為 The Modular Architecture (TMA)，以更好反映其目的同背後原則。


## 核心原則 {#core-principle}

開發人員應該能夠快速**構建、測試同試用**佢哋嘅功能，獨立於主應用程式之外，同時確保 Xcode 功能（例如 UI 預覽、代碼補全同除錯）可靠運作。

## 乜嘢係模組 {#what-is-a-module}

模組代表一個應用程式功能，由以下五個 target 組成（其中 target 指 Xcode target）：

- **Source：** 包含功能源代碼（Swift、Objective-C、C++、JavaScript...）及其資源（圖片、字體、storyboards、xibs）。
- **Interface：** 佢係一個配套 target，包含功能嘅公開介面同模型。
- **Tests：** 包含功能嘅單元測試同集成測試。
- **Testing：** 提供可用於測試同示例應用程式嘅測試數據。佢亦為模組類同協議提供 mock，其他功能稍後可以使用佢哋。
- **Example：** 包含一個示例應用程式，開發人員可以用佢喺特定條件下（唔同語言、屏幕尺寸、設置）試用該功能。

我哋建議對 target 遵循命名規範，藉助 Tuist 嘅 DSL，你可以喺項目中強制執行呢一點。

| Target | 依賴項 | 內容 |
| ---- | ---- | ---- |
| `Feature` | `FeatureInterface` | 源代碼同資源 |
| `FeatureInterface` | - | 公開介面同模型 |
| `FeatureTests` | `Feature`, `FeatureTesting` | 單元同集成測試 |
| `FeatureTesting` | `FeatureInterface` | 測試數據同 mock |
| `FeatureExample` | `FeatureTesting`, `Feature` | 示例應用程式 |

> [!TIP]
> **UI 預覽**
>
> `Feature`可以將`FeatureTesting`用作開發資源，以啟用 UI 預覽


> [!WARNING]
> **使用編譯器指令代替 Testing Target**
>
> 或者，你可以使用編譯器指令，喺為`Debug`編譯時將測試數據同 mock 包含喺`Feature`或`FeatureInterface` target 中。雖然簡化咗依賴圖，但最終你會編譯一啲運行應用程式時唔需要嘅代碼。


## 點解要使用模組 {#why-a-module}

### 清晰簡潔嘅 API {#clear-and-concise-apis}

當所有應用程式源代碼都放喺同一個 target 時，好容易喺代碼中建立隱式依賴，最終導致所謂嘅「 spaghetti code 」。一切緊密耦合，狀態有時難以預測，引入新變更變成噩夢。當我哋喺獨立 target 中定義功能時，需要作為功能實現嘅一部分設計公開 API。我哋需要決定乜嘢應該公開、點樣消費我哋嘅功能、乜嘢應該保持私有。我哋對功能客戶如何使用功能有更多控制權，並可以透過設計安全嘅 API 來強制執行良好實踐。

### 小型模組 {#small-modules}

[分而治之](https://en.wikipedia.org/wiki/Divide_and_conquer)。喺小型模組中工作可以讓你有更多專注力，並孤立地測試同試用功能。此外，開發週期更快，因為我哋進行更具選擇性嘅編譯，只編譯使功能運作所需嘅組件。只有喺工作最後階段，當我需要將功能集成到應用程式中時，才需要編譯整個應用程式。

### 可重用性 {#reusability}

鼓勵使用框架或庫喺應用程式同其他產品（例如擴展）之間重用代碼。透過構建模組，重用佢哋非常直接。我哋可以通過組合現有模組並添加 _（必要時）_ 平台特定嘅 UI 層，來構建 iMessage 擴展、Today Extension 或 watchOS 應用程式。

## 依賴項 {#dependencies}

當一個模組依賴另一個模組時，佢會聲明對其介面 target 嘅依賴。呢樣好處有兩方面。佢防止一個模組嘅實現與另一個模組嘅實現耦合，並加速乾淨編譯，因為佢哋只需要編譯我哋功能嘅實現，以及直接同傳遞依賴項嘅介面。呢種方法受到 SwiftRock [透過使用介面模組減少 iOS 編譯時間](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets)想法嘅啟發。

依賴介面要求應用程式喺運行時構建實現圖，並將其依賴注入到需要佢嘅模組中。雖然 TMA 對如何做到呢一點冇特定意見，但我哋建議使用依賴注入解決方案或模式，避免增加編譯時間間接性或使用並非為此目的設計嘅平台 API。

## 產品類型 {#product-types}

構建模組時，你可以為 target 選擇**庫同框架**，以及**靜態同動態鏈接**。冇 Tuist 嘅話，做出呢個決定會複雜少少，因為你需要手動配置依賴圖。不過，多謝 Tuist Projects，這不再係問題。

我哋建議喺開發期間使用動態庫或框架，並使用<.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">bundle accessors</.localized_link>將 bundle 訪問邏輯與 target 嘅庫或框架性質解耦。這對快速編譯時間至關重要，並確保[SwiftUI Previews](https://developer.apple.com/documentation/swiftui/previews-in-xcode)可靠運作。對於發布版本，使用靜態庫或框架以確保應用程式快速啟動。你可以利用<.localized_link href="/guides/features/projects/dynamic-configuration#configuration-through-environment-variables">dynamic configuration</.localized_link>喺生成時更改產品類型：

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
> **可合併庫**
>
> Apple 嘗試透過引入[可合併庫](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)來減輕喺靜態同動態庫之間切換嘅繁瑣。不過，這會引入編譯時間嘅非確定性，令你嘅編譯不可重現且難以優化，所以我哋唔建議使用。


## 代碼 {#code}

TMA 對你模組嘅代碼架構同模式冇特定意見。不過，我哋想根據經驗分享一啲提示：

- **善用編譯器係好事。** 過度依賴編譯器可能會適得其反，並導致預覽等 Xcode 功能運作不穩定。我哋建議使用編譯器來強制執行良好實踐並及早發現錯誤，但唔好令到代碼難以閱讀同維護。
- **謹慎使用 Swift Macros。** 佢哋可以非常強大，但亦可能令代碼難以閱讀同維護。
- **擁抱平台同語言，唔好抽象化佢哋。** 試圖構建複雜嘅抽象層可能會適得其反。平台同語言已經足夠強大，可以構建出色嘅應用程式，無需額外嘅抽象層。參考良好嘅編程同設計模式來構建你嘅功能。


## 資源 {#resources}

- [構建 µFeatures](https://speakerdeck.com/pepibumur/building-ufeatures)
- [面向框架編程](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [探索框架同 Swift 之旅](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [利用框架加速 iOS 開發 - 第一部分](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [面向庫編程](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [構建現代框架](https://developer.apple.com/videos/play/wwdc2014/416/)
- [xcconfig 文件非官方指南](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [靜態同動態庫](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
