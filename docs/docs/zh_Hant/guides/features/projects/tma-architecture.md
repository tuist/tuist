---
{
  "title": "The Modular Architecture (TMA)",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about The Modular Architecture (TMA) and how to structure your projects using it."
}
---
# 模組化架構（TMA）{#the-modular-architecture-tma}

TMA 是一種架構方法，用於建構 Apple
作業系統應用程式，以實現可擴展性、優化建置與測試週期，並確保團隊遵循良好實務。其核心理念是透過建構獨立功能來開發應用程式，這些功能透過清晰簡潔的 API
相互連結。

這些準則闡述架構設計原則，協助您辨識並將應用程式功能分層組織。若您決定採用此架構，文中亦提供實用技巧、工具與建議。

::: info µFEATURES
<!-- -->
此架構先前稱為μFeatures。我們將其更名為模組化架構（TMA），以更貼切地反映其宗旨與背後的設計原則。
<!-- -->
:::

## 核心原則{#core-principle}

**** 開發人員應能快速建立、測試及嘗試其功能，且能獨立於主應用程式運作，同時確保 Xcode 功能（如 UI 預覽、程式碼完成及除錯）運作可靠。

## 何謂模組{#what-is-a-module}

模組代表應用程式功能，由以下五個目標組合而成（此處目標指Xcode目標）：

- **來源：** 包含功能原始碼（Swift、Objective-C、C++、JavaScript...）及其資源（圖片、字型、故事板、xib檔案）。
- **介面：** 此為配套目標，包含功能的公開介面與模型。
- **測試：** 包含功能單元測試與整合測試。
- **測試：** 提供可用於測試及範例應用程式的測試資料。同時也為模組類別與協定提供模擬物件，後續將說明其如何供其他功能使用。
- **範例：** 內含示範應用程式，開發人員可藉此在特定條件下（不同語言、螢幕尺寸、設定）測試此功能。

我們建議遵循目標名稱的命名規範，您可透過 Tuist 的 DSL 在專案中強制執行此規範。

| 目標     | 依賴          | 內容        |
| ------ | ----------- | --------- |
| `功能`   | `功能介面`      | 原始碼與資源    |
| `功能介面` | -           | 公開介面與模型   |
| `功能測試` | `功能測試：` 、`` | 單元測試與整合測試 |
| `功能測試` | `功能介面`      | 測試資料與模擬資料 |
| `功能範例` | `功能測試`,`功能` | 範例應用程式    |

::: tip UI Previews
<!-- -->
`功能測試（FeatureTesting）` 可使用`FeatureTesting` 作為開發資產，以實現 UI 預覽功能
<!-- -->
:::

::: warning COMPILER DIRECTIVES INSTEAD OF TESTING TARGETS
<!-- -->
另可透過編譯指令在以下目標中包含測試資料與模擬物件：`功能目標` 或`功能介面目標` 編譯時選用`調試模式`
此舉雖能簡化圖形結構，但最終編譯的程式碼將包含應用程式執行時無需的內容。
<!-- -->
:::

## 為何需要模組{#why-a-module}

### 清晰簡潔的 API{#clear-and-concise-apis}

當所有應用程式原始碼存放於同一目標時，極易在程式碼中形成隱性依賴關係，最終演變成眾所周知的義大利麵程式碼。此時所有元件高度耦合，狀態有時難以預測，任何新增變更都將成為噩夢。當我們在獨立目標中定義功能時，必須將公開
API 設計納入功能實作環節。 我們必須決定哪些應公開、功能應如何被使用、哪些應保持私有。如此既能掌控功能客戶端的使用方式，亦可透過設計安全的 API
來強制執行良好實務。

### 小型模組{#small-modules}

[分而治之](https://en.wikipedia.org/wiki/Divide_and_conquer)。採用小模組化開發能提升專注力，並在獨立環境中測試功能。此外，由於採用選擇性編譯機制（僅編譯實現功能所需的元件），開發週期大幅縮短。僅在工作尾聲需將功能整合至應用程式時，才需進行完整應用程式的編譯。

### 可重複使用性{#reusability}

鼓勵透過框架或函式庫在應用程式與擴充功能等產品間重複使用程式碼。藉由建構模組，重複使用便相當直觀。我們只需整合現有模組，並視需要添加平台專屬的 UI
層（例如：`_`、`_ `），即可開發 iMessage 擴充功能、今日擴充功能或 watchOS 應用程式。

## 依賴項{#dependencies}

當模組依賴其他模組時，需針對其介面目標宣告依賴關係。此做法具雙重效益：既能避免模組實作與其他模組實作產生耦合，亦可加速乾淨建置流程——因僅需編譯本功能之實作，以及直接與傳遞性依賴的介面。此方法靈感源自
SwiftRock 的構想：[透過介面模組縮短 iOS
建置時間](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets)。

依賴介面機制要求應用程式在執行時建立實作圖，並將其依賴注入至需要該功能的模組。儘管 TMA
對具體實現方式不作規定，我們建議採用依賴注入解決方案或模式，避免在編譯時增加間接層次，亦不應使用非為此目的設計的平台 API。

## 產品類型{#product-types}

建立模組時，可針對目標選擇以下選項：**函式庫與框架** ，以及**靜態與動態連結** 。若未使用
Tuist，此決策過程較為複雜，因需手動配置依賴關係圖。然而透過 Tuist Projects，此問題已迎刃而解。

開發期間建議使用動態庫或框架，透過
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">束狀存取器</LocalizedLink>
將束狀存取邏輯與目標庫/框架的本質解耦。此舉對實現快速編譯時間及確保 [SwiftUI
預覽功能](https://developer.apple.com/documentation/swiftui/previews-in-xcode)
穩定運作至關重要。正式發布版本則應採用靜態庫或框架，以確保應用程式啟動迅速。
您可運用<LocalizedLink href="/guides/features/projects/dynamic-configuration#configuration-through-environment-variables">動態配置</LocalizedLink>在生成時變更產品類型：

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
Apple 試圖透過引入
[可合併函式庫](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)
來減輕在靜態與動態函式庫間切換的繁瑣性。然而此舉會引入建置時間的不確定性，導致建置過程無法重現且更難優化，因此我們不建議使用此機制。
<!-- -->
:::

## 程式碼{#code}

TMA 對模組的程式架構與模式不作強制規範。然而，我們仍願分享基於實務經驗的建議：

- **善用編譯器是好事。** 過度依賴編譯器可能導致效率低下，並使預覽等 Xcode
  功能運作不穩定。我們建議運用編譯器來落實良好實務並及早偵測錯誤，但切勿過度使用以致影響程式碼的可讀性與維護性。
- **請謹慎使用 Swift 宏指令。** 宏指令雖能大幅提升效能，但也可能降低程式碼的可讀性與維護性。
- **擁抱平台與語言，切勿抽象化處理。**
  試圖建立繁複的抽象層可能適得其反。平台與語言本身已具備足夠能力打造卓越應用程式，無需額外抽象層。請以優質程式設計與設計模式為參考基準來建構功能。

## 資源{#resources}

- [建立微特徵](https://speakerdeck.com/pepibumur/building-ufeatures)
- [框架導向程式設計](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [框架與 Swift
  之旅](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [運用框架加速 iOS 開發進程 -
  第一部分](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [面向函式庫的程式設計](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [建構現代框架](https://developer.apple.com/videos/play/wwdc2014/416/)
- [非官方 xcconfig 檔案指南](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [靜態與動態函式庫](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
