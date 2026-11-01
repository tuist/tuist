---
{
  "title": "範本",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何在 Tuist 中建立與使用範本，以在專案中產生程式碼。"
}
---
# 範本 {#templates}

在已有既定架構的專案中，開發者可能希望建立與專案一致的新元件或功能。使用 `tuist scaffold` 即可從範本產生檔案。你可以定義自己的範本，或使用 Tuist 內建的範本。以下是一些適合使用 scaffold 的情境：

- 建立符合指定架構的新功能：`tuist scaffold viper --name MyFeature`。
- 建立新專案：`tuist scaffold feature-project --name Home`

> [!NOTE]
> **不預設立場**
>
> Tuist 不會對範本的內容或用途施加任何限制，只要求它們位於特定目錄中。


## 定義範本 {#defining-a-template}

若要定義範本，可以執行 <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link>，然後在 `Tuist/Templates` 底下建立名為 `name_of_template` 的目錄來代表你的範本。範本需要一個描述範本的 manifest 檔案 `name_of_template.swift`。因此，如果你要建立名為 `framework` 的範本，應該在 `Tuist/Templates` 建立新的 `framework` 目錄，並在其中放置名為 `framework.swift` 的 manifest 檔案，內容可能如下：


```swift
import ProjectDescription

let nameAttribute: Template.Attribute = .required("name")

let template = Template(
    description: "Custom template",
    attributes: [
        nameAttribute,
        .optional("platform", default: "ios"),
    ],
    items: [
        .string(
            path: "Project.swift",
            contents: "My template contents of name \(nameAttribute)"
        ),
        .file(
            path: "generated/Up.swift",
            templatePath: "generate.stencil"
        ),
        .directory(
            path: "destinationFolder",
            sourcePath: "sourceFolder"
        ),
    ]
)
```

## 使用範本 {#using-a-template}

定義範本後，我們可以透過 `scaffold` 指令來使用它：

```bash
tuist scaffold name_of_template --name Name --platform macos
```

> [!NOTE]
> 由於 platform 是選用引數，我們也可以在不加上 `--platform macos` 引數的情況下呼叫該指令。


如果 `.string` 和 `.files` 提供的彈性不足，你可以透過 `.file` 情況利用 [Stencil](https://stencil.fuller.li/en/latest/) 範本語言。此外，你也可以使用此處定義的其他過濾器。

使用字串插值時，上述的 `\(nameAttribute)` 會解析為 `{{ name }}`。如果你希望在範本定義中使用 Stencil 過濾器，可以手動撰寫該插值並加入任意過濾器。例如，你可以使用 `{ { name | lowercase } }` 取代 `\(nameAttribute)`，以取得 name 屬性的全小寫值。

你也可以使用 `.directory`，它能將整個資料夾複製到指定路徑。

> [!TIP]
> **Project Description Helpers**
>
> 範本支援使用 <.localized_link href="/guides/features/projects/code-sharing">project description helpers</.localized_link>，以便在不同範本之間重複使用程式碼。
