---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# 外掛程式{#plugins}

外掛程式是用於在多個專案間共享與重複使用 Tuist 組件的工具。支援以下組件：

- <LocalizedLink href="/guides/features/projects/code-sharing">跨專案的專案說明輔助工具</LocalizedLink>。
- <LocalizedLink href="/guides/features/projects/templates">跨多個專案的範本</LocalizedLink>。
- 跨專案的任務。
- <LocalizedLink href="/guides/features/projects/synthesized-files">跨專案的
  Resource accessor</LocalizedLink> 範本

請注意，外掛程式旨在作為擴充 Tuist 功能的簡易方式。因此，有**一些限制需加以考量**:

- 一個外掛程式不能依賴另一個外掛程式。
- 外掛程式不得依賴第三方 Swift 套件
- 外掛程式無法使用該外掛程式所屬專案中的專案描述輔助函式。

若您需要更大的彈性，可考慮為該工具提出功能建議，或基於 Tuist 的生成框架
[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator)
自行開發解決方案。

## 外掛程式類型{#plugin-types}

### 專案說明輔助外掛程式{#project-description-helper-plugin}

專案描述輔助外掛程式由一個目錄表示，該目錄包含宣告外掛程式名稱的 ``Plugin.swift`` 清單檔案，以及存放輔助 Swift 檔案的
``ProjectDescriptionHelpers`` 目錄。

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

### 資源存取器範本外掛程式{#resource-accessor-templates-plugin}

若需共用
<LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors">資源合成器</LocalizedLink>，可使用此類外掛程式。該外掛程式由一個目錄構成，其中包含宣告外掛程式名稱的
manifests.swift 檔案（`Plugin.swift` ），以及存放資源存取器範本檔案的 ResourceSynthesizers 目錄（`` ）。


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

範本名稱應採用資源類型的 [駱駝式大小寫](https://en.wikipedia.org/wiki/Camel_case) 形式：

| 資源類型  | 範本檔名稱                    |
| ----- | ------------------------ |
| 字串    | Strings.stencil          |
| 資源    | Assets.stencil           |
| 屬性清單  | Plists.stencil           |
| 字型    | Fonts.stencil            |
| 核心資料  | CoreData.stencil         |
| 介面建構器 | InterfaceBuilder.stencil |
| JSON  | JSON.stencil             |
| YAML  | YAML.stencil             |

在專案中定義資源合成器時，您可以指定外掛程式名稱以使用該外掛程式的範本：

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### Task 外掛程式 <Badge type="warning" text="deprecated" />{#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
任務外掛程式已不再支援。若您正在為專案尋找自動化解決方案，請參閱
[這篇部落格文章](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)。
<!-- -->
:::

任務是`$PATH`- 透過`tuist` 命令可調用的公開可執行檔，前提是它們遵循命名規範`tuist-<task-name>` 。在早期版本中，Tuist
曾在`tuist plugin` 下提供一些簡易的規範與工具，用於`建置` 、`執行` 、`測試` 以及`歸檔` 這些由 Swift
套件中的可執行檔所代表的任務，但我們已廢棄此功能，因為它增加了工具的維護負擔與複雜性。</task-name>

若您使用 Tuist 來分配任務，我們建議您建立您的
- 您可以繼續使用隨每個 Tuist 版本發佈的`ProjectAutomation.xcframework` ，透過`let graph = try
  Tuist.graph()` 在邏輯中存取專案圖。此指令會使用系統程序執行`tuist` 指令，並返回專案圖的記憶體內表示形式。
- 為了分發任務，我們建議在 GitHub 發行版中包含支援`arm64` 以及`x86_64` 的 fat 二進位檔，並使用
  [Mise](https://mise.jdx.dev) 作為安裝工具。若要指示 Mise 如何安裝您的工具，您需要一個外掛程式儲存庫。您可以參考
  [Tuist 的](https://github.com/asdf-community/asdf-tuist) 作為範例。
- 若您將工具命名為`tuist-{xxx}` ，且使用者可透過執行`mise install` 來安裝，則他們既可直接呼叫該工具，亦可透過`tuist
  xxx` 來執行。

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
我們計劃將`ProjectAutomation` 與`XcodeGraph`
的模型整合為單一且向後相容的框架，向使用者完整呈現專案圖。此外，我們將把生成邏輯抽離至新層級`XcodeGraph` ，您亦可從自己的命令列介面 (CLI)
使用此框架。不妨將其視為打造您專屬的 Tuist。
<!-- -->
:::

## 使用外掛程式{#using-plugins}

若要使用外掛程式，您必須將其新增至專案的
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
manifest 檔案中：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

若您希望在不同儲存庫中的專案間重複使用某個外掛程式，可將外掛程式推送至 Git 儲存庫，並在`Tuist.swift` 檔案中引用它：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

安裝插件後，執行`tuist install` 將把插件下載至全域快取目錄中。

::: info NO VERSION RESOLUTION
<!-- -->
您可能已經注意到，我們不提供外掛程式的版本解析功能。我們建議使用 Git 標籤或 SHA 值來確保可重現性。
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
使用專案說明輔助程式外掛時，包含這些輔助程式的模組名稱即為該外掛的名稱
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
