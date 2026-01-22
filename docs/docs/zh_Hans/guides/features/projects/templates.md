---
{
  "title": "Templates",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use templates in Tuist to generate code in your projects."
}
---
# 模板{#templates}

在架构成熟的项目中，开发者可能需要初始化与项目风格一致的新组件或功能。通过执行 ``tuist scaffold`
`，可从模板生成文件。您既可自定义模板，也可使用Tuist内置模板。以下场景中可能需要使用模板生成功能：

- 创建遵循指定架构的新功能：`tuist scaffold viper --name MyFeature`
- 创建新项目：`tuist scaffold feature-project --name Home`

::: info NON-OPINIONATED
<!-- -->
Tuist 对模板内容及用途不作限制，仅要求存放于指定目录。
<!-- -->
:::

## 定义模板{#defining-a-template}

要定义模板，可运行 <LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink>，然后在`Tuist/Templates` 下创建名为`name_of_template` 的目录作为模板根目录。
模板需包含描述文件（`name_of_template.swift），该文件位于` 。例如创建名为`framework`
的模板时，应在`Tuist/Templates` 下新建目录`framework` ，并创建名为`framework.swift` 的描述文件，其内容示例如下：


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

定义模板后，可通过`框架的` 命令调用：

```bash
tuist scaffold name_of_template --name Name --platform macos
```

信息
<!-- -->
由于平台参数为可选项，我们也可省略`--platform macos` 参数直接调用该命令。
<!-- -->
:::

若`.string` 和`.files` 无法满足需求，可通过`.file` 案例使用
[Stencil](https://stencil.fuller.li/en/latest/) 模板语言。此外，还可使用此处定义的附加过滤器。

使用字符串插值时，`\(nameAttribute)` 将解析为`{{ name }}` 。若需在模板定义中使用 Stencil
过滤器，可手动进行插值并添加任意过滤器。例如，可使用`{ { name | lowercase } }` 替代`\(nameAttribute)` 以获取
name 属性的小写值。

您也可使用`.directory` ，该功能支持将整个文件夹复制到指定路径。

::: tip PROJECT DESCRIPTION HELPERS
<!-- -->
模板支持使用
<LocalizedLink href="/guides/features/projects/code-sharing">项目描述辅助工具</LocalizedLink>
在不同模板间复用代码。
<!-- -->
:::
