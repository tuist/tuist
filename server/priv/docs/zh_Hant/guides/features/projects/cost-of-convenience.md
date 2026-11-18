---
{
  "title": "便利的代價",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "Xcode 的隱含行為如何導致問題，以及 Tuist 如何防止這些問題。"
}
---
# 便利的代價 {#the-cost-of-convenience}

設計一個能適用於**各種規模專案，從小型到大型**的程式碼編輯器是一項艱鉅的任務。許多工具透過分層解決方案並提供擴充性來處理這個問題。最底層非常低階且貼近底層建置系統，而最上層則是高階抽象，雖然使用方便但彈性較低。如此一來，它們讓簡單的事情變得容易，也讓其他事情成為可能。

然而，**[Apple](https://www.apple.com) 決定為 Xcode 採取不同的做法**。原因不明，但很可能優化大型專案的挑戰從來不是他們的目標。他們過度投資於小型專案的便利性，提供的彈性有限，並將工具與底層建置系統緊密耦合。為了實現這種便利性，他們提供了合理的預設值（你可以輕鬆替換），並加入了許多在編譯時期解析的隱含行為，這些行為正是大規模專案中許多問題的根源。

## 明確性與規模 {#explicitness-and-scale}

在大規模開發時，**明確性是關鍵**。它讓建置系統能夠事先分析並理解專案結構與相依性，進而執行否則無法實現的最佳化。同樣的明確性也是確保編輯器功能（例如 [SwiftUI previews](https://developer.apple.com/documentation/swiftui/previews-in-xcode) 或 [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)）可靠且可預測運作的關鍵。由於 Xcode 與 Xcode 專案將隱含性視為實現便利的有效設計選擇，而 Swift Package Manager 繼承了這一原則，因此使用 Xcode 的困難也出現在 Swift Package Manager 中。

> [!NOTE]
> **Tuist 的角色**
>
> 我們可以將 Tuist 的角色總結為一種防止隱含定義專案的工具，並利用明確性提供更好的開發者體驗（例如驗證、最佳化）。像 [Bazel](https://bazel.build) 這樣的工具更進一步，將其深入至建置系統層級。


這是一個在社群中鮮少被討論但卻相當重要的議題。在開發 Tuist 的過程中，我們注意到許多組織與開發者認為他們目前面臨的挑戰將由 [Swift Package Manager](https://www.swift.org/documentation/package-manager/) 解決，但他們沒有意識到的是，由於它建立在相同的原則之上，儘管它緩解了眾所周知的 Git 衝突，卻在其他方面降低了開發者體驗，並持續讓專案無法最佳化。

在以下章節中，我們將討論一些實際例子，說明隱含性如何影響開發者體驗與專案健康度。這份清單並非詳盡無遺，但應該能讓你大致了解在使用 Xcode 專案或 Swift Packages 時可能面臨的挑戰。

## 便利性成為阻礙 {#convenience-getting-in-your-way}

### 共用的建置產物目錄 {#shared-built-products-directory}

Xcode 為每個產物在 derived data 目錄中使用一個子目錄。在其中，它儲存建置產物，例如編譯後的二進位檔、dSYM 檔案與日誌。由於專案的所有產物都進入同一個目錄，而其他 target 預設可見該目錄以進行連結，**你可能會得到彼此隱含相依的 target。** 雖然在只有少數幾個 target 時這可能不是問題，但當專案成長時，這可能會表現為難以除錯的建置失敗。

此設計決策的結果是，許多專案意外地以未明確定義的圖形進行編譯。

> [!TIP]
> **Tuist 偵測隱含相依性**
>
> Tuist 提供一個 <.localized_link href="/guides/features/projects/inspect/implicit-dependencies">指令</.localized_link> 來偵測隱含相依性。你可以使用該指令在 CI 中驗證所有相依性都是明確的。


### 在 schemes 中找出隱含相依性 {#find-implicit-dependencies-in-schemes}

隨著專案成長，在 Xcode 中定義與維護相依性圖形變得更加困難。困難的原因在於它們以建置階段與建置設定的形式編碼在 `.pbxproj` 檔案中，沒有工具可以視覺化與操作該圖形，而且圖形的變更（例如新增一個動態預編譯框架）可能需要上游設定變更（例如新增一個建置階段以將框架複製到 bundle 中）。

Apple 在某個時刻決定，與其將圖形模型演進為更易管理的形式，不如增加一個選項在建置時期解析隱含相依性。這再次是一個值得商榷的設計選擇，因為你可能會導致建置時間變慢或建置結果不可預測。例如，由於 derived data 中的某些狀態（其作用如同 [singleton](https://en.wikipedia.org/wiki/Singleton_pattern)），建置可能在本地通過，但隨後在 CI 上因狀態不同而編譯失敗。

> [!TIP]
> 我們建議在你的專案 schemes 中停用此選項，並使用像 Tuist 這樣能簡化相依性圖形管理的工具。


### SwiftUI Previews 與靜態函式庫／框架 {#swiftui-previews-and-static-librariesframeworks}

某些編輯器功能（如 SwiftUI Previews 或 Swift Macros）需要從正在編輯的檔案編譯相依性圖形。編輯器與建置系統之間的整合要求建置系統解析任何隱含性，並輸出這些功能運作所需的正確產物。可想而知，**圖形越隱含，建置系統的任務就越具挑戰性**，因此許多這些功能無法可靠運作並不令人驚訝。我們經常聽到開發者表示，他們很早就停止使用 SwiftUI previews，因為它們太不可靠。相反地，他們改用範例應用程式，或避免某些做法，例如使用靜態函式庫或腳本建置階段，因為這些做法會導致該功能失效。

### 可合併函式庫 {#mergeable-libraries}

動態框架雖然更具彈性且更容易使用，但會對應用程式的啟動時間產生負面影響。另一方面，靜態函式庫啟動速度較快，但會影響編譯時間，且在使用上較為困難，特別是在複雜的圖形情境中。*如果能根據設定在兩者之間切換，豈不是太好了嗎？* 這想必是 Apple 決定開發可合併函式庫時的想法。但他們再次將更多建置時期的推論移至建置時期。試想，若需對相依性圖形進行推理，卻必須在建置時期根據某些目標中的建置設定來解析目標的靜態或動態性質，那會是多麼困難。要在確保 SwiftUI previews 等功能不會失效的同時，讓這種做法可靠運作，祝你好運。

**許多使用者來到 Tuist 希望使用可合併函式庫，而我們的答案始終如一：你不需要這麼做。** 你可以在專案生成時期控制目標的靜態或動態性質，從而產生一個在編譯前就已確知圖形的專案。無需在建置時期解析任何變數。

```bash
# The value of TUIST_DYNAMIC can be read from the project {#the-value-of-tuist_dynamic-can-be-read-from-the-project}
# to set the product as static or dynamic based on the value.
TUIST_DYNAMIC=1 tuist generate
```

## 明確、明確、再明確 {#explicit-explicit-and-explicit}

如果有一個重要的不成文原則，是我們建議每位希望透過 Xcode 擴展開發規模的開發者或組織採行的，那就是擁抱明確性。若使用原始的 Xcode 專案難以管理明確性，則應考慮其他方案，例如 [Tuist](https://tuist.dev) 或 [Bazel](https://bazel.build)。**唯有如此，才能實現可靠性、可預測性與最佳化。**

## 未來 {#future}

Apple 是否會採取措施防止上述所有問題，目前尚不清楚。他們持續在 Xcode 和 Swift Package Manager 中做出的決策，並未顯示出他們有此意圖。一旦你允許隱含設定成為有效狀態，**就很難在不引入破壞性變更的情況下改變現狀。** 回到基本原則並重新思考工具的設計，可能會導致許多多年來意外編譯成功的 Xcode 專案失效。想像一下，若發生這種情況，社群將會掀起多大的波瀾。

Apple 陷入了某種雞生蛋、蛋生雞的困境。便利性有助於開發者快速入門並為其生態系統建構更多應用程式。但他們為了在大規模下提供便利體驗所做的決策，卻使得他們難以確保某些 Xcode 功能能可靠運作。

由於未來充滿不確定性，我們努力**盡可能貼近產業標準與 Xcode 專案**。我們防止上述問題，並運用我們的知識提供更佳的開發者體驗。理想情況下，我們本不必訴諸專案生成來達成此目標，但 Xcode 和 Swift Package Manager 缺乏擴充性，使其成為唯一可行的選項。這也是一個安全的選項，因為他們必須先破壞 Xcode 專案，才會破壞 Tuist 專案。

理想情況下，**建置系統應更具擴充性**，但讓外掛程式／擴充功能與充滿隱含性的世界互動，難道不是個壞主意嗎？這似乎並非良策。因此，我們似乎需要像 Tuist 或 [Bazel](https://bazel.build) 這樣的外部工具來提供更佳的開發者體驗。或者，Apple 也許會給我們驚喜，讓 Xcode 更具擴充性與明確性……

在那之前，你必須選擇是要擁抱 Xcode 的便利性並承擔隨之而來的技術債，還是信任我們在這段旅程中提供更佳的開發者體驗。我們不會讓你失望。
