---
{
  "title": "便利嘅代價",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Xcode 嘅隱含行為會點樣引發問題，同埋 Tuist 點樣防止呢啲問題。"
}
---
# 方便嘅代價 {#the-cost-of-convenience}

設計一個適用於 **各種規模項目，由小型到大型** 嘅程式碼編輯器係一項艱鉅任務。許多工具透過分層解決方案並提供擴展性來應對這個問題。最底層非常低階且貼近底層建構系統，而最頂層則係一個高階抽象層，雖然使用方便但靈活性較低。透過呢種方式，佢哋令簡單嘅事情變得容易，並使其他事情成為可能。

然而，**[Apple](https://www.apple.com) 決定為 Xcode 採取不同嘅方法**。原因不明，但好可能優化大型項目挑戰從來都唔係佢哋嘅目標。佢哋過度投資於小型項目嘅便利性，提供咗極少嘅靈活性，並將工具與底層建構系統緊密耦合。為咗實現便利性，佢哋提供咗合理嘅預設值（你可以輕鬆替換），並添加咗大量隱式建構時解析行為，這些行為係導致許多規模化問題嘅元兇。

## 明確性與規模 {#explicitness-and-scale}

當進行大規模開發時，**明確性至關重要**。它允許建構系統提前分析並理解項目結構同依賴關係，並執行否則無法實現嘅優化。同樣嘅明確性對於確保諸如 [SwiftUI previews](https://developer.apple.com/documentation/swiftui/previews-in-xcode) 或 [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) 等編輯器功能可靠且可預測地運作亦至關重要。由於 Xcode 同 Xcode 項目將隱式性作為實現便利性嘅有效設計選擇——這一原則已被 Swift Package Manager 繼承——因此使用 Xcode 嘅困難同樣存在於 Swift Package Manager 中。

> [!NOTE]
> **Tuist 嘅角色**
>
> 我哋可以將 Tuist 嘅角色總結為一種防止隱式定義項目並利用明確性以提供更好開發者體驗（例如驗證、優化）嘅工具。像 [Bazel](https://bazel.build) 這樣嘅工具更進一步，將其帶到建構系統層面。


這是一個在社區中很少被討論但非常重要嘅問題。在開發 Tuist 期間，我哋注意到許多組織同開發者認為他們面臨嘅當前挑戰將由 [Swift Package Manager](https://www.swift.org/documentation/package-manager/) 解決，但他們沒有意識到，由於它建立在相同原則之上，儘管它緩解咗眾所周知嘅 Git 衝突，卻在其他方面降低咗開發者體驗，並繼續使項目無法優化。

在以下章節中，我哋將討論一些真實案例，說明隱式性如何影響開發者體驗同項目健康狀況。列表並非詳盡無遺，但應該讓你對使用 Xcode 項目或 Swift Packages 時可能面臨嘅挑戰有一個良好嘅了解。

## 便利性成為你嘅障礙 {#convenience-getting-in-your-way}

### 共享建構產品目錄 {#shared-built-products-directory}

Xcode 為每個產品使用衍生數據目錄內的一個目錄。在其中，它儲存建構產物，例如編譯後嘅二進制文件、dSYM 文件同日誌。由於項目嘅所有產品都進入同一個目錄，而其他目標默認可見該目錄以進行連結，**你可能會最終得到相互隱式依賴嘅目標。** 雖然當只有少數幾個目標時這可能不成問題，但隨著項目增長，它可能表現為難以調試嘅建構失敗。

此設計決策嘅後果係許多項目意外地以未良好定義嘅圖進行編譯。

> [!TIP]
> **Tuist 檢測隱式依賴**
>
> Tuist 提供一個 <.localized_link href="/guides/features/projects/inspect/implicit-dependencies">命令</.localized_link> 來檢測隱式依賴。你可以使用該命令在 CI 中驗證你嘅所有依賴關係都係明確嘅。


### 在 Scheme 中查找隱式依賴 {#find-implicit-dependencies-in-schemes}

隨著項目增長，在 Xcode 中定義同維護依賴圖變得更加困難。困難在於它們以建構階段同建構設定嘅形式編碼在 `.pbxproj` 文件中，沒有工具可以可視化並處理該圖，並且圖中嘅更改（例如添加新嘅動態預編譯框架）可能需要上游配置更改（例如添加新嘅建構階段以將框架複製到 bundle 中）。

Apple 在某個時刻決定，與其將圖模型演進為更易管理嘅形式，不如添加一個選項來在建構時解析隱式依賴更為合理。這再次係一個值得商榷嘅設計選擇，因為你可能會最終得到更慢嘅建構時間或不可預測嘅建構。例如，由於衍生數據中嘅某些狀態（其作用類似於 [singleton](https://en.wikipedia.org/wiki/Singleton_pattern)），建構可能在本地通過，但隨後因狀態不同而在 CI 上編譯失敗。

> [!TIP]
> 我哋建議在你嘅項目 scheme 中禁用此功能，並使用像 Tuist 這樣簡化依賴圖管理嘅工具。


### SwiftUI Previews 同靜態庫/框架 {#swiftui-previews-and-static-librariesframeworks}

某些編輯器功能（如 SwiftUI Previews 或 Swift Macros）需要從正在編輯嘅文件編譯依賴圖。編輯器與此之間嘅集成要求建構系統解析任何隱式性並輸出這些功能正常工作所需嘅正確產物。可想而知，**圖越隱式，對建構系統來說任務就越具挑戰性**，因此許多這些功能無法可靠運作並不足為奇。我哋經常聽到開發者說他們很久以前就停止使用 SwiftUI previews，因為它們太不可靠。相反，他們要么使用示例應用程序，要么避免某些事情，例如使用靜態庫或腳本建構階段，因為這些會導致功能失效。

### 可合併庫 {#mergeable-libraries}

動態框架雖然更靈活且易於使用，但會對應用啟動時間產生負面影響。另一方面，靜態庫啟動更快，但會影響編譯時間，並且較難使用，特別是在複雜的依賴圖場景中。*如果能夠根據配置在兩者之間切換，豈不是更好？* 這肯定是 Apple 決定開發可合併庫時的想法。但再一次，他們將更多建構時推斷移到了建構階段。試想像一下，如果要推理依賴圖，而目標的靜態或動態性質要根據某些目標中的建構設定在建構時才解析，情況會有多複雜。要在確保 SwiftUI previews 等功能不會失效的同時讓這種機制可靠運作，祝你好運。

**許多用戶來到 Tuist 希望使用可合併庫，而我哋的回答總是一樣：你不需要。** 你可以在生成時控制目標的靜態或動態性質，從而使項目的依賴圖在編譯前就已確定。無需在建構時解析任何變量。

```bash
# The value of TUIST_DYNAMIC can be read from the project {#the-value-of-tuist_dynamic-can-be-read-from-the-project}
# to set the product as static or dynamic based on the value.
TUIST_DYNAMIC=1 tuist generate
```

## 明確、明確、再明確 {#explicit-explicit-and-explicit}

如果我哋要向每位希望其 Xcode 開發能夠擴展嘅開發者或組織推薦一個重要嘅不成文原則，那就是擁抱明確性。如果原始 Xcode 項目難以管理明確性，他們應該考慮其他方案，例如 [Tuist](https://tuist.dev) 或 [Bazel](https://bazel.build)。**只有這樣，可靠性、可預測性和優化才有可能實現。**

## 未來 {#future}

Apple 是否會採取措施防止上述所有問題尚不清楚。他們嵌入到 Xcode 和 Swift Package Manager 中嘅持續決策並未顯示出這種跡象。一旦你允許隱式配置作為有效狀態，**就很難在不引入破壞性更改的情況下改變現狀。** 回歸基本原則並重新思考工具設計可能會導致多年來偶然編譯成功嘅許多 Xcode 項目失效。想像一下如果發生這種情況，社區會有多麼嘩然。

Apple 陷入了一種雞生蛋、蛋生雞嘅困境。便利性幫助開發者快速入門並為其生態系統構建更多應用。但他們為了在大規模下提供便利體驗而做出嘅決策，使得他們難以確保某些 Xcode 功能可靠運作。

由於未來未知，我哋嘗試 **盡可能貼近行業標準和 Xcode 項目**。我哋防止上述問題，並利用現有知識提供更好的開發者體驗。理想情況下，我哋無須訴諸項目生成來實現這一點，但 Xcode 和 Swift Package Manager 缺乏可擴展性，使其成為唯一可行嘅選項。這也是一個安全嘅選項，因為他們必須破壞 Xcode 項目才能破壞 Tuist 項目。

理想情況下，**建構系統應更具可擴展性**，但如果插件/擴展需要與充滿隱式性嘅世界打交道，這豈不是一個壞主意？這似乎並不是一個好主意。因此，看來我哋需要像 Tuist 或 [Bazel](https://bazel.build) 這樣嘅外部工具來提供更好的開發者體驗。或者也許 Apple 會給所有人帶來驚喜，讓 Xcode 更具可擴展性和明確性……

在那之前，你必須選擇是擁抱 Xcode 嘅便利性並承擔隨之而來嘅技術債，還是信任我哋在這段旅程中提供更好的開發者體驗。我哋不會讓你失望。
