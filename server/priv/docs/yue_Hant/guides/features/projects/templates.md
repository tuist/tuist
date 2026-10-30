---
{
  "title": "範本",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何喺 Tuist 建立同使用範本，為你嘅專案產生代碼。"
}
---
# 模板 {#templates}

在已有架構的項目中，開發人員可能希望建立與項目一致的新元件或功能。使用 `tuist scaffold` 你可以從模板生成檔案。你可以定義自己的模板，或使用 Tuist 內建的模板。以下是一些適合使用 scaffolding 的情境：

- 建立遵循指定架構的新功能：`tuist scaffold viper --name MyFeature`。
- 建立新項目：`tuist scaffold feature-project --name Home`

> [!NOTE]
> **非強制性**
>
> Tuist 不會對你的模板內容及用途施加限制。唯一要求是將它們放在特定目錄中。


## 定義模板 {#defining-a-template}

要定義模板，你可以執行 <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link>，然後在 `Tuist/Templates` 下建立一個名為 `name_of_template` 的目錄來代表你的模板。模板需要一個描述模板的清單檔案 `name_of_template.swift`。因此，如果你要建立一個名為 `framework` 的模板，你應該在 `Tuist/Templates` 建立一個新目錄 `framework`，並在其中放入名為 `framework.swift` 的清單檔案，內容可能如下：


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

## 使用模板 {#using-a-template}

定義模板後，我們可以透過 `scaffold` 指令來使用它：

```bash
tuist scaffold name_of_template --name Name --platform macos
```

> [!NOTE]
> 由於 platform 是選用參數，我們也可以在不加入 `--platform macos` 參數的情況下呼叫該指令。


如果 `.string` 和 `.files` 提供的彈性不足，你可以透過 `.file` 情況利用 [Stencil](https://stencil.fuller.li/en/latest/) 模板語言。此外，你也可以使用此處定義的其他過濾器。

使用字串插值時，上面的 `\(nameAttribute)` 會解析為 `{{ name }}`。如果你想在模板定義中使用 Stencil 過濾器，可以手動使用該插值並加入任何你喜歡的過濾器。例如，你可以使用 `{ { name | lowercase } }` 而非 `\(nameAttribute)` 來取得 name 屬性的小寫值。

你也可以使用 `.directory`，它可以將整個資料夾複製到指定路徑。

> [!TIP]
> **Project Description Helpers**
>
> 模板支援使用 <.localized_link href="/guides/features/projects/code-sharing">project description helpers</.localized_link>，以便在不同模板之間重複使用程式碼。
