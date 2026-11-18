---
{
  "title": "外掛程式",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何在 Tuist 中建立和使用外掛程式，以擴充其功能。"
}
---
# 外掛程式 {#plugins}

外掛程式可讓你喺多個項目之間共用同重用 Tuist 構件。支援以下構件：

- <.localized_link href="/guides/features/projects/code-sharing">項目描述輔助工具</.localized_link>，適用於多個項目。
- <.localized_link href="/guides/features/projects/templates">模板</.localized_link>，適用於多個項目。
- 任務，適用於多個項目。
- <.localized_link href="/guides/features/projects/synthesized-files">資源存取器</.localized_link>模板，適用於多個項目

請注意，外掛程式旨在提供一種簡單方式來擴展 Tuist 的功能。因此有**一些需要考慮的限制**：

- 外掛程式唔可以依賴另一個外掛程式。
- 外掛程式唔可以依賴第三方 Swift 套件
- 外掛程式唔可以使用使用該外掛程式的項目中的項目描述輔助工具。

如果你需要更多靈活性，可以考慮為工具建議新功能，或者基於 Tuist 的生成框架 [`TuistGenerator`](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator) 建立你自己的解決方案。

## 外掛程式類型 {#plugin-types}

### 項目描述輔助工具外掛程式 {#project-description-helper-plugin}

項目描述輔助工具外掛程式由一個目錄表示，該目錄包含聲明外掛程式名稱的 `Plugin.swift` 清單檔案，以及包含輔助 Swift 檔案的 `ProjectDescriptionHelpers` 目錄。

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

### 資源存取器模板外掛程式 {#resource-accessor-templates-plugin}

如果你需要共用<.localized_link href="/guides/features/projects/synthesized-files#resource-accessors">合成的資源存取器</.localized_link>，可以使用此類外掛程式。外掛程式由一個目錄表示，該目錄包含聲明外掛程式名稱的 `Plugin.swift` 清單檔案，以及包含資源存取器模板檔案的 `ResourceSynthesizers` 目錄。


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

模板的名稱係資源類型的[駱駝式大小寫](https://en.wikipedia.org/wiki/Camel_case)版本：

| 資源類型 | 模板檔案名稱 |
| ------------- | ------------------ |
| Strings | Strings.stencil |
| Assets | Assets.stencil |
| Property Lists | Plists.stencil |
| Fonts | Fonts.stencil |
| Core Data | CoreData.stencil |
| Interface Builder | InterfaceBuilder.stencil |
| JSON | JSON.stencil |
| YAML | YAML.stencil |

當喺項目中定義資源合成器時，你可以指定外掛程式名稱以使用來自外掛程式的模板：

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### 任務外掛程式 <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

> [!WARNING]
> **已棄用**
>
> 任務外掛程式已棄用。如果你正在為項目尋找自動化解決方案，請查看[這篇部落格文章](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)。


任務係暴露喺 `$PATH` 嘅可執行檔案，如果佢哋遵循 `tuist-<task-name>` 命名慣例，就可以透過 `tuist` 命令調用。喺早期版本中，Tuist 喺 `tuist plugin` 之下提供咗一啲弱約定同工具，用於 `build`、`run`、`test` 同 `archive` 由 Swift Packages 中可執行檔案表示嘅任務，但我哋已經棄用此功能，因為它增加咗工具嘅維護負擔同複雜性。

如果你之前將任務作為外掛程式分發，請改為將佢哋構建為獨立可執行檔案：

- 你可以繼續使用隨每個 Tuist 版本分發嘅 `ProjectAutomation.xcframework`，透過 `let graph = try Tuist.graph()` 從你嘅邏輯訪問項目圖。它會以子進程方式運行 `tuist` 並返回項目圖嘅內存表示。
- 要分發任務，我哋建議喺 GitHub releases 中發布支援 `arm64` 同 `x86_64` 嘅通用二進制檔案，並使用 [Mise](https://mise.jdx.dev) 作為安裝工具。要指示 Mise 如何安裝你嘅工具，你需要一個外掛程式儲存庫。你可以參考 [Tuist 嘅](https://github.com/asdf-community/asdf-tuist)。
- 如果你將工具命名為 `tuist-{xxx}` 並且用戶可以透過運行 `mise install` 來安裝它，佢哋可以直接調用它，或者透過 `tuist xxx` 運行它。

> [!NOTE]
> **ProjectAutomation 嘅未來**
>
> 我哋計劃將 `ProjectAutomation` 同 `XcodeGraph` 嘅模型整合到一個單一嘅向後相容框架中，該框架向用戶公開整個項目圖。此外，我哋會將生成邏輯提取到新層 `XcodeGraph`，你也可以從自己嘅 CLI 中使用它。可以將其視為構建你自己嘅 Tuist。


## 使用外掛程式 {#using-plugins}

要使用外掛程式，你需要將它添加到你項目嘅 [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 清單檔案中：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

如果你想喺位於不同儲存庫嘅項目之間重用外掛程式，你可以將外掛程式推送到 Git 儲存庫，並喺 `Tuist.swift` 檔案中引用它：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

添加外掛程式後，`tuist install` 會喺全局快取目錄中獲取外掛程式。

> [!NOTE]
> **無版本解析**
>
> 正如你可能注意到嘅，我哋唔提供外掛程式嘅版本解析。我哋建議使用 Git tags 或 SHAs 來確保可重複性。


> [!TIP]
> **項目描述輔助工具外掛程式**
>
> 當使用項目描述輔助工具外掛程式時，包含輔助工具嘅模組名稱就係外掛程式嘅名稱
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
