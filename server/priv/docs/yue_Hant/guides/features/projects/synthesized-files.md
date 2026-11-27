---
{
  "title": "合成檔案",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解 Tuist 專案中的合成檔案。"
}
---
# 合成檔案 {#synthesized-files}

Tuist 可以在生成階段產生檔案和程式碼，為管理和使用 Xcode 專案帶來便利。在本頁中，你將了解此功能以及如何在你的專案中使用它。

## 目標資源 {#target-resources}

Xcode 專案支援向目標加入資源。然而，這會為團隊帶來一些挑戰，特別是在處理模組化專案時，因為原始碼和資源經常會被移動：

- **執行階段存取不一致**：資源在最終產品中的位置以及存取方式取決於目標產品類型。例如，如果你的目標代表一個應用程式，資源會被複製到應用程式套件中。這導致存取資源的程式碼需要對套件結構作出假設，這並不理想，因為它使程式碼更難理解，也使資源更難移動。
- **不支援資源的產品類型**：某些產品類型（例如靜態函式庫）並非套件，因此不支援資源。因此，你必須改用其他產品類型，例如框架，但這可能會為你的專案或應用程式增加額外負擔。例如，靜態框架會以靜態方式連結到最終產品，並且需要一個建構階段來僅將資源複製到最終產品。或者動態框架，Xcode 會將二進位檔和資源都複製到最終產品中，但這會增加應用程式的啟動時間，因為框架需要動態載入。
- **容易發生執行階段錯誤**：資源透過名稱和副檔名（字串）來識別。因此，任何拼寫錯誤都會導致在嘗試存取資源時發生執行階段錯誤。這並不理想，因為這些錯誤無法在編譯時期被捕捉，可能會導致發佈版本當機。

Tuist 透過**合成統一的介面來存取套件和資源**，從而解決上述問題，並抽象化實作細節。

> [!WARNING]
> **建議做法**
>
> 雖然透過 Tuist 合成的介面存取資源並非強制要求，但我們建議這樣做，因為它使程式碼更易於理解，也使資源更易於移動。


## 資源 {#resources}

Tuist 提供介面，讓你在 Swift 中宣告檔案內容，例如 `Info.plist` 或權限設定。這有助於確保跨目標和專案的一致性，並利用編譯器在編譯時期捕捉問題。你也可以建立自己的抽象層來建模內容，並在目標和專案之間共用。

當你的專案生成時，Tuist 會合成這些檔案的內容，並將它們寫入相對於定義這些檔案的專案目錄的 `Derived` 目錄中。

> [!TIP]
> **將 Derived 目錄加入 .gitignore**
>
> 我們建議將 `Derived` 目錄加入你專案的 `.gitignore` 檔案中。


## 套件存取器 {#bundle-accessors}

Tuist 會合成一個介面，用於存取包含目標資源的套件。

### Swift {#swift}

目標會包含一個 `Bundle` 類型的擴充功能，用以公開該套件：

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
> 目前，Tuist 不會為僅包含 Objective-C 原始碼的內部目標生成資源套件存取器。這是一個已知的限制，追蹤於 [issue #6456](https://github.com/tuist/tuist/issues/6456)。


> [!TIP]
> **透過套件在函式庫中支援資源**
>
> 如果目標產品（例如函式庫）不支援資源，Tuist 會將資源包含在產品類型為 `bundle` 的目標中，確保它們最終出現在最終產品中，並且介面指向正確的套件。這些合成的套件會自動標記為 `tuist:synthesized`，並繼承其父目標的所有標籤，讓你能夠在 <.localized_link href="/guides/features/projects/metadata-tags#system-tags">快取設定檔</.localized_link> 中針對它們進行設定。


## 資源存取器 {#resource-accessors}

資源透過名稱和副檔名（字串）來識別。這並不理想，因為這些錯誤無法在編譯時期被捕捉，可能會導致發佈版本當機。為了防止這種情況，Tuist 將 [SwiftGen](https://github.com/SwiftGen/SwiftGen) 整合到專案生成過程中，以合成存取資源的介面。藉此，你可以放心地存取資源，並利用編譯器捕捉任何問題。

Tuist 預設包含 [範本](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator/Templates)，用於為以下資源類型合成存取器：

| 資源類型 | 合成檔案 |
| --- | ---- |
| 圖片和顏色 | `Assets+{Target}.swift` |
| 字串 | `Strings+{Target}.swift` |
| Plist 檔案 | `{NameOfPlist}.swift` |
| 字型 | `Fonts+{Target}.swift` |
| 檔案 | `Files+{Target}.swift` |

> 注意：你可以透過將 `disableSynthesizedResourceAccessors` 選項傳遞給專案選項，以每個專案為基礎停用資源存取器的生成功能。

### 自訂範本 {#custom-templates}

如果你想提供自己的範本來為其他資源類型合成存取器（必須由 [SwiftGen](https://github.com/SwiftGen/SwiftGen) 支援），你可以在 `Tuist/ResourceSynthesizers/{name}.stencil` 建立它們，其中名稱是資源的駝峰式命名版本。

| 資源 | 範本名稱 |
| --- | --- |
| 字串 | `Strings.stencil` |
| 資產 | `Assets.stencil` |
| Plist 檔案 | `Plists.stencil` |
| 字型 | `Fonts.stencil` |
| Core Data | `CoreData.stencil` |
| Interface Builder | `InterfaceBuilder.stencil` |
| JSON | `JSON.stencil` |
| YAML | `YAML.stencil` |
| 檔案 | `Files.stencil` |

如果你想設定要為哪些資源類型合成存取器，可以使用 `Project.resourceSynthesizers` 屬性並傳入你想使用的資源合成器清單：

```swift
let project = Project(name: "App", resourceSynthesizers: [.strings(), .fonts()])
```

> [!NOTE]
> **參考**
>
> 你可以查看 [此範例](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_ios_app_with_templates)，了解如何使用自訂範本來合成資源存取器。
