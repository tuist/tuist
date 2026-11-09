---
{
  "title": "外掛程式",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何在 Tuist 中建立與使用外掛程式，以擴充其功能。"
}
---
# 外掛程式 {#plugins}

外掛程式是一種工具，可讓你在多個專案之間共用與重複使用 Tuist 產物。支援以下產物：

- 跨多個專案的<.localized_link href="/guides/features/projects/code-sharing">專案描述輔助工具</.localized_link>。
- 跨多個專案的<.localized_link href="/guides/features/projects/templates">範本</.localized_link>。
- 跨多個專案的任務。
- 跨多個專案的<.localized_link href="/guides/features/projects/synthesized-files">資源存取器</.localized_link>範本

請注意，外掛程式的設計目的是以簡單的方式擴充 Tuist 的功能。因此有**一些需要注意的限制**：

- 外掛程式不能依賴其他外掛程式。
- 外掛程式不能依賴第三方 Swift 套件
- 外掛程式不能使用使用該外掛程式之專案中的專案描述輔助工具。

如果你需要更多彈性，可以考慮為工具提出功能建議，或基於 Tuist 的產生框架打造你自己的解決方案：[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator)。

## 外掛程式類型 {#plugin-types}

### 專案描述輔助外掛程式 {#project-description-helper-plugin}

專案描述輔助外掛程式由一個目錄表示，其中包含宣告外掛程式名稱的 `Plugin.swift` 資訊清單檔案，以及包含輔助 Swift 檔案的 `ProjectDescriptionHelpers` 目錄。

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

如果你需要共用<.localized_link href="/guides/features/projects/synthesized-files#resource-accessors">合成的資源存取器</.localized_link>，可以使用這類外掛程式。該外掛程式由一個目錄表示，其中包含宣告外掛程式名稱的 `Plugin.swift` 資訊清單檔案，以及包含資源存取器範本檔案的 `ResourceSynthesizers` 目錄。


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

範本的名稱是資源類型的[駝峰式大小寫](https://en.wikipedia.org/wiki/Camel_case)版本：

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

在專案中定義資源合成器時，你可以指定外掛程式名稱以使用來自外掛程式的範本：

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### 任務外掛程式 <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

> [!WARNING]
> **已淘汰**
>
> 任務外掛程式已淘汰。如果你正在為專案尋找自動化解決方案，請參閱[這篇部落格文章](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)。


任務是透過 `$PATH` 公開的可執行檔，如果遵循 `tuist-<task-name>` 的命名慣例，就可以透過 `tuist` 指令叫用。在較早的版本中，Tuist 在 `tuist plugin` 底下提供了一些鬆散的慣例與工具，用來處理由 Swift 套件中的可執行檔所代表的 `build`、`run`、`test` 與 `archive` 任務，但我們已淘汰此功能，因為它會增加工具的維護負擔與複雜度。

如果你先前以插件形式發布任務，請改為將它們建置為獨立的可執行檔：

- 你可以繼續使用隨每個 Tuist 版本發布的 `ProjectAutomation.xcframework`，並透過 `let graph = try Tuist.graph()` 從你的邏輯中存取專案圖。它會以子程序執行 `tuist`，並回傳專案圖的記憶體表示。
- 若要發布任務，我們建議在 GitHub 發布中提供支援 `arm64` 與 `x86_64` 的通用二進位檔，並使用 [Mise](https://mise.jdx.dev) 作為安裝工具。要指示 Mise 如何安裝你的工具，你需要一個插件儲存庫。你可以參考 [Tuist 的](https://github.com/asdf-community/asdf-tuist) 實作。
- 如果你將工具命名為 `tuist-{xxx}`，且使用者可以透過執行 `mise install` 來安裝，他們可以直接叫用它，或透過 `tuist xxx` 執行。

> [!NOTE]
> **ProjectAutomation 的未來**
>
> 我們計畫將 `ProjectAutomation` 與 `XcodeGraph` 的模型整合為單一向後相容的框架，讓使用者可以存取完整的專案圖。此外，我們會將產生邏輯抽離到新的層級 `XcodeGraph`，你也可以在自己的 CLI 中使用。你可以把它想像成打造你自己的 Tuist。


## 使用外掛程式 {#using-plugins}

要使用外掛程式，你必須將其加入專案的 [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 資訊清單檔案：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

如果你想在位於不同儲存庫的專案之間重複使用外掛程式，可以將外掛程式推送到 Git 儲存庫，並在 `Tuist.swift` 檔案中引用它：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

新增外掛程式後，`tuist install` 會在全域快取目錄中抓取外掛程式。

> [!NOTE]
> **無版本解析**
>
> 如你可能已經注意到，我們不為外掛程式提供版本解析。我們建議使用 Git 標籤或 SHA 來確保可重現性。


> [!TIP]
> **專案描述輔助外掛程式**
>
> 使用專案描述輔助外掛程式時，包含輔助工具的模組名稱就是外掛程式的名稱
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
