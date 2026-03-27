---
{
  "title": "Templates",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use templates in Tuist to generate code in your projects."
}
---
# 範本{#templates}

在有既定架構的專案中，開發人員可能希望開機新元件或功能與專案一致。透過`tuist scaffold` ，您可以從模板產生檔案。您可以定義自己的範本或使用
Tuist 提供的範本。這些是腳手架可能有用的一些情況：

- 建立遵循給定架構的新功能：`tuist scaffold viper --name MyFeature` 。
- 建立新專案：`tuist scaffold feature-project --name Home`

::: info NON-OPINIONATED
<!-- -->
Tuist 對於您的範本內容以及您使用範本的目的不持任何意見。它們只被要求在特定目錄中。
<!-- -->
:::

## 定義範本{#defining-a-template}

若要定義模板，您可以執行 <LocalizedLink href="/guides/features/projects/editing">`tuist edit`</LocalizedLink> ，然後在`Tuist/Templates` 下建立一個名為`name_of_template`
的目錄，代表您的模板。模板需要一個描述模板的清單檔案`name_of_template.swift` 。因此，如果您要建立一個名為`framework`
的範本，您應該在`Tuist/Templates` 下建立一個新目錄`framework` ，並建立一個名為`framework.swift`
的manifest 檔案，其內容可以如下所示：


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

## 使用範本{#using-a-template}

定義範本之後，我們可以從`scaffold` 指令使用它：

```bash
tuist scaffold name_of_template --name Name --platform macos
```

::: info
<!-- -->
由於 platform 是可選的參數，我們也可以在不使用`--platform macos` 參數的情況下呼叫指令。
<!-- -->
:::

如果`.string` 和`.files` 不能提供足夠的靈活性，您可以透過`.file` 的情況，利用
[Stencil](https://stencil.fuller.li/en/latest/) 模板語言。除此之外，您也可以使用在此定義的其他篩選器。

使用字串插值法，上面的`\(nameAttribute)` 將解析為`{{ name }}` 。如果您想在模板定義中使用 Stencil
過濾器，您可以手動使用該插值，並添加任何您喜歡的過濾器。例如，您可以使用`{ { name | 小寫 }}` 而不是`\(nameAttribute)` 來取得
name 屬性的小寫值。

您也可以使用`.directory` ，它提供了複製整個資料夾到指定路徑的可能性。

::: tip PROJECT DESCRIPTION HELPERS
<!-- -->
模板支援使用 <LocalizedLink href="/guides/features/projects/code-sharing">專案描述輔助程式</LocalizedLink> 來跨模板重複使用程式碼。
<!-- -->
:::
