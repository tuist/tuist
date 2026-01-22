---
{
  "title": "Templates",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use templates in Tuist to generate code in your projects."
}
---
# 範本{#templates}

在架構已確立的專案中，開發人員可能需要建立符合專案規範的新元件或功能。透過執行 ``tuist scaffold` `，即可從範本生成檔案。您可自訂範本或使用
Tuist 內建的範本。以下是架設工具可能派上用場的場景：

- 建立遵循指定架構的新功能：`tuist scaffold viper --name MyFeature`
- 建立新專案：`tuist scaffold feature-project --name Home`

::: info NON-OPINIONATED
<!-- -->
Tuist 對您的範本內容及其用途不作任何限制，僅要求存放於指定目錄中。
<!-- -->
:::

## 定義範本{#defining-a-template}

定義範本時，可執行 <LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink>，接著在`Tuist/Templates` 下建立名為`name_of_template` 的目錄作為範本根目錄。
範本需具備描述其內容的清單檔案，位於`name_of_template.swift` 。例如若要建立名為`framework`
的範本，應在`Tuist/Templates` 下建立新目錄`framework` ，並放置名為`framework.swift`
的清單檔案，內容可參照以下範例：


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

定義範本後，可透過 ``` 框架的 `` ` 指令使用：

```bash
tuist scaffold name_of_template --name Name --platform macos
```

::: info
<!-- -->
` 由於平台參數屬可選項目，我們亦可省略 ``--platform macos` 參數直接執行指令。
<!-- -->
:::

若`.string` 與`.files` 無法滿足需求，可透過`.file` 案例運用
[Stencil](https://stencil.fuller.li/en/latest/) 模板語言。此外，亦可使用此處定義的額外篩選器。

使用字串插值時，上述 ``\(nameAttribute)` ` 將解析為 ``{{ name }}``。若需在範本定義中使用 Stencil
濾鏡，可手動執行此插值並添加濾鏡。例如，欲取得名稱屬性的小寫值，可改用 ``{ { name | lowercase } }` ` 取代
``\(nameAttribute)` `。

您亦可使用`.directory` 指令，此功能可將整個資料夾複製至指定路徑。

::: tip PROJECT DESCRIPTION HELPERS
<!-- -->
範本支援使用
<LocalizedLink href="/guides/features/projects/code-sharing">專案描述輔助器</LocalizedLink>
於不同範本間重複使用程式碼。
<!-- -->
:::
