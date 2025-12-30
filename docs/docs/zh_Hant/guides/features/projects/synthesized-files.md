---
{
  "title": "Synthesized files",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about synthesized files in Tuist projects."
}
---
# 合成檔案{#synthesized-files}

Tuist 可以在生成時產生檔案和程式碼，為管理和使用 Xcode 專案帶來一些便利。在本頁中，您將學習到此功能，以及如何在您的專案中使用它。

## 目標資源{#target-resources}

Xcode 專案支援將資源新增至目標。但是，它們也為團隊帶來了一些挑戰，特別是在處理來源和資源經常被移動的模組化專案時：

- **不一致的運行時存取** ：資源在最終產品中的最終位置以及存取方式取決於目標產品。例如，如果您的目標是應用程式，資源會複製到應用程式
  bundle。這會導致存取資源的程式碼需要假設 bundle 的結構，這並不理想，因為這會使程式碼更難推理，資源也會隨處移動。
- **不支援資源的產品** ：有些產品，例如靜態函式庫，不是
  bundle，因此不支援資源。因此，您必須使用不同的產品類型，例如框架，這可能會增加專案或應用程式的開銷。例如，靜態框架會靜態連結到最終產品，而建立階段只需要將資源複製到最終產品。或是動態框架，Xcode
  會同時複製二進位檔和資源到最終產品，但會增加您應用程式的啟動時間，因為框架需要動態載入。
- **容易發生執行時錯誤**
  ：資源是以其名稱和副檔名（字串）來識別的。因此，在嘗試存取資源時，其中任何一個字錯都會導致執行時錯誤。這並不理想，因為它無法在編譯時捕捉到，可能會導致發行時當機。

Tuist 透過**綜合了一個統一的介面來存取 bundle 和資源** ，抽象出實作的細節，從而解決了上述問題。

::: warning RECOMMENDED
<!-- -->
儘管透過 Tuist 綜合介面存取資源不是強制性的，但我們仍建議這樣做，因為這樣會讓程式碼更容易推理，也讓資源更容易移動。
<!-- -->
:::

## 資源{#resources}

Tuist 提供介面來宣告檔案內容，例如`Info.plist` 或 Swift 中的
entitlements。這對於確保跨目標和專案的一致性非常有用，並可利用編譯器在編譯時捕捉問題。您也可以提出自己的抽象來為內容建模，並跨目標和專案分享。

當您的專案產生時，Tuist 將合成這些檔案的內容，並將它們寫入`Derived` 目錄，相對於包含定義這些檔案的專案的目錄。

::: tip GITIGNORE THE DERIVED DIRECTORY
<!-- -->
我們建議將`Derived` 目錄加入專案的`.gitignore` 檔案。
<!-- -->
:::

## 捆綁存取器{#bundle-accessors}

Tuist 綜合了一個介面來存取包含目標資源的 bundle。

### 雨燕{#swift}

目標將包含`Bundle` 類型的延伸，以揭露 bundle：

```swift
let bundle = Bundle.module
```

### Objective-C{#objectivec}

在 Objective-C 中，您會得到一個介面`{Target}Resources` 來存取 bundle：

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

::: warning LIMITATION WITH INTERNAL TARGETS
<!-- -->
目前，Tuist 不會為僅包含 Objective-C 原始碼的內部目標產生資源包存取器。這是 [issue
#6456](https://github.com/tuist/tuist/issues/6456)中追蹤到的已知限制。
<!-- -->
:::

::: tip SUPPORTING RESOURCES IN LIBRARIES THROUGH BUNDLES
<!-- -->
如果目標產品 (例如函式庫) 不支援資源，Tuist 會將資源包含在產品類型`bundle` 的目標中，以確保它最終出現在最終產品中，並且介面指向正確的
bundle。
<!-- -->
:::

## 資源存取器{#resource-accessors}

資源使用字串來識別其名稱和副檔名。這並不理想，因為在編譯時無法捕捉，可能會導致發行時當機。為了避免這種情況，Tuist 將
[SwiftGen](https://github.com/SwiftGen/SwiftGen)
整合到專案產生流程中，以合成存取資源的介面。有了這個功能，您就可以放心地存取資源，並利用編譯器來捕捉任何問題。

Tuist 預設包含
[templates](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator/Templates)
來合成下列資源類型的存取器：

| 資源類型  | 合成檔案                     |
| ----- | ------------------------ |
| 圖片和顏色 | `Assets+{Target}.swift`  |
| 弦線    | `Strings+{Target}.swift` |
| 清單    | `{NameOfPlist}.swift`    |
| 字體    | `Fonts+{Target}.swift`   |
| 檔案    | `Files+{Target}.swift`   |

> 注意：您可以在專案選項中傳入`disableSynthesizedResourceAccessors` 選項，在每個專案的基礎上停用資源存取器的合成。

#### 自訂範本{#custom-templates}

如果您想要提供自己的範本來合成其他資源類型的存取器（必須由 [SwiftGen](https://github.com/SwiftGen/SwiftGen)
所支援），您可以在`Tuist/ResourceSynthesizers/{name}.stencil` 建立這些範本，其中名稱是資源的駝峰大寫版本。

| 資源               | 範本名稱                       |
| ---------------- | -------------------------- |
| 字符串              | `Strings.stencil`          |
| 資產               | `Assets.stencil`           |
| 列表               | `Plists.stencil`           |
| 字體               | `字體模板`                     |
| 核心資料             | `CoreData.stencil`         |
| interfaceBuilder | `InterfaceBuilder.stencil` |
| json             | `JSON.stencil`             |
| yaml             | `YAML.stencil`             |
| 檔案               | `檔案.樣板`                    |

如果您要設定要合成存取器的資源類型清單，可以使用`Project.resourceSynthesizers` 屬性傳入您要使用的資源合成器清單：

```swift
let project = Project(resourceSynthesizers: [.string(), .fonts()])
```

::: info REFERENCE
<!-- -->
您可以查看 [this
fixture](https://github.com/tuist/tuist/tree/main/cli/Fixtures/ios_app_with_templates)
以瞭解如何使用自訂範本來合成資源存取器的範例。
<!-- -->
:::
