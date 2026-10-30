---
{
  "title": "便利嘅代價",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Xcode 嘅隱含行為點樣導致問題，同埋 Tuist 點樣避免呢啲問題。"
}
---
# 方便嘅代價 {#the-cost-of-convenience}

設計一個 **由小型到大型項目都可以用** 嘅程式碼編輯器係一件困難嘅事。好多工具會透過分層方案同提供擴展性嚟解決呢個問題。最底層非常低階，貼近底層建構系統；最頂層就係高階抽象，用起嚟方便但靈活性較低。咁樣做可以令簡單嘅事變易，其他事亦變得可行。

不過，**[Apple](https://www.apple.com) 為 Xcode 選擇咗另一條路**。原因不明，但好可能優化大型項目嘅挑戰從來唔係佢哋嘅目標。佢哋過度投資於小型項目嘅便利性，提供嘅靈活性有限，並將工具與底層建構系統緊密耦合。為咗達到便利，佢哋提供咗合理嘅預設值（你可以輕鬆替換），同時加入咗大量隱式嘅建構時解析行為，成為規模擴大時許多問題嘅根源。

## 明確性與規模 {#explicitness-and-scale}

當項目規模擴大時，**明確性至關重要**。它讓建構系統可以預先分析並理解項目結構同依賴關係，從而執行否則無法實現嘅優化。同樣嘅明確性對於確保 [SwiftUI previews](https://developer.apple.com/documentation/swiftui/previews-in-xcode) 或 [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) 等編輯器功能可靠且可預測地運作亦至關重要。由於 Xcode 同 Xcode 項目將隱式性視為達成便利嘅有效設計選擇，而 Swift Package Manager 繼承咗呢一原則，因此使用 Xcode 嘅困難同樣存在於 Swift Package Manager 中。

> [!NOTE]
> **Tuist 嘅角色**
>
> 我哋可以將 Tuist 嘅角色總結為一個防止隱式定義項目、並利用明確性提供更佳開發者體驗（例如驗證、優化）嘅工具。像 [Bazel](https://bazel.build) 這類工具更進一步，將此原則落實到建構系統層面。


呢個問題在社區中很少被討論，但卻非常重要。在開發 Tuist 嘅過程中，我哋注意到許多組織同開發者認為 [Swift Package Manager](https://www.swift.org/documentation/package-manager/) 會解決佢哋目前面臨嘅挑戰，但佢哋未意識到，由於 Swift Package Manager 建立在相同原則之上，即使它緩解咗眾所周知嘅 Git 衝突，卻在其他方面降低咗開發者體驗，並繼續令項目難以優化。

在以下章節中，我哋會討論一些真實例子，說明隱式性如何影響開發者體驗同項目健康狀況。清單並非詳盡無遺，但應該讓你對使用 Xcode 項目或 Swift Packages 時可能面臨嘅挑戰有個清晰概念。

## 便利性反而成為障礙 {#convenience-getting-in-your-way}

### 共享建構產物目錄 {#shared-built-products-directory}

Xcode 為每個產品在 derived data 目錄內使用一個目錄。裡面儲存建構產物，例如編譯後嘅二進制文件、dSYM 文件同日誌。由於項目所有產品都進入同一個目錄，而其他 target 預設可以看到並連結該目錄，**你可能會導致 target 之間產生隱式依賴。** 雖然只有少數 target 時這可能不成問題，但當項目擴大時，可能會表現為難以除錯嘅建構失敗。

呢個設計決策嘅後果係，許多項目意外地以定義不清嘅圖進行編譯。

> [!TIP]
> **Tuist 檢測隱式依賴**
>
> Tuist 提供 <.localized_link href="/guides/features/projects/inspect/implicit-dependencies">指令</.localized_link> 來檢測隱式依賴。你可以使用該指令在 CI 中驗證所有依賴都係明確嘅。


### 在 schemes 中查找隱式依賴 {#find-implicit-dependencies-in-schemes}

隨著項目擴大，在 Xcode 中定義同維護依賴圖變得更加困難。困難在於它們以建構階段同建構設定嘅形式編碼在 `.pbxproj` 文件中，沒有工具可以視覺化並處理該圖，而且圖中嘅變更（例如新增一個動態預編譯框架）可能需要上游配置變更（例如新增一個建構階段將框架複製到 bundle 中）。

Apple 在某個時刻決定，與其將圖模型演進為更易管理嘅形式，不如新增一個選項在建構時解析隱式依賴更為合理。這再次係一個值得商榷嘅設計選擇，因為你可能最終面臨更慢嘅建構時間或不可預測嘅建構結果。例如，由於 derived data 中嘅某些狀態（其作用類似 [singleton](https://en.wikipedia.org/wiki/Singleton_pattern)），建構可能在本地通過，但隨後因狀態不同而在 CI 上編譯失敗。

> [!TIP]
> 我哋建議在你嘅項目 schemes 中禁用此選項，並使用像 Tuist 這樣簡化依賴圖管理嘅工具。


### SwiftUI Previews 與靜態庫/框架 {#swiftui-previews-and-static-librariesframeworks}

某些編輯器功能（如 SwiftUI Previews 或 Swift Macros）需要從正在編輯嘅文件編譯依賴圖。編輯器與建構系統之間嘅集成要求建構系統解析任何隱式性，並輸出這些功能正常工作所需嘅正確產物。可想而知，**圖越隱式，建構系統嘅任務就越具挑戰性**，因此許多這些功能無法可靠運作並不足為奇。我哋經常聽到開發者說，他們很久以前就停止使用 SwiftUI previews，因為它們太不可靠。相反，他們要么使用示例應用，要么避免某些事情（例如使用靜態庫或腳本建構階段），因為這些會導致功能失效。

### 可合併庫 {#mergeable-libraries}

動態框架雖然更靈活、更易於使用，但會對應用程式啟動時間產生負面影響。另一方面，靜態庫啟動更快，但會影響編譯時間，而且較難使用，特別是在複雜依賴圖場景中。*如果可以根據配置在兩者之間切換，豈不是更好？* 這應該就是 Apple 決定開發可合併庫時嘅想法。但又一次，他們將更多建構時推論移到了建構時。試想像一下，如果要推理依賴圖，而目標係靜態定動態要根據某些目標中嘅建構設定在建構時先解析，情況會幾複雜。要在確保 SwiftUI previews 等功能不會失效嘅同時令其可靠運作，真係好難。

**許多用戶接觸 Tuist 時都想使用可合併庫，而我哋嘅答案總係一樣：你不需要。** 你可以在生成時控制目標嘅靜態或動態性質，從而令項目嘅依賴圖在編譯前就已確定。無需在建構時解析任何變量。

```bash
# The value of TUIST_DYNAMIC can be read from the project {#the-value-of-tuist_dynamic-can-be-read-from-the-project}
# to set the product as static or dynamic based on the value. {#to-set-the-product-as-static-or-dynamic-based-on-the-value}
TUIST_DYNAMIC=1 tuist generate
```

## 明確、明確、再明確 {#explicit-explicit-and-explicit}

如果我哋要向每位希望其 Xcode 開發能夠擴展嘅開發者或組織推薦一個重要嘅不成文原則，那就係擁抱明確性。如果原始 Xcode 項目難以管理明確性，就應該考慮其他方案，例如 [Tuist](https://tuist.io) 或 [Bazel](https://bazel.build)。**唯有如此，可靠性、可預測性同優化才有可能實現。**

## 未來 {#future}

Apple 會否採取措施防止上述所有問題，目前尚不清楚。他們持續嵌入 Xcode 同 Swift Package Manager 中嘅決策並未顯示出會這樣做嘅跡象。一旦你允許隱式配置作為有效狀態，**就很難在不引入破壞性變更嘅情況下改變現狀。** 回到基本原則並重新思考工具設計，可能會導致多年來意外編譯成功嘅許多 Xcode 項目失效。想像一下如果發生這種情況，社區會幾大反應。

Apple 陷入咗某種雞生蛋、蛋生雞嘅困境。便利性幫助開發者快速入門並為其生態系統構建更多應用程式。但他們為咗喺該規模上提供便利體驗而做出嘅決策，卻令他們難以確保某些 Xcode 功能可靠運作。

由於未來未知，我哋試圖 **盡量貼近行業標準同 Xcode 項目**。我哋防止上述問題，並利用現有知識提供更好嘅開發者體驗。理想情況下，我哋本無需為此訴諸項目生成，但 Xcode 同 Swift Package Manager 缺乏可擴展性，令其成為唯一可行嘅選項。這亦係一個安全嘅選項，因為他們必須先破壞 Xcode 項目，先會破壞 Tuist 項目。

理想情況下，**建構系統應該更具可擴展性**，但如果插件/擴展需要與充滿隱式性嘅世界交互，豈不是一個壞主意？這似乎並非好主意。因此，我哋似乎需要像 Tuist 或 [Bazel](https://bazel.build) 這樣嘅外部工具來提供更好嘅開發者體驗。或者 Apple 會給所有人帶來驚喜，讓 Xcode 更具可擴展性同明確性……

在那發生之前，你需要選擇係擁抱 Xcode 嘅便利並承擔隨之而來嘅技術債，還係信任我哋在這段旅程中提供更好嘅開發者體驗。我哋不會令你失望。
