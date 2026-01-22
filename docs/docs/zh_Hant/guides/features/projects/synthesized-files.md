---
{
  "title": "Synthesized files",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about synthesized files in Tuist projects."
}
---
# 合成檔案{#synthesized-files}

Tuist 能在生成時自動產出檔案與程式碼，為管理與操作 Xcode 專案帶來便利。本頁將介紹此功能及其在專案中的應用方式。

## 目標資源{#target-resources}

Xcode 專案支援將資源新增至目標。然而，這為團隊帶來若干挑戰，尤其在處理模組化專案時，因原始碼與資源常需頻繁移動：

- **不一致的執行時存取**:
  資源在最終產品中的位置及存取方式取決於目標產品。例如，若目標為應用程式，資源將複製至應用程式套件。這導致存取資源的程式碼需預設套件結構，此做法並不理想，因其增加程式碼的邏輯推導難度，且使資源遷移更為複雜。
- **不支援資源的產品類型**:
  某些產品（如靜態函式庫）不屬於封裝套件，因此不支援資源管理。此時您必須改用其他產品類型（例如框架），這可能為專案或應用程式增加額外開銷。
  例如：靜態框架會以靜態連結方式整合至最終產品，需額外建立建置階段才能將資源複製至最終產品；動態框架則由 Xcode
  同時複製二進位檔與資源至最終產品，但因框架需動態載入，將增加應用程式啟動時間。
- **易引發執行時錯誤**:
  資源透過名稱與副檔名（字串）識別。因此，當嘗試存取資源時，任何字串的拼寫錯誤都將導致執行時錯誤。此機制並不理想，因為編譯階段無法偵測此類錯誤，可能導致正式版本發生崩潰。

Tuist 透過**合成統一介面來存取套件與資源** ，藉此解決上述問題，該介面抽象化了實作細節。

::: warning RECOMMENDED
<!-- -->
儘管透過 Tuist 合成介面存取資源並非強制要求，我們仍建議採用此方式，因其能使程式碼更易於理解，並提升資源調度的靈活性。
<!-- -->
:::

## 資源{#resources}

Tuist 提供介面來宣告檔案內容，例如 Swift 中的`Info.plist` 或
entitlements。此功能有助於確保跨目標與專案的一致性，並利用編譯器在編譯時偵測問題。您亦可自行設計抽象模型來建構內容，並在不同目標與專案間共享。

當專案生成時，Tuist 會整合這些檔案的內容，並將其寫入相對於定義專案所在目錄的「`」衍生目錄（路徑：` ）。

::: tip GITIGNORE THE DERIVED DIRECTORY
<!-- -->
建議將`Derived` 目錄加入專案的`.gitignore 檔案中。`
<!-- -->
:::

## 捆綁存取器{#bundle-accessors}

Tuist 合成一個介面，用於存取包含目標資源的資源包。

### Swift{#swift}

目標將包含`類型的Bundle擴展，該擴展會公開此Bundle：`

```swift
let bundle = Bundle.module
```

### Objective-C{#objectivec}

在 Objective-C 中，您將獲得以下介面存取資源包：`{Target}Resources`

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

::: warning LIMITATION WITH INTERNAL TARGETS
<!-- -->
目前 Tuist 不會為僅含 Objective-C 原始碼的內部目標產生資源包存取函式。此為已知限制，相關追蹤請參閱 [issue
#6456](https://github.com/tuist/tuist/issues/6456)。
<!-- -->
:::

::: tip SUPPORTING RESOURCES IN LIBRARIES THROUGH BUNDLES
<!-- -->
若目標產品（例如函式庫）不支援資源，Tuist 將把資源納入產品類型為`的目標中，並將資源打包至`
，確保資源最終進入產品且介面指向正確的打包檔。這些合成打包檔會自動標記為`tuist:synthesized` ，並繼承父目標的所有標籤，讓您能在
<LocalizedLink href="/guides/features/projects/metadata-tags#system-tags">快取設定檔</LocalizedLink>中針對它們進行設定。
<!-- -->
:::

## 資源存取器{#resource-accessors}

資源透過名稱與副檔名組成的字串進行識別。此方式並不理想，因其無法在編譯時被偵測，可能導致正式版本發生崩潰。為避免此問題，Tuist將[SwiftGen](https://github.com/SwiftGen/SwiftGen)整合至專案生成流程，以合成存取資源的介面。藉此機制，您可安心存取資源，同時利用編譯器偵測潛在問題。

Tuist 預設包含
[範本](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator/Templates)
以合成下列資源類型的存取器：

| 資源類型   | 合成檔案                 |
| ------ | -------------------- |
| 圖片與顏色  | `Assets+{目標} .swift` |
| 字串     | `字串+{目標語言}.swift`    |
| Plists | `{Plist名稱}.swift`    |
| 字型     | `字型+{目標語言}.swift`    |
| 檔案     | `檔案+{目標語言}.swift`    |

> 注意：您可透過在專案選項中傳遞 ``` `disableSynthesizedResourceAccessors` `` `
> 選項，以專案為單位停用資源存取器的合成功能。

#### 自訂範本{#custom-templates}

若需自訂模板以合成其他資源類型的存取器（該類別須獲[SwiftGen](https://github.com/SwiftGen/SwiftGen)支援），請於以下路徑建立模板：`Tuist/ResourceSynthesizers/{name}.stencil`
其中{name}應為資源名稱的駝峰式大小寫版本。

| 資源               | 範本名稱                       |
| ---------------- | -------------------------- |
| 字串               | `字串.模板`                    |
| 資產               | `Assets.stencil`           |
| plists           | `Plists.stencil`           |
| 字型               | `字體.模板`                    |
| 核心資料             | `CoreData.stencil`         |
| interfaceBuilder | `InterfaceBuilder.stencil` |
| json             | `JSON.stencil`             |
| yaml             | `YAML.stencil`             |
| 檔案               | `Files.stencil`            |

` 若需設定資源類型清單以合成存取器，可透過 ``` 的 `Project.resourceSynthesizers` 屬性傳遞欲使用的資源合成器清單：

```swift
let project = Project(resourceSynthesizers: [.string(), .fonts()])
```

::: info REFERENCE
<!-- -->
您可參閱[此範例](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_ios_app_with_templates)，了解如何運用自訂範本合成資源存取函式。
<!-- -->
:::
