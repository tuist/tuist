---
{
  "title": "外掛程式",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何在 Tuist 中建立及使用外掛程式，以擴充其功能。"
}
---
# 外掛 {#plugins}

外掛係一種工具，用嚟喺多個項目之間共用同重用 Tuist 構件。支援以下構件：

- 跨多個項目的<.localized_link href="/guides/features/projects/code-sharing">項目描述輔助程式</.localized_link>。
- 跨多個項目的<.localized_link href="/guides/features/projects/templates">範本</.localized_link>。
- 跨多個項目的任務。
- 跨多個項目的<.localized_link href="/guides/features/projects/synthesized-files">資源存取器</.localized_link>範本

請注意，外掛設計為擴充 Tuist 功能的簡單方法。因此有**若干限制需要考慮**：

- 外掛不能依賴另一個外掛。
- 外掛不能依賴第三方 Swift 套件
- 外掛不能使用使用該外掛的項目中的項目描述輔助程式。

如果你需要更大彈性，可以考慮向工具建議新功能，或者基於 Tuist 的生成框架 [`TuistGenerator`](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator) 建立你自己的解決方案。

## 外掛類型 {#plugin-types}

### 項目描述輔助程式外掛 {#project-description-helper-plugin}

項目描述輔助程式外掛由一個目錄表示，該目錄包含聲明外掛名稱的 `Plugin.swift` 清單檔案，以及包含輔助 Swift 檔案的 `ProjectDescriptionHelpers` 目錄。

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

### 資源存取器範本外掛 {#resource-accessor-templates-plugin}

如果你需要共用<.localized_link href="/guides/features/projects/synthesized-files#resource-accessors">合成的資源存取器</.localized_link>，可以使用此類型的外掛。此外掛由一個目錄表示，該目錄包含聲明外掛名稱的 `Plugin.swift` 清單檔案，以及包含資源存取器範本檔案的 `ResourceSynthesizers` 目錄。


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

範本的名稱係資源類型的[駝峰式大小寫](https://en.wikipedia.org/wiki/Camel_case)版本：

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

當喺項目中定義資源合成器時，你可以指定外掛名稱以使用來自外掛的範本：

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### 任務外掛 <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

> [!WARNING]
> **已棄用**
>
> 任務外掛已棄用。如果你正在為項目尋找自動化解決方案，請查看[這篇部落格文章](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)。


任務係 `$PATH` 公開的可執行檔，如果遵循命名慣例 `tuist-<task-name>`，就可以透過 `tuist` 指令呼叫。在早期版本中，Tuist 喺 `tuist plugin` 之下提供咗一些弱約定同工具，用嚟處理由 Swift Packages 中的可執行檔代表的 `build`、`run`、`test` 同 `archive` 任務，但我哋已經棄用此功能，因為它會增加工具的維護負擔同複雜性。

如果你之前將任務作為外掛分發，請改為將它們構建為獨立的可執行檔：

- 你可以繼續使用隨每個 Tuist 版本分發的 `ProjectAutomation.xcframework`，透過 `let graph = try Tuist.graph()` 從你的邏輯中存取項目圖。它會以子進程方式運行 `tuist`，並返回項目圖的記憶體表示。
- 要分發任務，我哋建議喺 GitHub 發布中發布支援 `arm64` 同 `x86_64` 的通用二進制檔，並使用 [Mise](https://mise.jdx.dev) 作為安裝工具。要指示 Mise 如何安裝你的工具，你需要一個外掛儲存庫。你可以參考 [Tuist 的](https://github.com/asdf-community/asdf-tuist) 儲存庫。
- 如果你將工具命名為 `tuist-{xxx}`，並且用戶可以透過運行 `mise install` 來安裝它，那麼他們可以直接呼叫它，或者透過 `tuist xxx` 來運行它。

> [!NOTE]
> **ProjectAutomation 的未來**
>
> 我哋計劃將 `ProjectAutomation` 同 `XcodeGraph` 的模型合併為單一向後相容的框架，向用戶公開整個項目圖。此外，我哋會將生成邏輯提取到一個新層 `XcodeGraph`，你也可以從自己的 CLI 中使用它。可以將其視為建立你自己的 Tuist。


## 使用外掛 {#using-plugins}

要使用外掛，你必須將其添加到項目的 [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 清單檔案中：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

如果你想喺位於不同儲存庫的項目之間重用外掛，你可以將外掛推送到 Git 儲存庫，並喺 `Tuist.swift` 檔案中引用它：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

添加外掛後，`tuist install` 會喺全域快取目錄中獲取外掛。

> [!NOTE]
> **無版本解析**
>
> 正如你可能注意到的，我哋不為外掛提供版本解析。我哋建議使用 Git 標籤或 SHA 以確保可重現性。


> [!TIP]
> **項目描述輔助程式外掛**
>
> 當使用項目描述輔助程式外掛時，包含輔助程式的模組名稱就係外掛的名稱
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
