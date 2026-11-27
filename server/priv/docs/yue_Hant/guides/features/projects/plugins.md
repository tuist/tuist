---
{
  "title": "外掛程式",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何在 Tuist 中建立及使用外掛程式，以擴充其功能。"
}
---
# 插件 {#plugins}

插件係一種工具，用嚟喺多個項目之間共用同重用 Tuist 產物。支援以下產物：

- <.localized_link href="/guides/features/projects/code-sharing">項目描述輔助函數</.localized_link>，可跨多個項目使用。
- <.localized_link href="/guides/features/projects/templates">模板</.localized_link>，可跨多個項目使用。
- 任務，可跨多個項目使用。
- <.localized_link href="/guides/features/projects/synthesized-files">資源存取器</.localized_link>模板，可跨多個項目使用。

請注意，插件設計為擴展 Tuist 功能嘅簡易方式。因此有**若干限制需要留意**：

- 插件不能依賴其他插件。
- 插件不能依賴第三方 Swift 套件。
- 插件不能使用使用該插件的項目中的項目描述輔助函數。

如果你需要更多靈活性，可以考慮向工具建議新功能，或者基於 Tuist 的生成框架 [`TuistGenerator`](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator) 構建你自己的解決方案。

## 插件類型 {#plugin-types}

### 項目描述輔助插件 {#project-description-helper-plugin}

項目描述輔助插件由一個目錄表示，該目錄包含聲明插件名稱的 `Plugin.swift` 清單文件，以及包含輔助 Swift 文件的 `ProjectDescriptionHelpers` 目錄。

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

### 資源存取器模板插件 {#resource-accessor-templates-plugin}

如果你需要共用<.localized_link href="/guides/features/projects/synthesized-files#resource-accessors">合成的資源存取器</.localized_link>，可以使用此類型的插件。該插件由一個目錄表示，該目錄包含聲明插件名稱的 `Plugin.swift` 清單文件，以及包含資源存取器模板文件的 `ResourceSynthesizers` 目錄。


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

模板的名稱係資源類型的[駝峰式大小寫](https://en.wikipedia.org/wiki/Camel_case)版本：

| 資源類型 | 模板文件名 |
| ------------- | ------------------ |
| Strings | Strings.stencil |
| Assets | Assets.stencil |
| Property Lists | Plists.stencil |
| Fonts | Fonts.stencil |
| Core Data | CoreData.stencil |
| Interface Builder | InterfaceBuilder.stencil |
| JSON | JSON.stencil |
| YAML | YAML.stencil |

當在項目中定義資源合成器時，你可以指定插件名稱以使用來自該插件的模板：

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### 任務插件 <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

> [!WARNING]
> **已棄用**
>
> 任務插件已棄用。如果你正在為項目尋找自動化解決方案，請查看[這篇博客文章](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)。


任務係暴露喺 `$PATH` 嘅可執行文件，如果佢哋遵循命名慣例 `tuist-<task-name>`，就可以透過 `tuist` 命令調用。喺早期版本中，Tuist 喺 `tuist plugin` 下提供咗一啲弱約定同工具，用嚟處理由 Swift Packages 中可執行文件代表嘅 `build`、`run`、`test` 同 `archive` 任務，但我哋已經棄用此功能，因為它增加咗工具嘅維護負擔同複雜性。

如果你之前將任務作為插件分發，請改為將佢哋構建為獨立可執行文件：

- 你可以繼續使用隨每個 Tuist 版本分發嘅 `ProjectAutomation.xcframework`，透過 `let graph = try Tuist.graph()` 從你嘅邏輯中訪問項目圖。它會將 `tuist` 作為子進程運行，並返回項目圖嘅內存表示。
- 為咗分發任務，我哋建議喺 GitHub releases 中發布支援 `arm64` 同 `x86_64` 嘅通用二進制文件，並使用 [Mise](https://mise.jdx.dev) 作為安裝工具。要指示 Mise 如何安裝你嘅工具，你需要一個插件倉庫。你可以參考 [Tuist 嘅](https://github.com/asdf-community/asdf-tuist)。
- 如果你將工具命名為 `tuist-{xxx}`，並且用戶可以透過運行 `mise install` 來安裝它，那麼佢哋可以直接調用它，或者透過 `tuist xxx` 來運行。

> [!NOTE]
> **ProjectAutomation 嘅未來**
>
> 我哋計劃將 `ProjectAutomation` 同 `XcodeGraph` 嘅模型合併到一個單一嘅向後兼容框架中，該框架向用戶公開整個項目圖。此外，我哋會將生成邏輯提取到新層 `XcodeGraph` 中，你也可以從自己嘅 CLI 中使用它。可以將其視為構建你自己嘅 Tuist。


## 使用插件 {#using-plugins}

要使用插件，你需要將它添加到項目嘅 [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 清單文件中：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

如果你想喺位於不同倉庫嘅項目之間重用插件，你可以將插件推送到 Git 倉庫，並喺 `Tuist.swift` 文件中引用它：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

添加插件後，`tuist install` 會喺全局緩存目錄中獲取插件。

> [!NOTE]
> **無版本解析**
>
> 正如你可能注意到嘅，我哋不為插件提供版本解析。我哋建議使用 Git 標籤或 SHA 以確保可重複性。


> [!TIP]
> **項目描述輔助插件**
>
> 當使用項目描述輔助插件時，包含輔助函數嘅模塊名稱就係插件嘅名稱
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
