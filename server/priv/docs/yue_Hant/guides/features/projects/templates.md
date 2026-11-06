---
{
  "title": "模板",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "學習如何在 Tuist 中建立和使用模板，以在專案中產生程式碼。"
}
---
# 範本 {#templates}

喺已有既定架構嘅專案入面，開發人員可能想建立同專案一致嘅新元件或功能。用 `tuist scaffold` 就可以從範本生成檔案。你可以定義自己嘅範本，或者使用 Tuist 內置嘅範本。以下係一啲適合使用 scaffolding 嘅情況：

- 建立符合指定架構嘅新功能：`tuist scaffold viper --name MyFeature`。
- 建立新專案：`tuist scaffold feature-project --name Home`

> [!NOTE]
> **無強制規範**
>
> Tuist 唔會對你範本嘅內容同用途施加任何規範。唯一要求係將佢哋放喺指定目錄。


## 定義範本 {#defining-a-template}

要定義範本，你可以執行 <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link>，然後喺 `Tuist/Templates` 底下建立一個名為 `name_of_template` 嘅目錄嚟代表你嘅範本。範本需要一個清單檔案 `name_of_template.swift` 嚟描述範本。所以如果你要建立一個名為 `framework` 嘅範本，就應該喺 `Tuist/Templates` 建立一個新目錄 `framework`，並加入一個名為 `framework.swift` 嘅清單檔案，內容可以如下：


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

定義好範本之後，就可以透過 `scaffold` 指令嚟使用：

```bash
tuist scaffold name_of_template --name Name --platform macos
```

> [!NOTE]
> 由於 platform 係可選參數，我哋亦都可以唔加 `--platform macos` 參數嚟執行指令。


如果 `.string` 同 `.files` 提供嘅彈性不足，你可以透過 `.file` 選項使用 [Stencil](https://stencil.fuller.li/en/latest/) 範本語言。除此之外，你亦都可以使用此處定義嘅額外過濾器。

使用字串插值時，上面嘅 `\(nameAttribute)` 會解析為 `{{ name }}`。如果你希望喺範本定義中使用 Stencil 過濾器，可以手動撰寫該插值並加入任意過濾器。例如，你可以用 `{ { name | lowercase } }` 取代 `\(nameAttribute)`，以取得 name 屬性嘅小寫值。

你亦都可以使用 `.directory`，從而將整個資料夾複製到指定路徑。

> [!TIP]
> **專案描述輔助工具**
>
> 範本支援使用 <.localized_link href="/guides/features/projects/code-sharing">專案描述輔助工具</.localized_link>，以便喺不同範本之間重用代碼。
