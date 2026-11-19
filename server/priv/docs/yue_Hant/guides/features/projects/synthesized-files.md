---
{
  "title": "合成檔案",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "了解 Tuist 專案中的合成檔案。"
}
---
# 合成檔案 {#synthesized-files}

Tuist 可以在生成時產生檔案和程式碼，方便管理和處理 Xcode 專案。本頁將介紹此功能，以及如何在你的專案中使用它。

## Target 資源 {#target-resources}

Xcode 專案支援為 target 加入資源。不過，這會為團隊帶來一些挑戰，特別是在模組化專案中，原始碼和資源經常需要移動：

- **執行階段存取不一致**：資源在最終產品中的位置以及存取方式取決於 target 的產品類型。例如，如果你的 target 代表應用程式，資源會被複製到應用程式 bundle。這導致存取資源的程式碼必須對 bundle 結構作出假設，並不理想，因為這令程式碼更難理解，亦令資源難以移動。
- **不支援資源的產品類型**：某些產品類型（例如靜態函式庫）並非 bundle，因此不支援資源。因此，你必須改用其他產品類型（例如 framework），但這可能會為專案或應用程式帶來額外負擔。例如，靜態 framework 會以靜態方式連結至最終產品，並需要額外的 build phase 來僅將資源複製到最終產品。而動態 framework 則會讓 Xcode 將二進位檔和資源都複製到最終產品，但由於 framework 需要動態載入，會增加應用程式的啟動時間。
- **容易出現執行階段錯誤**：資源透過名稱和副檔名（字串）來識別。因此，任何拼寫錯誤都會在嘗試存取資源時導致執行階段錯誤。這並不理想，因為這些錯誤不會在編譯時被捕捉，可能導致正式版應用程式崩潰。

Tuist 透過**合成統一的介面來存取 bundle 和資源**，抽象化實作細節，從而解決上述問題。

> [!WARNING]
> **建議**
>
> 雖然透過 Tuist 合成的介面存取資源並非強制，但我們建議這樣做，因為這令程式碼更易理解，亦令資源更易移動。


## 資源 {#resources}

Tuist 提供介面，讓你在 Swift 中宣告如 `Info.plist` 或 entitlements 等檔案的內容。這有助於確保不同 target 和專案之間的一致性，並利用編譯器在編譯時捕捉問題。你也可以自行設計抽象層來建模內容，並在多個 target 和專案之間共用。

當你的專案生成時，Tuist 會合成這些檔案的內容，並將它們寫入相對於定義該專案之目錄的 `Derived` 目錄中。

> [!TIP]
> **將 Derived 目錄加入 .gitignore**
>
> 我們建議將 `Derived` 目錄加入專案的 `.gitignore` 檔案。


## Bundle 存取器 {#bundle-accessors}

Tuist 會合成一個介面，用於存取包含 target 資源的 bundle。

### Swift {#swift}

target 會包含 `Bundle` 類型的擴充功能，用以公開 bundle：

```swift
let bundle = Bundle.module
```

### Objective-C {#objectivec}

在 Objective-C 中，你會獲得一個 `{Target}Resources` 介面來存取 bundle：

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

> [!WARNING]
> **內部 target 的限制**
>
> 目前，Tuist 不會為僅包含 Objective-C 原始碼的內部 target 生成資源 bundle 存取器。這是一個已知限制，已在 [issue #6456](https://github.com/tuist/tuist/issues/6456) 中追蹤。


> [!TIP]
> **透過 bundle 在函式庫中支援資源**
>
> 如果某個 target 產品（例如函式庫）不支援資源，Tuist 會將資源納入產品類型為 `bundle` 的 target 中，確保它們出現在最終產品內，且介面指向正確的 bundle。這些合成的 bundle 會自動標記為 `tuist:synthesized`，並繼承其父 target 的所有標籤，讓你能在 <.localized_link href="/guides/features/projects/metadata-tags#system-tags">快取設定檔</.localized_link> 中針對它們進行設定。


## 資源存取器 {#resource-accessors}

資源透過名稱和副檔名（字串）來識別。這並不理想，因為這些錯誤不會在編譯時被捕捉，可能導致正式版應用程式崩潰。為防止此情況，Tuist 將 [SwiftGen](https://github.com/SwiftGen/SwiftGen) 整合到專案生成流程中，以合成存取資源的介面。藉此，你可以放心地存取資源，並利用編譯器捕捉任何問題。

Tuist 預設包含 [範本](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator/Templates)，用於為以下資源類型合成存取器：

| 資源類型 | 合成檔案 |
| --- | ---- |
| 圖片和顏色 | `Assets+{Target}.swift` |
| 字串 | `Strings+{Target}.swift` |
| Plist | `{NameOfPlist}.swift` |
| 字型 | `Fonts+{Target}.swift` |
| 檔案 | `Files+{Target}.swift` |

> 注意：你可以透過將 `disableSynthesizedResourceAccessors` 選項傳遞給專案選項，以每個專案為基礎停用資源存取器的合成功能。

### 自訂範本 {#custom-templates}

如果你想提供自己的範本來為其他資源類型合成存取器（必須由 [SwiftGen](https://github.com/SwiftGen/SwiftGen) 支援），你可以在 `Tuist/ResourceSynthesizers/{name}.stencil` 建立它們，其中名稱是資源的 camel-case 版本。

| 資源 | 範本名稱 |
| --- | --- |
| 字串 | `Strings.stencil` |
| 資源 | `Assets.stencil` |
| Plist | `Plists.stencil` |
| 字型 | `Fonts.stencil` |
| CoreData | `CoreData.stencil` |
| Interface Builder | `InterfaceBuilder.stencil` |
| JSON | `JSON.stencil` |
| YAML | `YAML.stencil` |
| 檔案 | `Files.stencil` |

如果你想設定要為哪些資源類型合成存取器，可以使用 `Project.resourceSynthesizers` 屬性，並傳入你想使用的資源合成器清單：

```swift
let project = Project(name: "App", resourceSynthesizers: [.strings(), .fonts()])
```

> [!NOTE]
> **參考**
>
> 你可以查看 [此範例](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_ios_app_with_templates)，了解如何使用自訂範本來合成資源存取器。
