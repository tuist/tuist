---
{
  "title": "插件",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何在 Tuist 中建立及使用插件，以擴充其功能。"
}
---
# 外掛程式 {#plugins}

外掛程式係一種工具，可以喺多個項目之間分享同重用 Tuist 產物。支援以下產物：

- <.localized_link href="/guides/features/projects/code-sharing">項目描述輔助工具</.localized_link>（適用於多個項目）
- <.localized_link href="/guides/features/projects/templates">範本</.localized_link>（適用於多個項目）
- 任務（適用於多個項目）
- <.localized_link href="/guides/features/projects/synthesized-files">資源存取器</.localized_link>範本（適用於多個項目）

請注意，外掛程式設計上係為咗提供一種簡單方式去擴展 Tuist 功能。因此，有**若干限制需要注意**：

- 一個外掛程式唔可以依賴另一個外掛程式。
- 一個外掛程式唔可以依賴第三方 Swift 套件。
- 一個外掛程式唔可以使用使用該外掛程式嘅項目中嘅項目描述輔助工具。

如果你需要更高彈性，可以考慮向工具建議新功能，或者基於 Tuist 嘅生成框架 [`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator) 自行構建解決方案。

## 外掛程式類型 {#plugin-types}

### 項目描述輔助外掛程式 {#project-description-helper-plugin}

項目描述輔助外掛程式由一個目錄表示，當中包含聲明外掛程式名稱嘅 `Plugin.swift` 清單檔案，以及包含輔助 Swift 檔案嘅 `ProjectDescriptionHelpers` 目錄。

::: code-group
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ProjectDescriptionHelpers
└── ...
```
<!-- -->
:::

### 資源存取器範本外掛程式 {#resource-accessor-templates-plugin}

如果你需要分享 <.localized_link href="/guides/features/projects/synthesized-files#resource-accessors">合成資源存取器</.localized_link>，可以使用此類型外掛程式。此外掛程式由一個目錄表示，當中包含聲明外掛程式名稱嘅 `Plugin.swift` 清單檔案，以及包含資源存取器範本檔案嘅 `ResourceSynthesizers` 目錄。


::: code-group
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ResourceSynthesizers
├───── Strings.stencil
├───── Plists.stencil
├───── CustomTemplate.stencil
└── ...
```
<!-- -->
:::

範本名稱係資源類型嘅 [駝峰式大小寫](https://en.wikipedia.org/wiki/Camel_case) 版本：

| 資源類型 | 範本檔案名稱 |
| ------------- | ------------------ |
| Strings | Strings.stencil |
| Assets | Assets.stencil |
| Property Lists | Plists.stencil |
| Fonts | Fonts.stencil |
| Core Data | CoreData.stencil |
| Interface Builder | InterfaceBuilder.stencil |
| JSON | JSON.stencil |
| YAML | YAML.stencil |

當喺項目中定義資源合成器時，你可以指定外掛程式名稱以使用來自外掛程式嘅範本：

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### 任務外掛程式 <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

> [!WARNING]
> **已棄用**
>
> 任務外掛程式已棄用。如果你正在為項目尋找自動化解決方案，請參閱[這篇網誌文章](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)。


任務係 `$PATH` 公開嘅可執行檔案，如果遵循 `tuist-<task-name>` 命名慣例，就可以透過 `tuist` 指令調用。喺早期版本中，Tuist 喺 `tuist plugin` 底下提供咗一啲寬鬆嘅慣例同工具，用於處理由 Swift Packages 中可執行檔案代表嘅 `build`、`run`、`test` 同 `archive` 任務，但我哋已經棄用此功能，因為佢會增加工具嘅維護負擔同複雜性。

如果你之前使用 Tuist 來分發任務，我哋建議你構建自己嘅
- 你可以繼續使用隨每個 Tuist 版本發布嘅 `ProjectAutomation.xcframework`，並透過 `let graph = try Tuist.graph()` 從你嘅邏輯中訪問項目圖。該指令使用系統進程運行 `tuist` 指令，並返回項目圖嘅內存表示形式。
- 要分發任務，我哋建議喺 GitHub 發布中包含支援 `arm64` 同 `x86_64` 嘅通用二進制檔案，並使用 [Mise](https://mise.jdx.dev) 作為安裝工具。要指示 Mise 如何安裝你嘅工具，你需要一個外掛程式倉庫。你可以參考 [Tuist 嘅](https://github.com/asdf-community/asdf-tuist)。
- 如果你將工具命名為 `tuist-{xxx}`，並且用戶可以透過運行 `mise install` 來安裝它，那麼他們可以直接調用它，或者透過 `tuist xxx` 來運行。

> [!NOTE]
> **Projectautomation 嘅未來**
>
> 我哋計劃將 `ProjectAutomation` 同 `XcodeGraph` 嘅模型整合到一個單一嘅向後兼容框架中，向用戶公開整個項目圖。此外，我哋會將生成邏輯提取到一個新層 `XcodeGraph`，你亦都可以從自己嘅 CLI 中使用它。可以將其視為構建你自己嘅 Tuist。


## 使用外掛程式 {#using-plugins}

要使用外掛程式，你需要將佢添加到你項目嘅 [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 清單檔案中：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

如果你想喺位於不同倉庫嘅多個項目之間重用外掛程式，你可以將外掛程式推送到 Git 倉庫，並喺 `Tuist.swift` 檔案中引用它：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

添加外掛程式後，`tuist install` 會喺全局緩存目錄中獲取外掛程式。

> [!NOTE]
> **無版本解析**
>
> 正如你可能已經注意到，我哋唔提供外掛程式嘅版本解析。我哋建議使用 Git 標籤或 SHA 以確保可重現性。


> [!TIP]
> **項目描述輔助外掛程式**
>
> 當使用項目描述輔助外掛程式時，包含輔助工具嘅模組名稱就係外掛程式嘅名稱
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
