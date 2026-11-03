---
{
  "title": "範本",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "學習如何在 Tuist 中建立和使用範本，以在專案中產生程式碼。"
}
---
# 範本 {#templates}

在已有既定架構的項目中，開發人員可能希望建立與項目一致的新元件或功能。使用 `tuist scaffold` 你可以從範本產生檔案。你可以定義自己的範本，或使用 Tuist 內建的範本。以下係一些適合使用 scaffolding 的情況：

- 建立符合指定架構的新功能：`tuist scaffold viper --name MyFeature`。
- 建立新項目：`tuist scaffold feature-project --name Home`

> [!NOTE]
> **非強制性**
>
> Tuist 不會對你範本的內容及用途施加限制。唯一要求係將它們放在指定目錄中。


## 定義範本 {#defining-a-template}

要定義範本，你可以執行 <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link>，然後在 `Tuist/Templates` 底下建立一個名為 `name_of_template` 的目錄來代表你的範本。範本需要一個描述範本的清單檔案 `name_of_template.swift`。因此，如果你要建立一個名為 `framework` 的範本，你應該在 `Tuist/Templates` 建立一個新目錄 `framework`，並加入一個名為 `framework.swift` 的清單檔案，內容可能如下：


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
> 由於 platform 係可選參數，我們亦可以唔帶 `--platform macos` 參數來執行指令。


如果 `.string` 同 `.files` 提供的彈性不足，你可以透過 `.file` 選項使用 [Stencil](https://stencil.fuller.li/en/latest/) 範本語言。此外，你亦可以使用此處定義的其他過濾器。

使用字串插值時，上面的 `\(nameAttribute)` 會解析為 `{{ name }}`。如果你想在範本定義中使用 Stencil 過濾器，可以手動使用該插值並加入任何你想要的過濾器。例如，你可以使用 `{ { name | lowercase } }` 代替 `\(nameAttribute)` 來取得 name 屬性的小寫值。

你亦可以使用 `.directory`，它可以將整個資料夾複製到指定路徑。

> [!TIP]
> **Project Description Helpers**
>
> 範本支援使用 <.localized_link href="/guides/features/projects/code-sharing">project description helpers</.localized_link>，以便在不同範本之間重複使用程式碼。
