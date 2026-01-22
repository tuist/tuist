---
{
  "title": "The cost of convenience",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the cost of convenience in Xcode and how Tuist helps you prevent the issues that come with it."
}
---
# 便利的代價{#the-cost-of-convenience}

設計一款能滿足從小型到大型專案需求（**）的程式碼編輯器（**
）是項艱鉅任務。多數工具透過分層架構與擴充性來解決此問題：底層採用貼近底層建置系統的低階設計，頂層則提供高階抽象化介面，雖便利但靈活性較低。如此設計使簡單之事易如反掌，其他需求亦皆可實現。

然而，**[Apple](https://www.apple.com) 在 Xcode**
中選擇了截然不同的做法。原因雖不明朗，但很可能優化大型專案的挑戰性從來就不是他們的目標。他們過度投資於小型專案的便利性，提供極少彈性，並將工具與底層建置系統緊密結合。
為達成便利性，他們提供可輕鬆替換的合理預設值，並加入大量隱含的建置時解析行為——這些正是大規模專案中諸多問題的根源。

## 明確性與規模{#explicitness-and-scale}

大規模作業時，**的明確性至關重要** 。此特性使建置系統能預先分析理解專案結構與依賴關係，執行其他方式無法實現的優化。
同樣的明確性對於確保編輯器功能（如[SwiftUI
預覽](https://developer.apple.com/documentation/swiftui/previews-in-xcode)或[Swift
巨集](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)）能穩定且可預測地運作至關重要。由於
Xcode 與 Xcode 專案為追求便利性而採用隱含性作為有效設計選擇（此原則亦為 Swift Package Manager 所繼承），Xcode
的使用難點同樣存在於 Swift Package Manager 中。

::: info THE ROLE OF TUIST
<!-- -->
我們可將 Tuist 的角色歸納為：透過防止隱式定義專案並強化顯式性，提供更優質的開發者體驗（例如驗證機制、效能優化）。諸如
[Bazel](https://bazel.build) 之類的工具更進一步將此概念延伸至建置系統層級。
<!-- -->
:::

這是社群中鮮少討論卻至關重要的議題。 在開發 Tuist 的過程中，我們發現許多組織與開發者認為當前面臨的挑戰將由 [Swift Package
Manager](https://www.swift.org/documentation/package-manager/)
解決，但他們未意識到：由於其建構於相同原則之上，即便能緩解眾所周知的 Git 衝突問題，卻在其他層面削弱開發者體驗，並持續使專案無法進行最佳化。

在以下章節中，我們將透過實際案例探討隱含性如何影響開發者體驗與專案健康度。此清單雖非詳盡無遺，但應能讓您充分理解在處理 Xcode 專案或 Swift
套件時可能面臨的挑戰。

## 便利性反而成為阻礙{#convenience-getting-in-your-way}

### 共享建置產品目錄{#shared-built-products-directory}

Xcode 為每個產品在衍生資料目錄內建立專屬目錄。 該目錄內儲存建置產物，例如編譯後的二進位檔、dSYM
檔案及記錄檔。由於專案所有產品皆存放於同個目錄（預設對其他目標可見且可連結），**可能導致目標間產生隱含依賴關係。**
當目標數量較少時此問題尚可接受，但隨著專案規模擴大，可能引發難以除錯的建置失敗狀況。

此設計決策的後果是，許多專案會意外地以未明確定義的圖結構進行編譯。

::: tip TUIST DETECTION OF IMPLICIT DEPENDENCIES
<!-- -->
Tuist 提供
<LocalizedLink href="/guides/features/inspect/implicit-dependencies">command</LocalizedLink>
指令用於偵測隱含依賴關係。您可運用此指令在 CI 環境中驗證所有依賴關係是否皆為顯式宣告。
<!-- -->
:::

### 找出方案中的隱含依賴關係{#find-implicit-dependencies-in-schemes}

隨著專案規模擴大，在 Xcode 中定義與維護依賴關係圖會變得更困難。 其困難在於：這些圖表以建置階段與建置設定的形式，編碼於` 的 .pbxproj 檔案（`
）中；缺乏可視化操作圖表的工具；且圖表變更（例如新增動態預編譯框架）可能需上游配置調整（例如新增建置階段以將框架複製至套件）。

蘋果公司曾決定，與其將圖模型演進為更易管理的形態，不如在建置時新增選項來解析隱含依賴關係。此設計選擇再度引發爭議，因可能導致建置時間變慢或產生不可預測的建置結果。舉例而言，某次建置可能因導出資料中的狀態（該狀態充當單例(https://en.wikipedia.org/wiki/Singleton_pattern)）而在本地通過，卻因狀態差異導致在持續整合環境中編譯失敗。

::: tip
<!-- -->
我們建議在專案設定中停用此功能，改用如 Tuist 等工具來簡化依賴關係圖的管理。
<!-- -->
:::

### SwiftUI 預覽與靜態函式庫/框架{#swiftui-previews-and-static-librariesframeworks}

某些編輯器功能（如 SwiftUI 預覽或 Swift
宏）需從編輯檔案編譯依賴圖。此類編輯器整合要求建置系統解析所有隱含依賴關係，並輸出正確的建置產物以支援功能運作。正如您所知，**圖結構越隱含，建置系統的解析任務就越艱鉅**
，因此這些功能常無法穩定運作實屬必然。 我們經常聽開發者反映，他們早已因預覽功能過於不可靠而停止使用 SwiftUI
預覽。取而代之的是，他們要麼使用範例應用程式，要麼刻意避開某些操作（例如使用靜態函式庫或腳本建構階段），因為這些操作會導致功能失效。

### 可合併的函式庫{#mergeable-libraries}

動態框架雖更具彈性且易於操作，卻會影響應用程式啟動時間。反之，靜態函式庫啟動速度較快，但會增加編譯時間且操作較為困難，尤其在複雜圖形情境下。*若能依據設定在兩者間切換豈不完美？*
這正是蘋果公司著手開發可合併函式庫時的考量。
然而他們再次將更多建構時推論移至建構階段。試想當依賴圖的解析需基於某些目標中的建構設定，在建構時動態決定目標採用靜態或動態特性時，要確保 SwiftUI
預覽等功能不被破壞，同時維持可靠運作——這可真是個挑戰。

**許多使用者來到 Tuist 詢問能否使用可合併函式庫，我們的回答始終如一：您無需如此。**
您可在生成時控制目標的靜態或動態特性，從而建立在編譯前即可知曉圖結構的專案。建置時無需解析任何變數。

```bash
# The value of TUIST_DYNAMIC can be read from the project {#the-value-of-tuist_dynamic-can-be-read-from-the-project}
# to set the product as static or dynamic based on the value. {#to-set-the-product-as-static-or-dynamic-based-on-the-value}
TUIST_DYNAMIC=1 tuist generate
```

## 明確、明確、再明確{#explicit-explicit-and-explicit}

若要向所有希望透過 Xcode 實現可擴展開發的開發者或組織傳達一項重要的非成文原則，那就是他們應秉持明確性。若原始 Xcode
專案難以管理明確性，則應考慮採用其他方案，無論是 [Tuist](https://tuist.io) 或
[Bazel](https://bazel.build)。**唯有如此，可靠性、可預測性與優化才得以實現。**

## 未來{#future}

蘋果是否會採取措施避免上述所有問題尚屬未知。其持續嵌入 Xcode 與 Swift Package Manager
的決策方向，似乎並未顯示此意圖。一旦允許隱含配置作為有效狀態，**便難以在不引發相容性變更的前提下進行調整。**
若回歸基本原則重新設計工具架構，恐將導致多年來意外編譯成功的眾多 Xcode 專案失效。試想若此情況發生，社群將掀起何等軒然大波。

蘋果正面臨雞生蛋、蛋生雞的困境。便利性雖能協助開發者快速上手並為其生態系統打造更多應用程式，但當便利性擴展至如此規模時，其決策反而使某些 Xcode
功能難以確保穩定運作。

由於未來充滿變數，我們致力於**盡可能貼近產業標準與Xcode專案規範** 。我們避免上述問題，並運用既有知識提供更優質的開發者體驗。
理想情況下我們不該依賴專案生成機制，但 Xcode 與 Swift Package Manager
的擴充性不足，使此成為唯一可行方案。此舉亦屬安全策略，因開發者必須破壞 Xcode 專案結構，才能破壞 Tuist 專案。

理想情況下，**構建系統本應具備更高擴展性** ，但若插件/擴展需與隱含機制共存，豈非弊大於利？此構想似乎不甚妥當。因此我們可能需要借助 Tuist 或
[Bazel](https://bazel.build) 等外部工具來提升開發體驗。當然，蘋果或許會帶來驚喜，讓 Xcode 變得更具擴展性與明確性⋯⋯

在此之前，您必須抉擇：是選擇擁抱 Xcode 的便利性並承擔隨之而來的技術負債，抑或信任我們在這段旅程中為您打造更優質的開發體驗。我們絕不讓您失望。
