---
{
  "title": "外掛程式",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何在 Tuist 中建立與使用外掛程式，以擴充其功能。"
}
---
# 外掛程式 {#plugins}

外掛程式是用於在多個專案之間共用與重複使用 Tuist 產物的工具。支援以下產物：

- <.localized_link href="/guides/features/projects/code-sharing">專案描述輔助工具</.localized_link>，可在多個專案之間共用。
- <.localized_link href="/guides/features/projects/templates">範本</.localized_link>，可在多個專案之間共用。
- 跨多個專案的任務
- <.localized_link href="/guides/features/projects/synthesized-files">跨多個專案的資源存取器</.localized_link>範本

請注意，外掛程式的設計目標是以簡單的方式擴充 Tuist 的功能。因此有**一些需要注意的限制**：

- 外掛程式不能依賴其他外掛程式。
- 外掛程式不能依賴第三方 Swift 套件
- 外掛程式不能使用使用該外掛程式之專案中的專案描述輔助工具。

如果你需要更多彈性，建議為工具提出功能需求，或基於 Tuist 的產生框架 [`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator) 自行建構解決方案。

## 外掛程式類型 {#plugin-types}

### 專案描述輔助外掛程式 {#project-description-helper-plugin}

專案描述輔助外掛程式由一個目錄表示，該目錄包含宣告外掛名稱的 `Plugin.swift` 資訊清單檔案，以及包含輔助 Swift 檔案的 `ProjectDescriptionHelpers` 目錄。

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

若你需要共用<.localized_link href="/guides/features/projects/synthesized-files#resource-accessors">合成的資源存取器</.localized_link>，可以使用此類型的外掛程式。該外掛程式由一個目錄表示，其中包含宣告外掛名稱的 `Plugin.swift` 資訊清單檔案，以及包含資源存取器範本檔案的 `ResourceSynthesizers` 目錄。


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
> **已棄用**
>
> 任務外掛程式已棄用。若你正在為專案尋找自動化解決方案，請參閱[這篇部落格文章](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)。


任務是透過 `$PATH` 公開的可執行檔，若遵循 `tuist-<task-name>` 的命名慣例，即可透過 `tuist` 指令叫用。在較早的版本中，Tuist 在 `tuist plugin` 底下提供了一些較為寬鬆的慣例與工具，用於處理由 Swift 套件中的可執行檔所代表的 `build`、`run`、`test` 與 `archive` 任務，但我們已棄用此功能，因為它會增加工具的維護負擔與複雜度。

如果你過去使用 Tuist 來分發任務，我們建議你自行建構
- 你可以繼續使用隨每個 Tuist 版本發布的 `ProjectAutomation.xcframework`，並透過 `let graph = try Tuist.graph()` 從你的邏輯中存取專案圖。該指令會使用系統程序執行 `tuist` 指令，並回傳專案圖的記憶體中表示。
- 若要分發任務，我們建議在 GitHub 發布中包含支援 `arm64` 與 `x86_64` 的通用二進位檔，並使用 [Mise](https://mise.jdx.dev) 作為安裝工具。若要指示 Mise 如何安裝你的工具，你需要一個外掛程式儲存庫。你可以參考 [Tuist 的](https://github.com/asdf-community/asdf-tuist) 實作。
- 若將你的工具命名為 `tuist-{xxx}`，且使用者可以透過執行 `mise install` 來安裝，他們可以直接叫用它，或透過 `tuist xxx` 執行。

> [!NOTE]
> **ProjectAutomation 的未來**
>
> 我們計畫將 `ProjectAutomation` 與 `XcodeGraph` 的模型整合為單一向後相容的框架，向使用者揭露完整的專案圖。此外，我們會將產生邏輯提取到新的層級 `XcodeGraph`，你也可以從自己的 CLI 中使用它。不妨將其視為建構你自己的 Tuist。


## 使用外掛程式 {#using-plugins}

若要使用外掛程式，你必須將其加入專案的 [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 資訊清單檔案：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

若你想在不同儲存庫的專案之間重複使用外掛程式，可以將外掛程式推送至 Git 儲存庫，並在 `Tuist.swift` 檔案中參考它：

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
> 如你可能已經注意到，我們不為外掛程式提供版本解析。我們建議使用 Git 標籤或 SHA 以確保可重現性。


> [!TIP]
> **專案描述輔助外掛程式**
>
> 使用專案描述輔助外掛程式時，包含輔助工具的模組名稱即為外掛程式的名稱
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
