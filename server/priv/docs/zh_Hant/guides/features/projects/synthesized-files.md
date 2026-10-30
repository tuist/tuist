---
{
  "title": "合成檔案",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解 Tuist 專案中的合成檔案。"
}
---
# 合成檔案 {#synthesized-files}

Tuist 能在專案生成階段產生檔案與程式碼，讓管理與使用 Xcode 專案更便利。本頁將說明這項功能，以及如何在你的專案中使用。

## 目標資源 {#target-resources}

Xcode 專案支援為目標加入資源。然而，這會為團隊帶來一些挑戰，特別是在模組化專案中，原始碼與資源經常需要移動時：

- **執行階段存取不一致**：資源在最終產品中的位置與存取方式取決於目標產品類型。例如，若你的目標代表應用程式，資源會被複製到應用程式套件中。這會導致存取資源的程式碼對套件結構做出假設，並不理想，因為這會讓程式碼更难理解，也讓資源更难移動。
- **不支援資源的產品類型**：某些產品類型（例如靜態函式庫）並非套件，因此不支援資源。因此，你必須改用其他產品類型（例如框架），但這可能為專案或應用程式帶來額外負擔。例如，靜態框架會以靜態方式連結至最終產品，且需要額外的建置階段才能將資源複製到最終產品。若是動態框架，Xcode 會將二進位檔與資源都複製到最終產品，但由於框架需動態載入，會增加應用程式的啟動時間。
- **容易發生執行階段錯誤**：資源透過名稱與副檔名（字串）識別。因此，任何拼寫錯誤都會在嘗試存取資源時導致執行階段錯誤。這並不理想，因為這些錯誤無法在建置時期被發現，可能在正式版中造成崩潰。

Tuist 透過**合成統一的介面來存取套件與資源**，抽象化實作細節，從而解決上述問題。

> [!WARNING]
> **建議做法**
>
> 雖然透過 Tuist 合成的介面存取資源並非強制，但我們建議採用，因為這能讓程式碼更易於理解，也更方便移動資源。


## 資源 {#resources}

Tuist 提供介面，讓你在 Swift 中宣告如 `Info.plist` 或權限清單等檔案的內容。這有助於確保跨目標與專案的一致性，並利用編譯器在建置時期捕捉問題。你也可以自行設計抽象層來建模內容，並在目標與專案之間共用。

當你的專案生成時，Tuist 會合成這些檔案的內容，並將它們寫入相對於定義該專案之目錄的 `Derived` 目錄中。

> [!TIP]
> **將 Derived 目錄加入 .gitignore**
>
> 我們建議將 `Derived` 目錄加入專案的 `.gitignore` 檔案中。


## 套件存取器 {#bundle-accessors}

Tuist 會合成一個介面，用於存取包含目標資源的套件。

### Swift {#swift}

目標會包含 `Bundle` 類型的擴充功能，用以暴露該套件：

```swift
let bundle = Bundle.module
```

### Objective-C {#objectivec}

在 Objective-C 中，你會獲得一個 `{Target}Resources` 介面來存取套件：

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

> [!WARNING]
> **內部目標的限制**
>
> 目前，Tuist 不會為僅包含 Objective-C 原始碼的內部目標生成資源套件存取器。此為已知限制，相關追蹤見 [issue #6456](https://github.com/tuist/tuist/issues/6456)。


> [!TIP]
> **透過套件在函式庫中支援資源**
>
> 若目標產品（例如函式庫）不支援資源，Tuist 會將資源放入產品類型為 `bundle` 的目標中，確保其出現在最終產品裡，且介面指向正確的套件。這些合成的套件會自動標記為 `tuist:synthesized`，並繼承父目標的所有標籤，讓你能在 <.localized_link href="/guides/features/projects/metadata-tags#system-tags">快取設定檔</.localized_link>中針對它們進行設定。


## 資源存取器 {#resource-accessors}

資源透過名稱與副檔名（字串）識別。這並不理想，因為這些錯誤無法在建置時期被發現，可能在正式版中造成崩潰。為避免此情況，Tuist 將 [SwiftGen](https://github.com/SwiftGen/SwiftGen) 整合進專案生成流程，以合成存取資源的介面。藉此，你可以放心地存取資源，並依靠編譯器捕捉任何問題。

Tuist 預設包含 [範本](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator/Templates)，用於為下列資源類型合成存取器：

| 資源類型 | 合成檔案 |
| --- | ---- |
| 圖片與顏色 | `Assets+{Target}.swift` |
| 字串 | `Strings+{Target}.swift` |
| 屬性清單 | `{NameOfPlist}.swift` |
| 字型 | `Fonts+{Target}.swift` |
| 檔案 | `Files+{Target}.swift` |

> 注意：你可以透過將 `disableSynthesizedResourceAccessors` 選項傳入專案選項，以專案為單位停用資源存取器的合成功能。

#### 自訂範本 {#custom-templates}

若想提供自己的範本來為其他資源類型合成存取器（必須由 [SwiftGen](https://github.com/SwiftGen/SwiftGen) 支援），你可以在 `Tuist/ResourceSynthesizers/{name}.stencil` 建立範本，其中名稱為資源的駝峰式命名。

| 資源 | 範本名稱 |
| --- | --- |
| 字串 | `Strings.stencil` |
| 資源 | `Assets.stencil` |
| 屬性清單 | `Plists.stencil` |
| 字型 | `Fonts.stencil` |
| Core Data | `CoreData.stencil` |
| Interface Builder | `InterfaceBuilder.stencil` |
| JSON | `JSON.stencil` |
| YAML | `YAML.stencil` |
| 檔案 | `Files.stencil` |

若要設定要為哪些資源類型合成存取器，你可以使用 `Project.resourceSynthesizers` 屬性並傳入你想使用的資源合成器清單：

```swift
let project = Project(resourceSynthesizers: [.string(), .fonts()])
```

> [!NOTE]
> **參考資料**
>
> 你可以查看 [此範例](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_ios_app_with_templates)，了解如何使用自訂範本來合成資源存取器。
