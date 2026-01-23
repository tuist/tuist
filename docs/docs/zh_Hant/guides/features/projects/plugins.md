---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# 外掛程式{#plugins}

外掛程式是跨專案共享與重複使用 Tuist 成果的工具。目前支援以下成果類型：

- <LocalizedLink href="/guides/features/projects/code-sharing">專案說明協助者</LocalizedLink>橫跨多個專案。
- <LocalizedLink href="/guides/features/projects/templates">跨多個專案的範本</LocalizedLink>。
- 跨專案任務。
- <LocalizedLink href="/guides/features/projects/synthesized-files">跨專案資源存取器</LocalizedLink>範本

請注意，插件旨在作為擴展 Tuist 功能的簡易途徑。因此需考量若干限制，詳見**及** ：

- 一個外掛程式不能依賴另一個外掛程式。
- 外掛程式不得依賴第三方 Swift 套件
- 外掛程式不得使用其宿主專案的專案描述輔助函式。

若需更靈活的處理方式，可考慮為工具建議新增功能，或基於 Tuist
的生成框架自行開發解決方案：[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator)。

## 外掛類型{#plugin-types}

### 專案描述輔助外掛程式{#project-description-helper-plugin}

`專案描述輔助程式插件由以下目錄構成：- 包含插件名稱宣告的 ``` 目錄- 內含 `Plugin.swift` 及 `` ` 清單檔案的
`ProjectDescriptionHelpers` 目錄- 存放輔助 Swift 檔案的 `` ` 目錄

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

`若需共享<LocalizedLink
href="/guides/features/projects/synthesized-files#resource-accessors">合成資源存取器</LocalizedLink>，可採用此類外掛程式。該外掛程式由以下目錄構成：-
包含宣告外掛名稱的 `Plugin.swift` 及 `` ` 清單檔案的 ``` 目錄- 存放資源存取器範本檔案的
`ResourceSynthesizers` 目錄（路徑：`` `）


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

範本名稱採用資源類型的駝峰式命名法：

| 資源類型  | 範本檔案名稱                   |
| ----- | ------------------------ |
| 字串    | 字串.模板                    |
| 資產    | Assets.stencil           |
| 屬性清單  | Plists.stencil           |
| 字型    | 字體.模板                    |
| 核心資料  | CoreData.stencil         |
| 介面建構器 | InterfaceBuilder.stencil |
| JSON  | JSON.stencil             |
| YAML  | YAML.stencil             |

在專案中定義資源合成器時，可指定外掛名稱以使用該外掛的範本：

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### 任務外掛程式 <Badge type="warning" text="deprecated" />{#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
任務外掛程式已廢棄。若您正在為專案尋找自動化解決方案，請參閱[這篇部落格文章](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)。
<!-- -->
:::

任務是符合命名規範的`$PATH`-exposed 可執行檔，可透過`tuist` 指令呼叫。其命名規則為`tuist-&lt;任務名稱&gt;`
。早期版本中，Tuist 曾在`tuist plugin` 下提供部分弱規範與工具，用於處理`build` 、`run` 、`test` 及`archive`
等由 Swift Packages 可執行檔所代表的任務，但因該功能增加工具維護負擔與複雜度，現已廢棄此特性。

若您曾使用 Tuist 分配任務，我們建議您建立您的
- 您可繼續使用隨每個 Tuist 發行版附帶的`ProjectAutomation.xcframework` ，透過以下邏輯存取專案圖：`let graph
  = try Tuist.graph()` 。此指令使用系統進程執行`tuist` 命令，並返回專案圖的記憶體表示形式。
- 為分配任務，建議在 GitHub 發行版中包含支援以下架構的胖二進位檔：`(arm64)` ` (x86_64)` 並使用
  [Mise](https://mise.jdx.dev) 作為安裝工具。若要指示 Mise 如何安裝您的工具，需建立外掛程式儲存庫。可參考
  [Tuist's](https://github.com/asdf-community/asdf-tuist) 作為範例。
- 若將工具命名為`tuist-{xxx}` ，使用者可透過執行`mise install` 安裝。安裝後可直接執行，或透過`tuist xxx` 間接調用。

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
我們計劃將以下模型整合為單一向下相容框架，該框架將完整呈現專案圖譜供使用者使用：`ProjectAutomation` ` XcodeGraph`
此外，我們將提取生成邏輯至新層級：`XcodeGraph` 此層級亦可供您在自建命令列介面中使用。可視其為打造專屬 Tuist 的基礎架構。
<!-- -->
:::

## 使用外掛程式{#using-plugins}

若要使用外掛程式，您必須將其新增至專案的
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
清單檔案中：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

若需在不同儲存庫的專案間重複使用外掛程式，可將外掛程式推送至 Git 儲存庫，並於 Tuist.swift 檔案（位於` ）的 ``` 區塊中引用：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

安裝完畢後，執行 ``tuist install` ` 將把插件存入全域快取目錄。

::: info NO VERSION RESOLUTION
<!-- -->
如您所知，我們不提供外掛程式版本解析功能。建議使用 Git 標籤或 SHA 值以確保可重現性。
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
使用專案描述輔助程式外掛時，包含輔助程式的模組名稱即為外掛名稱
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
