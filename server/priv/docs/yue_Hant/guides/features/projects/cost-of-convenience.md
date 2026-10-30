---
{
  "title": "便利嘅代價",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Xcode 嘅隱含行為會點樣引發問題，以及 Tuist 點樣避免呢啲情況。"
}
---
# 便利的代價 {#the-cost-of-convenience}

設計一個讓 **由小型到大型專案都能使用** 的程式碼編輯器是一項艱鉅任務。許多工具透過分層解決方案並提供擴充性來處理這個問題。最底層非常低階且貼近底層建置系統，而最頂層則是高階抽象，雖然使用方便但靈活性較低。這樣做讓簡單的事情變得容易，其他事情則成為可能。

然而，**[Apple](https://www.apple.com) 決定為 Xcode 採取不同的做法**。原因不明，但很可能優化大型專案的挑戰從來不是他們的目標。他們在小型專案的便利性上過度投資，提供的靈活性很少，並將工具與底層建置系統緊密耦合。為了達到便利性，他們提供了合理的預設值（你可以輕鬆替換），並加入了許多在編譯時期解析的隱含行為，這些正是造成規模化時許多問題的元兇。

## 明確性與規模 {#explicitness-and-scale}

在大型規模下工作時，**明確性是關鍵**。它讓建置系統能夠提前分析並理解專案結構和依賴關係，並執行否則無法實現的優化。同樣的明確性也是確保編輯器功能（例如 [SwiftUI previews](https://developer.apple.com/documentation/swiftui/previews-in-xcode) 或 [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)）可靠且可預測運作的關鍵。由於 Xcode 和 Xcode 專案將隱含性視為達成便利的有效設計選擇，而 Swift Package Manager 繼承了這一原則，因此使用 Xcode 的困難也存在於 Swift Package Manager 中。

> [!NOTE]
> **Tuist 的角色**
>
> 我們可以將 Tuist 的角色總結為一個防止隱含定義專案的工具，並利用明確性提供更好的開發者體驗（例如驗證、優化）。像 [Bazel](https://bazel.build) 這樣的工具更進一步，將其帶入建置系統層級。


這是一個在社群中很少被討論的問題，但卻非常重要。在開發 Tuist 的過程中，我們注意到許多組織和開發者認為他們目前面臨的挑戰將由 [Swift Package Manager](https://www.swift.org/documentation/package-manager/) 解決，但他們沒有意識到的是，由於它建立在相同的原則之上，即使它緩解了眾所周知的 Git 衝突，卻在其他領域降低了開發者體驗，並繼續使專案無法優化。

在以下章節中，我們將討論一些隱含性如何影響開發者體驗和專案健康的實際例子。這份清單並非詳盡無遺，但應該能讓你大致了解在使用 Xcode 專案或 Swift Packages 時可能面臨的挑戰。

## 便利性成為阻礙 {#convenience-getting-in-your-way}

### 共享建置產物目錄 {#shared-built-products-directory}

Xcode 為每個產品使用衍生資料目錄中的一個目錄。在其中，它儲存建置產物，例如編譯後的二進位檔、dSYM 檔案和日誌。由於專案的所有產品都進入同一個目錄，而其他目標預設可見並可連結該目錄，**你可能會最終得到彼此隱含依賴的目標。** 雖然這在只有少數目標時可能不是問題，但當專案成長時，可能會表現為難以除錯的建置失敗。

這個設計決策的結果是，許多專案意外地以定義不明的圖表進行編譯。

> [!TIP]
> **Tuist 偵測隱含依賴**
>
> Tuist 提供一個 <.localized_link href="/guides/features/projects/inspect/implicit-dependencies">指令</.localized_link> 來偵測隱含依賴。你可以使用該指令在 CI 中驗證所有依賴都是明確的。


### 在 Scheme 中尋找隱含依賴 {#find-implicit-dependencies-in-schemes}

隨著專案成長，在 Xcode 中定義和維護依賴圖變得更加困難。困難在於它們以建置階段和建置設定的形式編碼在 `.pbxproj` 檔案中，沒有工具可以視覺化和操作該圖，而且圖的變更（例如新增動態預編譯框架）可能需要上游設定變更（例如新增建置階段以將框架複製到 bundle 中）。

Apple 在某個時刻決定，與其將圖模型演進為更易管理的形式，不如增加一個在編譯時期解析隱含依賴的選項更為合理。這再次是一個值得商榷的設計選擇，因為你可能會導致建置時間變慢或建置結果不可預測。例如，由於衍生資料中的某些狀態（ acting as a [singleton](https://en.wikipedia.org/wiki/Singleton_pattern)），建置可能在本地通過，但隨後在 CI 上因狀態不同而編譯失敗。

> [!TIP]
> 我們建議在你的專案 Scheme 中停用此功能，並使用像 Tuist 這樣的工具來簡化依賴圖的管理。


### SwiftUI Previews 與靜態函式庫/框架 {#swiftui-previews-and-static-librariesframeworks}

某些編輯器功能（如 SwiftUI Previews 或 Swift Macros）需要從正在編輯的檔案編譯依賴圖。這種編輯器與建置系統的整合要求建置系統解析任何隱含性，並輸出這些功能運作所需的正確產物。可想而知，**圖表越隱含，對建置系統來說任務就越具挑戰性**，因此許多這些功能無法可靠運作並不令人驚訝。我們經常聽到開發者說他們很久以前就停止使用 SwiftUI previews，因為它們太不可靠。相反，他們要麼使用範例應用程式，要麼避免某些事物，例如使用靜態函式庫或腳本建置階段，因為這些會導致功能失效。

### 可合併函式庫 {#mergeable-libraries}

動態框架雖然更靈活且易於使用，但會對應用程式的啟動時間產生負面影響。另一方面，靜態函式庫啟動速度較快，但會影響編譯時間，且在複雜的圖表情境下較難處理。*如果能根據設定在兩者之間切換，豈不是更好？* 這想必是 Apple 決定開發可合併函式庫時的思路。但他們再次將更多編譯時期的推論移到了編譯時期。試想像，如果要推理依賴圖，卻必須在建置時期根據某些目標中的建置設定來解析目標的靜態或動態性質，那會有多困難。要在確保 SwiftUI previews 等功能不會失效的同時讓這種機制可靠運作，祝你好運。

**許多用戶接觸 Tuist 時都想使用可合併函式庫，而我們的回答始終如一：你不需要。** 你可以在專案生成時期控制目標的靜態或動態性質，從而使專案的依賴圖在編譯前就已確定。無需在建置時期解析任何變數。

```bash
# The value of TUIST_DYNAMIC can be read from the project {#the-value-of-tuist_dynamic-can-be-read-from-the-project}
# to set the product as static or dynamic based on the value. {#to-set-the-product-as-static-or-dynamic-based-on-the-value}
TUIST_DYNAMIC=1 tuist generate
```

## 明確、明確、再明確 {#explicit-explicit-and-explicit}

如果有一個重要的不成文原則，是我們建議每位希望其 Xcode 開發能夠擴展的開發者或組織採納的，那就是擁抱明確性。如果原始 Xcode 專案難以管理明確性，則應考慮其他方案，例如 [Tuist](https://tuist.io) 或 [Bazel](https://bazel.build)。**唯有如此，才能實現可靠性、可預測性及優化。**

## 未來 {#future}

Apple 是否會採取措施防止上述所有問題尚不清楚。他們在 Xcode 和 Swift Package Manager 中持續做出的決策並未顯示出這種跡象。一旦你允許隱含設定作為有效狀態，**就很難在不引入破壞性變更的情況下改變現狀。** 回歸基本原則並重新思考工具的設計，可能會導致多年來偶然編譯通過的許多 Xcode 專案失效。想像一下如果發生這種情況，社群會有多麼嘩然。

Apple 陷入了一種雞生蛋、蛋生雞的困境。便利性有助於開發者快速入門並為其生態系統建構更多應用程式。但他們為了在大規模下提供便利體驗所做的決策，卻使得確保某些 Xcode 功能可靠運作變得困難。

由於未來充滿未知，我們試圖 **盡可能貼近行業標準和 Xcode 專案**。我們防止上述問題，並利用我們的知識提供更好的開發者體驗。理想情況下，我們無需訴諸專案生成來達成此目的，但 Xcode 和 Swift Package Manager 缺乏可擴展性，使其成為唯一可行的選項。這也是一個安全的選項，因為他們必須先破壞 Xcode 專案，才會破壞 Tuist 專案。

理想情況下，**建置系統應更具可擴展性**，但如果插件/擴充功能需要與一個充滿隱含性的世界打交道，這難道不是一個壞主意嗎？這似乎並不是一個好主意。因此，我們似乎需要像 Tuist 或 [Bazel](https://bazel.build) 這樣的外部工具來提供更好的開發者體驗。或者也許 Apple 會給我們驚喜，讓 Xcode 更具可擴展性和明確性……

在那之前，你必須選擇是要擁抱 Xcode 的便利性並承擔隨之而來的技術債，還是信任我們在這段旅程中提供更好的開發者體驗。我們不會讓你失望。
