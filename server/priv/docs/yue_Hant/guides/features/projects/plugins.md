---
{
  "title": "外掛程式",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何建立及使用 Tuist 外掛程式以擴充其功能。"
}
---
# 外掛程式 {#plugins}

外掛程式係一種工具，方便你喺多個專案之間共用同重用 Tuist 產物。支援以下產物：

- <.localized_link href="/guides/features/projects/code-sharing">Project description helpers</.localized_link>（跨多個專案）
- <.localized_link href="/guides/features/projects/templates">Templates</.localized_link>（跨多個專案）
- Tasks（跨多個專案）
- <.localized_link href="/guides/features/projects/synthesized-files">Resource accessor</.localized_link> template（跨多個專案）

請注意，外掛程式設計上係為咗以簡單方式擴展 Tuist 功能。因此有**若干限制需要注意**：

- 一個外掛程式唔可以依賴另一個外掛程式。
- 一個外掛程式唔可以依賴第三方 Swift packages
- 一個外掛程式唔可以使用使用該外掛程式嘅專案入面嘅 project description helpers。

如果你需要更高彈性，可以考慮向工具建議新功能，或者基於 Tuist 嘅 generation framework [`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator) 建立自己嘅解決方案。

## 外掛程式類型 {#plugin-types}

### Project description helper 外掛程式 {#project-description-helper-plugin}

Project description helper 外掛程式由一個目錄表示，當中包含宣告外掛程式名稱嘅 `Plugin.swift` manifest 檔案，以及包含 helper Swift 檔案嘅 `ProjectDescriptionHelpers` 目錄。

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

### Resource accessor templates 外掛程式 {#resource-accessor-templates-plugin}

如果你需要共用<.localized_link href="/guides/features/projects/synthesized-files#resource-accessors">synthesized resource accessors</.localized_link>，可以使用呢種類型嘅外掛程式。此外掛程式由一個目錄表示，當中包含宣告外掛程式名稱嘅 `Plugin.swift` manifest 檔案，以及包含 resource accessor template 檔案嘅 `ResourceSynthesizers` 目錄。


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

Template 嘅名稱係資源類型嘅[camel case](https://en.wikipedia.org/wiki/Camel_case)版本：

| 資源類型 | Template 檔案名稱 |
| ------------- | ------------------ |
| Strings | Strings.stencil |
| Assets | Assets.stencil |
| Property Lists | Plists.stencil |
| Fonts | Fonts.stencil |
| Core Data | CoreData.stencil |
| Interface Builder | InterfaceBuilder.stencil |
| JSON | JSON.stencil |
| YAML | YAML.stencil |

當喺專案中定義 resource synthesizers 時，你可以指定外掛程式名稱以使用來自此外掛程式嘅 templates：

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### Task 外掛程式 <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

> [!WARNING]
> **已棄用**
>
> Task 外掛程式已棄用。如果你正在為專案尋找自動化解決方案，請參閱[呢篇網誌文章](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)。


Tasks 係 `$PATH`-exposed executables，如果佢哋遵循命名慣例 `tuist-<task-name>`，就可以透過 `tuist` 指令呼叫。喺早期版本中，Tuist 喺 `tuist plugin` 底下提供咗一啲較弱嘅慣例同工具，用於處理由 Swift Packages 中 executables 代表嘅 `build`、`run`、`test` 同 `archive` tasks，但我哋已經棄用呢項功能，因為佢會增加工具嘅維護負擔同複雜性。

如果你之前使用 Tuist 來分發 tasks，我哋建議你建立自己嘅
- 你可以繼續使用隨每個 Tuist 版本發佈嘅 `ProjectAutomation.xcframework`，透過 `let graph = try Tuist.graph()` 從你嘅邏輯存取 project graph。該指令會使用系統進程運行 `tuist` 指令，並返回 project graph 嘅記憶體表示。
- 要分發 tasks，我哋建議喺 GitHub releases 中包含支援 `arm64` 同 `x86_64` 嘅 fat binary，並使用 [Mise](https://mise.jdx.dev) 作為安裝工具。要指示 Mise 如何安裝你嘅工具，你需要一個 plugin repository。你可以參考 [Tuist's](https://github.com/asdf-community/asdf-tuist)。
- 如果你將工具命名為 `tuist-{xxx}`，而用戶可以透過運行 `mise install` 來安裝它，那麼佢哋可以直接調用它，或者透過 `tuist xxx` 來運行。

> [!NOTE]
> **Projectautomation 嘅未來**
>
> 我哋計劃將 `ProjectAutomation` 同 `XcodeGraph` 嘅模型合併為單一嘅向後相容 framework，向用戶公開整個 project graph。此外，我哋會將 generation logic 提取到新層 `XcodeGraph`，你也可以從自己嘅 CLI 中使用它。可以將此視為建立你自己嘅 Tuist。


## 使用外掛程式 {#using-plugins}

要使用外掛程式，你需要將它添加到專案嘅 [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) manifest 檔案中：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

如果你想喺位於不同儲存庫嘅專案之間重用外掛程式，你可以將外掛程式推送到 Git repository，並喺 `Tuist.swift` 檔案中引用它：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

添加外掛程式後，`tuist install` 會喺全域快取目錄中獲取外掛程式。

> [!NOTE]
> **無版本解析**
>
> 正如你可能注意到，我哋唔會為外掛程式提供版本解析。我哋建議使用 Git tags 或 SHAs 以確保可重複性。


> [!TIP]
> **Project Description Helpers 外掛程式**
>
> 當使用 project description helpers 外掛程式時，包含 helpers 嘅 module 名稱就係外掛程式嘅名稱
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
