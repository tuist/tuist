---
{
  "title": "合成檔案",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "了解 Tuist 專案中的合成檔案。"
}
---
# 合成檔案 {#synthesized-files}

Tuist 可以在生成時產生檔案和程式碼，讓管理和使用 Xcode 專案更方便。本頁將介紹此功能，以及如何在你的專案中使用。

## 目標資源 {#target-resources}

Xcode 專案支援向目標加入資源。不過，這會為團隊帶來一些挑戰，特別是在處理模組化專案時，因為來源與資源經常被移動：

- **執行階段存取不一致**：資源在最終產品中的位置及存取方式取決於目標產品類型。例如，如果你的目標代表應用程式，資源會被複製到應用程式套件中。這會導致存取資源的程式碼對套件結構作出假設，並不理想，因為這令程式碼更難理解，亦令資源難以移動。
- **不支援資源的產品**：某些產品（例如靜態函式庫）並非套件，因此不支援資源。為此，你必須改用其他產品類型（例如框架），但這可能為你的專案或應用程式帶來額外負擔。例如，靜態框架會以靜態方式連結至最終產品，並需要一個建置階段來只將資源複製到最終產品。或者使用動態框架，Xcode 會將二進位檔和資源都複製到最終產品，但由於框架需要動態載入，會增加應用程式的啟動時間。
- **容易出現執行階段錯誤**：資源透過名稱和副檔名（字串）來識別。因此，任何拼寫錯誤都會在嘗試存取資源時導致執行階段錯誤。這並不理想，因為編譯時期無法偵測到，可能在發行版本中引發崩潰。

Tuist 透過**合成統一介面來存取套件和資源**，抽象化實作細節，從而解決上述問題。

> [!WARNING]
> **建議**
>
> 雖然並非必須透過 Tuist 合成的介面來存取資源，但我們建議這樣做，因為這令程式碼更易理解，亦令資源更易移動。


## 資源 {#resources}

Tuist 提供介面，讓你在 Swift 中宣告如 `Info.plist` 或權限等檔案的內容。這有助於確保跨目標和專案的一致性，並利用編譯器在編譯時期捕捉問題。你也可以建立自己的抽象層來建模內容，並在目標和專案之間共用。

當你的專案生成時，Tuist 會合成這些檔案的內容，並將它們寫入相對於定義它們的專案目錄的 `Derived` 目錄中。

> [!TIP]
> **將 Derived 目錄加入 .gitignore**
>
> 我們建議將 `Derived` 目錄加入你專案的 `.gitignore` 檔案中。


## 套件存取器 {#bundle-accessors}

Tuist 會合成一個介面，用以存取包含目標資源的套件。

### Swift {#swift}

目標會包含一個 `Bundle` 類型的擴充功能，用於公開套件：

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
> 目前，Tuist 不會為僅包含 Objective-C 來源的內部目標生成資源套件存取器。這是已知限制，可在 [issue #6456](https://github.com/tuist/tuist/issues/6456) 中追蹤。


> [!TIP]
> **透過套件在函式庫中支援資源**
>
> 如果目標產品（例如函式庫）不支援資源，Tuist 會將資源包含在產品類型為 `bundle` 的目標中，確保其出現在最終產品中，且介面指向正確的套件。這些合成的套件會自動標記為 `tuist:synthesized`，並繼承其父目標的所有標籤，讓你能在 <.localized_link href="/guides/features/projects/metadata-tags#system-tags">快取設定檔</.localized_link>中針對它們。


## 資源存取器 {#resource-accessors}

資源透過名稱和副檔名（字串）來識別。這並不理想，因為編譯時期無法偵測到，可能在發行版本中引發崩潰。為防止此情況，Tuist 將 [SwiftGen](https://github.com/SwiftGen/SwiftGen) 整合到專案生成過程中，以合成存取資源的介面。藉此，你可以放心地存取資源，並利用編譯器捕捉任何問題。

Tuist 預設包含 [範本](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator/Templates)，用於為以下資源類型合成存取器：

| 資源類型 | 合成檔案 |
| --- | ---- |
| 圖片和顏色 | `Assets+{Target}.swift` |
| 字串 | `Strings+{Target}.swift` |
| Plist | `{NameOfPlist}.swift` |
| 字型 | `Fonts+{Target}.swift` |
| 檔案 | `Files+{Target}.swift` |

> 注意：你可以透過將 `disableSynthesizedResourceAccessors` 選項傳遞給專案選項，以每個專案為基礎停用資源存取器的生成功能。

#### 自訂範本 {#custom-templates}

如果你想提供自己的範本來為其他資源類型合成存取器（必須由 [SwiftGen](https://github.com/SwiftGen/SwiftGen) 支援），你可以在 `Tuist/ResourceSynthesizers/{name}.stencil` 建立它們，其中名稱是資源的駝峰式大小寫版本。

| 資源 | 範本名稱 |
| --- | --- |
| 字串 | `Strings.stencil` |
| 資產 | `Assets.stencil` |
| Plist | `Plists.stencil` |
| 字型 | `Fonts.stencil` |
| CoreData | `CoreData.stencil` |
| InterfaceBuilder | `InterfaceBuilder.stencil` |
| JSON | `JSON.stencil` |
| YAML | `YAML.stencil` |
| 檔案 | `Files.stencil` |

如果你想設定要為哪些資源類型合成存取器，可以使用 `Project.resourceSynthesizers` 屬性，並傳入你想使用的資源合成器清單：

```swift
let project = Project(resourceSynthesizers: [.string(), .fonts()])
```

> [!NOTE]
> **參考**
>
> 你可以查看 [此範例](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_ios_app_with_templates)，了解如何使用自訂範本來合成資源存取器。
