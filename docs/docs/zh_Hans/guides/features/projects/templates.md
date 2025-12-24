---
{
  "title": "Templates",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use templates in Tuist to generate code in your projects."
}
---
# 模板{#templates}

在具有既定架构的项目中，开发人员可能希望引导与项目一致的新组件或功能。通过`tuist scaffold`
，您可以从模板生成文件。您可以定义自己的模板，也可以使用 Tuist 提供的模板。这些是脚手架可能有用的一些情况：

- 创建遵循给定架构的新功能：`tuist scaffold viper --name MyFeature` 。
- 创建新项目：`tuist scaffold feature-project --name Home`

::: info NON-OPINIONATED
<!-- -->
Tuist 对模板的内容和用途没有任何意见。它们只被要求放在特定的目录中。
<!-- -->
:::

## 定义模板{#defining-a-template}

要定义模板，可以运行 <LocalizedLink href="/guides/features/projects/editing">`tuist edit`</LocalizedLink>，然后在`Tuist/Templates` 下创建一个名为`name_of_template`
的目录，代表你的模板。模板需要一个清单文件`name_of_template.swift` 来描述模板。因此，如果您要创建一个名为`framework`
的模板，则应在`Tuist/Templates` 下创建一个新目录`framework` ，并创建一个名为`framework.swift`
的清单文件，该文件可以如下所示：


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

## 使用模板{#using-a-template}

定义模板后，我们可以通过`scaffold` 命令使用它：

```bash
tuist scaffold name_of_template --name Name --platform macos
```

信息
<!-- -->
由于平台是一个可选参数，我们也可以调用该命令而不使用`--platform macos` 参数。
<!-- -->
:::

如果`.string` 和`.files` 的灵活性不够，您可以通过`.file` 使用
[Stencil](https://stencil.fuller.li/en/latest/) 模板语言。除此之外，您还可以使用此处定义的其他过滤器。

使用字符串插值法，上述`\(nameAttribute)` 将解析为`{{ name }}` 。如果想在模板定义中使用 Stencil
过滤器，可以手动使用插值法并添加任何过滤器。例如，您可以使用`{ { name | 小写 }}}` 而不是`\(nameAttribute)` 来获取 name
属性的小写值。

您还可以使用`.directory` 将整个文件夹复制到指定路径。

::: tip PROJECT DESCRIPTION HELPERS
<!-- -->
模板支持使用 <LocalizedLink href="/guides/features/projects/code-sharing"> 项目描述助手</LocalizedLink>，以便在不同模板之间重复使用代码。
<!-- -->
:::
