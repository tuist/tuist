---
{
  "title": "合成檔案",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "了解 Tuist 專案中的合成檔案。"
}
---
# 合成檔案 {#synthesized-files}

Tuist 可以在生成階段產生檔案與程式碼，讓管理與使用 Xcode 專案更方便。本頁會介紹這項功能，以及如何在你的專案中使用。

## 目標資源 {#target-resources}

Xcode 專案支援將資源加入目標。不過，這會為團隊帶來一些挑戰，特別是在模組化專案中，原始碼與資源經常需要搬移：

- **執行階段存取不一致**：資源最終放在哪裡、以及如何存取，取決於目標的產品類型。例如，如果你的目標代表應用程式，資源會被複製到應用程式 bundle。這會導致存取資源的程式碼對 bundle 結構作出假設，並不理想，因為這會讓程式碼更難理解，也讓資源更难搬移。
- **不支援資源的產品類型**：有些產品類型（例如靜態函式庫）並非 bundle，因此不支援資源。因此，你只能改用其他產品類型（例如 framework），但這可能會為你的專案或應用程式帶來額外負擔。例如，靜態 framework 會以靜態方式連結至最終產品，並且需要額外的建置階段才能只把資源複製到最終產品。至於動態 framework，Xcode 會把二進位檔與資源都複製到最終產品，但由於 framework 需要在執行階段動態載入，會增加應用程式的啟動時間。
- **容易出現執行階段錯誤**：資源以名稱與副檔名（字串）來識別。因此，只要其中任何一項打錯字，在嘗試存取資源時就會引發執行階段錯誤。這並不理想，因為編譯時期無法偵測，可能在發行版本中導致崩潰。

Tuist 透過**合成統一的介面來存取 bundle 與資源**，抽象化實作細節，從而解決上述問題。

> [!WARNING]
> **建議採用**
>
> 雖然並非必須透過 Tuist 合成的介面來存取資源，但我們建議這樣做，因為這會讓程式碼更易於理解，也方便搬移資源。


## 資源 {#resources}

Tuist 提供介面，讓你在 Swift 中宣告如 `Info.plist` 或 entitlements 等檔案的內容。這有助於確保跨目標與專案的一致性，並利用編譯器在編譯時期捕捉問題。你也可以自行設計抽象層來建模內容，並在目標與專案之間共用。

當你的專案被生成時，Tuist 會合成這些檔案的內容，並將它們寫入相對於定義它們的專案所在目錄的 `Derived` 目錄。

> [!TIP]
> **將 Derived 目錄加入 .gitignore**
>
> 我們建議將 `Derived` 目錄加入你專案的 `.gitignore` 檔案。


## Bundle 存取器 {#bundle-accessors}

Tuist 會合成一個介面，用來存取包含目標資源的 bundle。

### Swift {#swift}

目標會包含一個 `Bundle` 類型的擴充，用於公開該 bundle：

```swift
let bundle = Bundle.module
```

### Objective-C {#objectivec}

在 Objective-C 中，你會取得一個 `{Target}Resources` 介面來存取 bundle：

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

> [!WARNING]
> **內部目標的限制**
>
> 目前，Tuist 不會為僅包含 Objective-C 原始碼的內部目標生成資源 bundle 存取器。這是已知限制，追蹤於 [issue #6456](https://github.com/tuist/tuist/issues/6456)。


> [!TIP]
> **透過 bundle 讓函式庫支援資源**
>
> 如果某個目標的產品類型（例如函式庫）不支援資源，Tuist 會將資源放入產品類型為 `bundle` 的目標中，確保它們最終出現在最終產品裡，並且介面指向正確的 bundle。這些合成的 bundle 會自動加上 `tuist:synthesized` 標籤，並繼承父目標的所有標籤，讓你能在 <.localized_link href="/guides/features/projects/metadata-tags#system-tags">快取設定檔</.localized_link>中針對它們進行設定。


## 資源存取器 {#resource-accessors}

資源以字串形式的名稱與副檔名來識別。這並不理想，因為編譯時期無法偵測，可能在發行版本中導致崩潰。為避免此情況，Tuist 在建置生成流程中整合了 [SwiftGen](https://github.com/SwiftGen/SwiftGen)，以合成存取資源的介面。藉此，你可以放心地存取資源，並依靠編譯器捕捉任何問題。

Tuist 預設包含 [範本](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator/Templates)，用於為下列資源類型合成存取器：

| 資源類型 | 合成檔案 |
| --- | ---- |
| 圖片與顏色 | `Assets+{Target}.swift` |
| 字串 | `Strings+{Target}.swift` |
| Plist | `{NameOfPlist}.swift` |
| 字型 | `Fonts+{Target}.swift` |
| 檔案 | `Files+{Target}.swift` |

> 注意：你可以透過將 `disableSynthesizedResourceAccessors` 選項傳入專案選項，以每個專案為單位停用資源存取器的合成功能。

### 自訂範本 {#custom-templates}

如果你想提供自己的範本來為其他資源類型合成存取器（必須由 [SwiftGen](https://github.com/SwiftGen/SwiftGen) 支援），你可以在 `Tuist/ResourceSynthesizers/{name}.stencil` 建立它們，其中名稱是資源的 camelCase 版本。

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

如果你想設定要為哪些資源類型合成存取器，可以使用 `Project.resourceSynthesizers` 屬性並傳入你想使用的資源合成器清單：

```swift
let project = Project(name: "App", resourceSynthesizers: [.strings(), .fonts()])
```

> [!NOTE]
> **參考**
>
> 你可以查看 [這個範例](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_ios_app_with_templates)，了解如何使用自訂範本來為資源合成存取器。
