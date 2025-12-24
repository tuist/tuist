---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# 外掛程式{#plugins}

外掛是在多個專案中分享和重複使用 Tuist 工件的工具。支援下列工件：

- <LocalizedLink href="/guides/features/projects/code-sharing">橫跨多個專案的專案描述輔助工具</LocalizedLink>。
- <LocalizedLink href="/guides/features/projects/templates">跨多個專案的範本</LocalizedLink>。
- 橫跨多個專案的任務。
- <LocalizedLink href="/guides/features/projects/synthesized-files">跨專案的資源存取器</LocalizedLink>範本

請注意，外掛被設計成擴展 Tuist 功能的簡單方式。因此**有一些限制需要考慮** ：

- 外掛程式不能依賴於其他外掛程式。
- 外掛無法依賴第三方 Swift 套件
- 外掛無法使用使用外掛的專案中的專案描述輔助程式。

如果您需要更多的彈性，請考慮建議工具的功能，或在 Tuist
的產生框架上建立您自己的解決方案，[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator).

## 外掛程式類型{#plugin-types}

### 專案描述輔助外掛程式{#project-description-helper-plugin}

專案描述輔助外掛程式由一個目錄表示，該目錄包含一個`Plugin.swift` 宣稱外掛程式名稱的 manifest
檔案，以及一個`ProjectDescriptionHelpers` 目錄，該目錄包含輔助 Swift 檔案。

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

### 資源存取器模板外掛程式{#resource-accessor-templates-plugin}

如果您需要共用
<LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors"> 合成的資源存取器</LocalizedLink>，您可以使用此類型的外掛。該外掛由一個包含`Plugin.swift` manifest
檔案（宣告外掛名稱）和`ResourceSynthesizers` 目錄（包含資源存取器模板檔案）的目錄來表示。


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

範本的名稱是資源類型的 [camel case](https://en.wikipedia.org/wiki/Camel_case) 版本：

| 資源類型   | 範本檔案名稱                   |
| ------ | ------------------------ |
| 弦線     | Strings.stencil          |
| 資產     | Assets.stencil           |
| 財產清單   | Plists.stencil           |
| 字體     | 字體模板                     |
| 核心資料   | CoreData.stencil         |
| 介面建立程式 | InterfaceBuilder.stencil |
| JSON   | JSON.stencil             |
| YAML   | YAML.stencil             |

在專案中定義資源合成器時，可以指定外掛程式名稱，以使用外掛程式中的範本：

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### 任務外掛程式 <Badge type="warning" text="deprecated" />{#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
任務外掛已經過時。如果您正在為專案尋找自動化解決方案，請參閱
[本篇部落格文章](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)。
<!-- -->
:::

任務是`$PATH`-exposed 的可執行檔，如果遵循命名慣例`tuist-<task-name>` ，則可透過`tuist`
指令來啟用。在早期版本中，Tuist 在`tuist plugin` 下提供了一些弱化的慣例和工具，以`build`,`run`,`test`
和`archive` 任務，這些任務由 Swift Packages
中的可執行檔代表，但是我們已經棄用此功能，因為它增加了維護負擔和工具的複雜性。

如果您使用 Tuist 來分發任務，我們建議您建立您的
- 您可以繼續使用`ProjectAutomation.xcframework` 與每個 Tuist 發行版本一起發佈，從您的邏輯中存取專案圖形，`let
  graph = try Tuist.graph()` 。該命令使用系統進程執行`tuist` 命令，並傳回專案圖形的記憶體表示。
- 若要發佈任務，我們建議在 GitHub 發佈的版本中，包含支援`arm64` 和`x86_64` 的 fat binary，並使用
  [Mise](https://mise.jdx.dev) 作為安裝工具。要指示 Mise 如何安裝您的工具，您需要一個外掛程式庫。您可以使用
  [Tuist's](https://github.com/asdf-community/asdf-tuist) 作為參考。
- 如果您將您的工具命名為`tuist-{xxx}` ，使用者可以執行`mise install` 來安裝它，他們可以直接呼叫它，或透過`tuist xxx`
  來執行它。

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
我們計劃將`ProjectAutomation` 和`XcodeGraph`
的模型整合為一個單一的向後相容的框架，將專案圖形的完整性暴露給用戶。此外，我們將提取生成邏輯到一個新的層，`XcodeGraph` ，您也可以從您自己的 CLI
中使用它。將其視為建立您自己的 Tuist。
<!-- -->
:::

## 使用外掛程式{#using-plugins}

若要使用外掛程式，您必須將其加入專案的
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
manifest 檔案：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

如果您想在不同儲存庫的專案中重複使用外掛程式，您可以將外掛程式推送到 Git 儲存庫，並在`Tuist.swift` 檔案中引用它：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

新增外掛程式後，`tuist install` 會在全域快取目錄中取得外掛程式。

::: info NO VERSION RESOLUTION
<!-- -->
您可能已經注意到，我們不提供外掛程式的版本解析。我們建議使用 Git 標籤或 SHA 以確保可重複性。
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
使用專案描述輔助外掛程式時，包含輔助程式的模組名稱即為外掛程式的名稱
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
