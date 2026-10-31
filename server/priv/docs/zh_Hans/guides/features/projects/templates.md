---
{
  "title": "模板",
  "titleTemplate": ":title · 项目 · 功能 · 指南 · Tuist",
  "description": "了解如何在 Tuist 中创建和使用模板，以在你的项目中生成代码。"
}
---
# 模板 {#templates}

在已有明确架构的项目中，开发者可能希望引导生成与项目保持一致的新组件或功能。使用 `tuist scaffold` 可以从模板生成文件。你可以定义自己的模板，也可以使用 Tuist 内置的模板。以下是一些适合使用脚手架的场景：

- 创建遵循指定架构的新功能：`tuist scaffold viper --name MyFeature`。
- 创建新项目：`tuist scaffold feature-project --name Home`

> [!NOTE]
> **非强制约定**
>
> Tuist 不对模板的内容及其用途施加任何强制约定。唯一的要求是将它们放在特定目录中。


## 定义模板 {#defining-a-template}

要定义模板，可以运行 <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link>，然后在 `Tuist/Templates` 下创建一个名为 `name_of_template` 的目录来表示你的模板。模板需要一个清单文件 `name_of_template.swift` 来描述模板。因此，如果你要创建一个名为 `framework` 的模板，应该在 `Tuist/Templates` 处创建一个新目录 `framework`，并在其中放置一个名为 `framework.swift` 的清单文件，示例如下：


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

定义模板后，可以通过 `scaffold` 命令使用它：

```bash
tuist scaffold name_of_template --name Name --platform macos
```

> [!NOTE]
> 由于 platform 是可选参数，我们也可以在不带 `--platform macos` 参数的情况下调用该命令。


如果 `.string` 和 `.files` 提供的灵活性不足，你可以通过 `.file` 情形借助 [Stencil](https://stencil.fuller.li/en/latest/) 模板语言。此外，你还可以使用此处定义的额外过滤器。

使用字符串插值时，上面的 `\(nameAttribute)` 会被解析为 `{{ name }}`。如果你希望在模板定义中使用 Stencil 过滤器，可以手动编写该插值并添加任意过滤器。例如，你可以使用 `{ { name | lowercase } }` 而不是 `\(nameAttribute)` 来获取 name 属性的小写值。

你还可以使用 `.directory`，它支持将整个文件夹复制到指定路径。

> [!TIP]
> **ProjectDescription 辅助工具**
>
> 模板支持使用 <.localized_link href="/guides/features/projects/code-sharing">ProjectDescription 辅助工具</.localized_link>，以便在多个模板之间复用代码。
