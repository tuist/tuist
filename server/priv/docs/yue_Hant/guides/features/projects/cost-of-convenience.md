---
{
  "title": "方便嘅代價",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Xcode 嘅隱含行為會點樣引發問題，以及 Tuist 點樣防止呢啲情況。"
}
---
# 方便嘅代價 {#the-cost-of-convenience}

設計一個能夠適用於**各種規模項目，由小型到大型**嘅程式碼編輯器係一項艱鉅任務。許多工具透過分層解決方案並提供可擴展性來應對呢個問題。最底層非常低階且貼近底層構建系統，而最頂層則係一個易於使用但靈活性較低嘅高階抽象。透過咁做，佢哋令簡單嘅事情變得容易，並使其他一切成為可能。

然而，**[Apple](https://www.apple.com) 決定為 Xcode 採取不同方法**。原因不明，但好可能優化大型項目挑戰從來唔係佢哋嘅目標。佢哋過度投資於小型項目嘅便利性，提供嘅靈活性好少，並將工具與底層構建系統緊密耦合。為咗實現便利性，佢哋提供合理嘅預設值（你可以輕鬆替換），並添加咗大量隱式構建時解析行為，這些正係導致大規模項目出現許多問題嘅元兇。

## 明確性與規模 {#explicitness-and-scale}

當處理大規模項目時，**明確性至關重要**。它允許構建系統提前分析並理解項目結構同依賴關係，從而執行否則無法實現嘅優化。同樣嘅明確性對於確保[SwiftUI 預覽](https://developer.apple.com/documentation/swiftui/previews-in-xcode)或[Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)等編輯器功能可靠且可預測地運作亦係關鍵。由於 Xcode 同 Xcode 項目將隱式性視為實現便利性嘅有效設計選擇，而 Swift Package Manager 繼承咗呢一原則，因此使用 Xcode 嘅困難同樣存在於 Swift Package Manager 中。

> [!NOTE]
> **Tuist 嘅角色**
>
> 我哋可以將 Tuist 嘅角色總結為一個防止隱式定義項目並利用明確性以提供更佳開發者體驗（例如驗證、優化）嘅工具。像[Bazel](https://bazel.build)這樣嘅工具更進一步，將其下沉到構建系統層級。


呢個係社區中幾乎無人討論但極其重要嘅問題。在開發 Tuist 期間，我哋注意到許多組織同開發者認為[Swift Package Manager](https://www.swift.org/documentation/package-manager/)會解決佢哋面臨嘅當前挑戰，但佢哋未意識到嘅係，由於它基於相同原則構建，儘管它緩解咗眾所周知嘅 Git 衝突，卻在其他方面降低咗開發者體驗，並繼續使項目難以優化。

在以下章節中，我哋將討論一些真實案例，說明隱式性如何影響開發者體驗同項目健康狀況。列表並非詳盡無遺，但應該能讓你充分了解在使用 Xcode 項目或 Swift Packages 時可能面臨嘅挑戰。

## 便利性成為阻礙 {#convenience-getting-in-your-way}

### 共享構建產品目錄 {#shared-built-products-directory}

Xcode 為每個產品在衍生數據目錄內使用一個目錄。裡面儲存構建成品，例如編譯後嘅二進制文件、dSYM 文件同日誌。由於項目所有產品都進入同一個目錄，而其他目標默認可見該目錄以進行鏈接，**你可能會最終得到相互隱式依賴嘅目標。** 雖然當只有少數幾個目標時這可能不成問題，但隨著項目增長，它可能表現為難以調試嘅構建失敗。

呢個設計決策嘅後果係，許多項目意外地使用定義不清嘅圖進行編譯。

> [!TIP]
> **Tuist 檢測隱式依賴**
>
> Tuist 提供一個<.localized_link href="/guides/features/projects/inspect/implicit-dependencies">命令</.localized_link>來檢測隱式依賴。你可以使用該命令在 CI 中驗證你所有依賴關係都係明確嘅。


### 在 Scheme 中查找隱式依賴 {#find-implicit-dependencies-in-schemes}

隨著項目增長，在 Xcode 中定義同維護依賴圖變得更加困難。困難在於它們以構建階段同構建設置嘅形式編碼在`.pbxproj`文件中，沒有工具可視化並處理該圖，並且圖中嘅更改（例如添加新嘅動態預編譯框架）可能需要上游配置更改（例如添加新嘅構建階段以將框架複製到 bundle 中）。

Apple 在某個時刻決定，與其將圖模型演變為更易管理嘅形式，不如添加一個選項在構建時解析隱式依賴更為合理。這再次係一個值得商榷嘅設計選擇，因為你可能會導致構建時間變慢或構建結果不可預測。例如，由於衍生數據中嘅某種狀態（其作用類似於[單例](https://en.wikipedia.org/wiki/Singleton_pattern)），構建可能在本地通過，但隨後因狀態不同而在 CI 上編譯失敗。

> [!TIP]
> 我哋建議在你嘅項目 Scheme 中禁用此功能，並使用像 Tuist 這樣簡化依賴圖管理嘅工具。


### SwiftUI 預覽與靜態庫/框架 {#swiftui-previews-and-static-librariesframeworks}

某些編輯器功能（如 SwiftUI 預覽或 Swift Macros）需要從正在編輯嘅文件編譯依賴圖。編輯器之間嘅這種集成要求構建系統解析任何隱式性並輸出這些功能正常工作所需嘅正確成品。可想而知，**圖越隱式，構建系統面臨嘅任務就越具挑戰性**，因此許多這些功能無法可靠運作並不足為奇。我哋經常聽到開發者表示，他們很久以前就停止使用 SwiftUI 預覽，因為它們太不可靠。相反，佢哋要麼使用示例應用，要麼避免某些事情，例如使用靜態庫或腳本構建階段，因為這些會導致功能失效。

### 可合併庫 {#mergeable-libraries}

動態框架雖然更靈活且更易於使用，但會對應用啟動時間產生負面影響。另一方面，靜態庫啟動更快，但會影響編譯時間，並且較難處理，特別是在複雜的圖結構場景中。*如果可以根據配置在兩者之間切換，豈不是更好？* 這一定是 Apple 決定開發可合併庫時的想法。但再一次，他們將更多構建時推斷移到了構建階段。如果考慮依賴圖，想像一下當目標的靜態或動態性質將根據某些目標中的構建設置在構建時解析時，必須這樣做。要在確保 SwiftUI 預覽等功能不會失效的同時讓其可靠運作，祝你好運。

**許多用戶來到 Tuist 希望使用可合併庫，而我哋嘅回答始終如一：你不需要。** 你可以在生成時控制目標的靜態或動態性質，從而使項目的圖結構在編譯前就已確定。無需在構建時解析任何變量。

```bash
# The value of TUIST_DYNAMIC can be read from the project {#the-value-of-tuist_dynamic-can-be-read-from-the-project}
# to set the product as static or dynamic based on the value.
TUIST_DYNAMIC=1 tuist generate
```

## 明確、明確、再明確 {#explicit-explicit-and-explicit}

如果我哋建議每個希望其 Xcode 開發能夠擴展嘅開發者或組織遵循一個重要嘅不成文原則，那就係擁抱明確性。如果原始 Xcode 項目難以管理明確性，佢哋應該考慮其他方案，例如 [Tuist](https://tuist.dev) 或 [Bazel](https://bazel.build)。**只有這樣，可靠性、可預測性和優化才成為可能。**

## 未來 {#future}

Apple 是否會採取措施防止上述所有問題尚不清楚。他們嵌入 Xcode 和 Swift Package Manager 中嘅持續決策並未表明他們會這樣做。一旦你允許隱式配置作為有效狀態，**就很難在不引入破壞性更改的情況下改變現狀。** 回歸基本原則並重新思考工具設計可能會導致破壞多年來意外編譯成功的許多 Xcode 項目。想像一下如果發生這種情況，社區會有多麼嘩然。

Apple 陷入了一種雞生蛋、蛋生雞的困境。便利性幫助開發者快速入門並為其生態系統構建更多應用。但他們為了在大規模下提供便利體驗而做出的決策，使得他們難以確保某些 Xcode 功能可靠運作。

由於未來未知，我哋試圖 **盡可能貼近行業標準和 Xcode 項目**。我哋防止上述問題，並利用現有知識提供更好的開發者體驗。理想情況下，我哋不必為此訴諸項目生成，但 Xcode 和 Swift Package Manager 缺乏可擴展性使其成為唯一可行的選擇。這也是一個安全的選擇，因為他們必須破壞 Xcode 項目才能破壞 Tuist 項目。

理想情況下，**構建系統應該更具可擴展性**，但擁有與隱式世界交互的插件/擴展難道不是一個壞主意嗎？這似乎不是一個好主意。因此，似乎我哋需要像 Tuist 或 [Bazel](https://bazel.build) 這樣的外部工具來提供更好的開發者體驗。或者也許 Apple 會給所有人帶來驚喜，讓 Xcode 更具可擴展性和明確性……

在那之前，你必須選擇是擁抱 Xcode 的便利性並承擔隨之而來的技術債務，還是信任我哋在這段旅程中提供更好的開發者體驗。我哋不會讓你失望。
