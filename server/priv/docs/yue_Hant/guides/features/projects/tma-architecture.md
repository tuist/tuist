---
{
  "title": "模組化架構（TMA）",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解模組化架構（TMA），以及如何使用它來組織你的專案。"
}
---
# 模組化架構（TMA）{#the-modular-architecture-tma}

TMA 係一種應用架構方法，用嚟組織應用程式結構，以支援擴展、優化建置同測試週期，並確保團隊採用良好實踐。其核心理念係透過建置獨立功能，並使用清晰簡潔嘅 API 將佢哋互連，從而構建你嘅應用程式。

呢份指南介紹咗該架構嘅原則，幫你識別並將應用程式功能組織到唔同層次。如果你決定採用呢種架構，佢亦提供咗提示、工具同建議。

> [!NOTE]
> **µFeatures**
>
> 呢種架構以前叫做 µFeatures。我哋將佢改名為 The Modular Architecture（TMA），以更準確反映其目的同背後原則。


## 核心原則{#core-principle}

開發人員應該能夠**快速建置、測試同試用**佢哋嘅功能，無需依賴主應用程式，同時確保 Xcode 功能（例如 UI 預覽、程式碼補全同除錯）可靠運作。

## 乜嘢係模組{#what-is-a-module}

一個模組代表一個應用程式功能，由以下五個 target 組成（target 指 Xcode target）：

- **Source：** 包含功能原始碼（Swift、Objective-C、C++、JavaScript...）同資源（圖片、字型、storyboard、xib）。
- **Interface：** 係一個配套 target，包含功能嘅公開介面同模型。
- **Tests：** 包含功能嘅單元測試同整合測試。
- **Testing：** 提供可用於測試同示例應用程式嘅測試數據。佢亦提供模組類別同協議嘅 mock，其他功能可以像稍後所示那樣使用佢哋。
- **Example：** 包含一個示例應用程式，開發人員可以用喺特定條件下（唔同語言、螢幕尺寸、設定）試用該功能。

我哋建議遵循 target 嘅命名慣例，你可以藉助 Tuist 嘅 DSL 喺專案中強制執行呢一點。

| Target | 依賴項 | 內容 |
| ---- | ---- | ---- |
| `Feature` | `FeatureInterface` | 原始碼同資源 |
| `FeatureInterface` | - | 公開介面同模型 |
| `FeatureTests` | `Feature`, `FeatureTesting` | 單元測試同整合測試 |
| `FeatureTesting` | `FeatureInterface` | 測試數據同 mock |
| `FeatureExample` | `FeatureTesting`, `Feature` | 示例應用程式 |

> [!TIP]
> **UI 預覽**
>
> `Feature`可以將`FeatureTesting`用作 Development Asset，以啟用 UI 預覽


> [!WARNING]
> **使用編譯器指令代替測試 target**
>
> 或者，你可以使用編譯器指令，喺為`Debug`編譯時將測試數據同 mock 包含喺`Feature`或`FeatureInterface` target 中。雖然簡化咗依賴圖，但最終會編譯一啲運行應用程式時不需要嘅程式碼。


## 點解要用模組{#why-a-module}

### 清晰簡潔嘅 API{#clear-and-concise-apis}

當所有應用程式原始碼都放喺同一個 target 入面，好容易喺程式碼中建立隱式依賴，最終導致所謂嘅「意大利麵式程式碼」。所有嘢都緊密耦合，狀態有時難以預測，引入新變更變成一場噩夢。當我哋喺獨立 target 中定義功能時，需要將公開 API 設計作為功能實現嘅一部分。我哋需要決定乜嘢應該公開、點樣消費我哋嘅功能、乜嘢應該保持私有。我哋可以更好控制功能客戶點樣使用功能，並透過設計安全嘅 API 來強制執行良好實踐。

### 小型模組{#small-modules}

[分而治之](https://en.wikipedia.org/wiki/Divide_and_conquer)。喺小型模組中工作令你更專注，並可以孤立地測試同試用功能。此外，開發週期更快，因為我哋進行更有選擇性嘅編譯，只編譯令功能運作所需嘅組件。只有喺工作最後階段，當需要將功能整合到應用程式中時，才需要編譯整個應用程式。

### 可重用性{#reusability}

鼓勵使用 framework 或 library 喺唔同應用程式同其他產品（例如 extension）之間重用程式碼。透過建置模組，重用佢哋相當直接。我哋可以只係組合現有模組並 _（必要時）_ 添加平台專屬 UI 層，來構建 iMessage extension、Today Extension 或 watchOS 應用程式。

## 依賴項{#dependencies}

當一個模組依賴另一個模組時，佢會聲明對其 interface target 嘅依賴。呢種做法有雙重好處。佢防止一個模組嘅實現與另一個模組嘅實現耦合，並加速 clean build，因為只需編譯我哋功能嘅實現，以及直接同傳遞依賴項嘅介面。呢種方法靈感來自 SwiftRock 嘅[透過使用 Interface Modules 減少 iOS 建置時間](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets)理念。

依賴介面要求應用程式喺運行時構建實現圖，並將其依賴注入到需要佢嘅模組中。雖然 TMA 對點樣做呢件事冇特定立場，但我哋建議使用唔會增加建置時間間接性或使用並非為此目的設計嘅平台 API 嘅依賴注入解決方案或模式。

## 產品類型{#product-types}

建置模組時，你可以為 target 選擇**library 同 framework**，以及**靜態連結同動態連結**。如果唔使用 Tuist，做呢個決定會複雜啲，因為你需要手動配置依賴圖。不過，多得 Tuist Projects，呢個已經唔再係問題。

我哋建議喺開發期間使用動態 library 或 framework，並使用<.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">bundle accessor</.localized_link>將 bundle 訪問邏輯與 target 係 library 定 framework 嘅性質解耦。呢點對於快速編譯時間同確保[SwiftUI Previews](https://developer.apple.com/documentation/swiftui/previews-in-xcode)可靠運作至關重要。而對於 release build，則使用靜態 library 或 framework 以確保應用程式快速啟動。你可以利用<.localized_link href="/guides/features/projects/dynamic-configuration#configuration-through-environment-variables">動態配置</.localized_link>喺生成時更改產品類型：

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
> Apple 嘗試透過引入[可合併 library](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)來減輕喺靜態同動態 library 之間切換嘅繁瑣。不過，呢種做法會引入建置時間嘅非確定性，導致你嘅建置無法重現並難以優化，所以我哋唔建議使用。


## 程式碼 {#code}

TMA 對你模組嘅程式碼架構同模式冇特定立場。不過，我哋想根據經驗分享一啲提示：

- **善用編譯器係好事。** 過度依賴編譯器可能會適得其反，並導致預覽等 Xcode 功能運作不穩定。我哋建議使用編譯器來強制執行良好實踐並及早捕捉錯誤，但唔好令到程式碼難以閱讀同維護。
- **謹慎使用 Swift Macro。** 佢哋功能強大，但亦可能令程式碼難以閱讀同維護。
- **擁抱平台同語言，唔好抽象化佢哋。** 試圖構建複雜嘅抽象層可能會適得其反。平台同語言本身已經足夠強大，無需額外抽象層就能構建出色嘅應用程式。參考良好嘅程式設計同設計模式來構建你嘅功能。


## 資源 {#resources}

- [構建 µFeatures](https://speakerdeck.com/pepibumur/building-ufeatures)
- [Framework 導向程式設計](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [探索 framework 同 Swift 之旅](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [利用 framework 加速 iOS 開發 - 第 1 部分](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [Library 導向程式設計](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [構建現代 Framework](https://developer.apple.com/videos/play/wwdc2014/416/)
- [xcconfig 檔案非官方指南](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [靜態同動態 Library](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
