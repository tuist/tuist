---
{
  "title": "The cost of convenience",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the cost of convenience in Xcode and how Tuist helps you prevent the issues that come with it."
}
---
# 便利的代價{#the-cost-of-convenience}

**
設計一個從小型專案到大型專案都能使用的程式碼編輯器**是一項極具挑戰性的任務。許多工具透過分層解決方案和提供擴充性來處理這個問題。最底層是非常低階且接近底層的建立系統，而最上層則是方便使用但靈活性較低的高階抽象。透過這樣的方式，他們讓簡單的事情變得容易，而其他的事情則變得可能。

然而，**[Apple](https://www.apple.com) 決定在 Xcode**
採用不同的方法。原因不明，但很可能是針對大型專案的挑戰進行最佳化從來就不是他們的目標。他們對小型專案的便利性投資過多，提供的彈性很少，而且將工具與底層建置系統強烈耦合。為了達到便利性，他們提供了合理的預設值，而您可以輕易取代這些預設值，並且加入了許多隱含的建立時間解析行為，這些行為是許多大規模問題的罪魁禍首。

## 明確性與規模{#explicitness-and-scale}

在大規模工作時，**明確性是關鍵** 。它允許建立系統提前分析和瞭解專案結構與相依性，並執行其他方式無法達成的最佳化。同樣的明確性也是確保編輯器功能（例如
[SwiftUI
預覽](https://developer.apple.com/documentation/swiftui/previews-in-xcode) 或
[Swift
巨集](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)）可靠且可預期運作的關鍵。由於
Xcode 與 Xcode 專案將 implicitness 視為達成便利性的有效設計選擇，而 Swift Package Manager
也繼承了這個原則，因此使用 Xcode 時所遇到的困難在 Swift Package Manager 中也同樣存在。

::: info THE ROLE OF TUIST
<!-- -->
我們可以將 Tuist 的角色概括為防止隱式定義專案的工具，並利用明確性提供更好的開發者經驗（例如驗證、最佳化）。像
[Bazel](https://bazel.build) 之類的工具則更進一步，將它帶到建置系統層級。
<!-- -->
:::

這個問題在社群中幾乎沒有討論過，但卻是一個重要的問題。在開發 Tuist 的過程中，我們注意到許多組織與開發人員都認為 [Swift
套件管理員](https://www.swift.org/documentation/package-manager/)可以解決他們目前所面臨的挑戰，但他們沒有意識到的是，由於
[Swift 套件管理員](https://www.swift.org/documentation/package-manager/)
是建立在相同的原則上，即使它可以緩解眾所皆知的 Git 衝突，但卻降低了開發人員在其他方面的體驗，並繼續讓專案無法最佳化。

在以下幾節中，我們將討論一些隱含性如何影響開發者體驗和專案健康的真實範例。這份清單並非詳盡無遺，但應該可以讓您了解在使用 Xcode 專案或 Swift
套件時可能面臨的挑戰。

## 便利性成為您的障礙{#convenience-getting-in-your-way}

### 共用建置的產品目錄{#shared-built-products-directory}

Xcode 在每個產品的派生資料目錄內使用一個目錄。在這個目錄中，它儲存了建立的工件，例如編譯的二進位檔案、dSYM
檔案和日誌。由於專案中的所有產品都會存放在同一個目錄中，而其他目標預設是可以看到該目錄以進行連結的，因此**，您可能會發現目標之間彼此隱含依賴。**
雖然這在只有幾個目標時可能不是問題，但當專案擴大時，可能會出現難以除錯的建立失敗。

這個設計決定的後果是，許多專案在編譯時會意外地產生定義不佳的圖形。

::: tip TUIST DETECTION OF IMPLICIT DEPENDENCIES
<!-- -->
Tuist 提供了
<LocalizedLink href="/guides/features/inspect/implicit-dependencies">command</LocalizedLink>
來偵測隱含的相依性。您可以使用該命令在 CI 中驗證所有的依賴關係都是顯式的。
<!-- -->
:::

### 尋找方案中的隱含相依性{#find-implicit-dependencies-in-schemes}

在 Xcode 中定義和維護相依性圖形會隨著專案的成長而變得越來越困難。它之所以困難，是因為它們被編碼在`.pbxproj`
檔案中，作為建置階段和建置設定，沒有工具可視化和處理圖形，而且圖形中的變更（例如新增動態預編譯框架），可能需要上游的組態變更（例如新增建置階段，將框架複製到
bundle 中）。

Apple
在某個時候決定，與其將圖表模型演進成更容易管理的東西，不如加入一個選項，在建立時解決隱含的依賴關係。這再次是一個值得商榷的設計選擇，因為您可能會因此而導致較慢的建立時間或無法預測的建立。舉例來說，可能會因為派生資料中的某些狀態而導致本機編譯通過，而派生資料就像是
[singleton](https://en.wikipedia.org/wiki/Singleton_pattern)，但在 CI
上卻因為狀態不同而無法編譯。

::: tip
<!-- -->
我們建議您在專案方案中停用此功能，並使用類似 Tuist 的軟體來簡化相依性圖形的管理。
<!-- -->
:::

### SwiftUI 預覽和靜態程式庫/框架{#swiftui-previews-and-static-librariesframeworks}

某些編輯器功能（例如 SwiftUI 預覽或 Swift
巨集）需要從正在編輯的檔案中編譯相依性圖形。編輯器之間的這種整合需要建立系統解決任何隱含性，並輸出這些功能運作所需的正確工件。您可以想像，**，圖形越隱含，建立系統的任務就越具挑戰性**
，因此許多這些功能無法可靠運作也就不足為奇了。我們經常聽到開發人員說，他們很久以前就停止使用 SwiftUI
預覽版了，因為它們太不可靠。取而代之的是，他們使用範例應用程式，或是避免使用某些東西，例如使用靜態函式庫或腳本建立階段，因為這些東西會導致功能無法正常運作。

### 可合併的庫{#mergeable-libraries}

動態框架雖然更靈活、更容易使用，但對應用程式的啟動時間有負面影響。另一方面，靜態函式庫啟動速度較快，但會影響編譯時間，而且較難使用，特別是在複雜的圖形情境中。*如果您可以根據配置在兩者之間進行選擇，那豈不是很棒？*
當 Apple
決定開發可合併的函式庫時，他們一定是這麼想的。但他們再一次把更多的建立時推理移到建立時。如果要推理相依性圖形，想像一下當目標的靜態或動態性質將在建立時根據某些目標中的某些建立設定來解析時，就必須這樣做。祝您好運，在確保
SwiftUI 預覽等功能不被破壞的同時，還能可靠地運作。

**很多用戶來到 Tuist 希望使用可合併庫，而我們的答案總是一樣的。您不需要。**
您可以在生成時控制目標的靜態或動態性質，使專案在編譯前就知道其圖形。不需要在建立時解決任何變數。

```bash
# The value of TUIST_DYNAMIC can be read from the project {#the-value-of-tuist_dynamic-can-be-read-from-the-project}
# to set the product as static or dynamic based on the value. {#to-set-the-product-as-static-or-dynamic-based-on-the-value}
TUIST_DYNAMIC=1 tuist generate
```

## 明確、明確、明確{#explicit-explicit-and-explicit}

如果有一個重要的非書面原則，我們建議每一個希望使用 Xcode 開發的開發人員或組織，他們應該接受明確性。如果顯性化在原始的 Xcode
專案中很難管理，那麼他們應該考慮其他東西，無論是 [Tuist](https://tuist.io) 或
[Bazel](https://bazel.build)。**只有這樣，可靠性、可預測性和最佳化才有可能實現。**

## 未來{#future}

Apple 是否會採取措施來避免上述所有問題，目前仍是未知之數。他們嵌入到 Xcode 和 Swift Package Manager
中的持續決策並沒有顯示他們會這樣做。一旦您允許隱含式組態為有效狀態，**，就很難在不引入破壞性變更的情況下繼續前進。**
回到最初的原則並重新思考工具的設計，可能會導致許多 Xcode 專案意外地編譯破壞多年。想像一下如果發生這種情況，社群會有多憤怒。

Apple
發現自己陷入了一個雞與蛋的問題。便利性可以幫助開發人員快速上手，並為他們的生態系統建立更多的應用程式。但是，他們為了讓體驗更便利而做出的決定，卻讓他們難以確保
Xcode 的某些功能能可靠地運作。

因為未來是未知的，所以我們嘗試讓**盡可能接近業界標準和 Xcode 專案**
。我們防止上述問題的發生，並利用我們所擁有的知識來提供更好的開發者經驗。理想的情況是，我們不必為此而採用專案產生的方式，但 Xcode 和 Swift
Package Manager 缺乏擴充性，因此這是唯一可行的選擇。這也是一個安全的選擇，因為他們必須破解 Xcode 專案才能破解 Tuist 專案。

在理想的情況下，**，建立系統是更可擴充的** ，但如果有外掛/擴充套件與隱含的世界簽約，這不是一個壞主意嗎？這似乎不是個好主意。因此，我們似乎需要 Tuist
或 [Bazel](https://bazel.build) 之類的外部工具來提供更好的開發者體驗。或許 Apple 會讓我們大吃一驚，讓 Xcode
變得更可擴充、更明確...

在此之前，您必須選擇是接受 Xcode 的信念並承擔隨之而來的債務，還是相信我們在提供更好開發者體驗的旅程中。我們不會讓您失望的。
