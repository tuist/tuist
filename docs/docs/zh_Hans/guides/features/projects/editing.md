---
{
  "title": "Editing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's edit workflow to declare your project leveraging Xcode's build system and editor capabilities."
}
---
# 编辑{#editing}

与传统的 Xcode 项目或 Swift 包（通过 Xcode 的用户界面进行更改）不同，Tuist 管理的项目是在**manifest 文件** 中包含的
Swift 代码中定义的。如果您熟悉 Swift 包和`Package.swift` 文件，那么这种方法非常相似。

您可以使用任何文本编辑器编辑这些文件，但我们建议您使用 Tuist 提供的工作流`tuist edit` 。该工作流会创建一个包含所有清单文件的 Xcode
项目，并允许您对其进行编辑和编译。由于使用了 Xcode，您可以获得**代码补全、语法高亮显示和错误检查** 的所有好处。

## 编辑项目{#edit-the-project}

要编辑项目，可以在 Tuist 项目目录或子目录下运行以下命令：

```bash
tuist edit
```

该命令会在全局目录下创建一个 Xcode 项目，并在 Xcode 中打开它。该项目包括一个`Manifests`
目录，您可以构建该目录以确保您的所有清单都是有效的。

::: info GLOB-RESOLVED MANIFESTS
<!-- -->
`tuist edit` 通过使用项目根目录（包含`Tuist.swift` 文件的目录）中的 glob`**/{Manifest}.swift`
来解析要包含的清单。确保项目根目录中有一个有效的`Tuist.swift` 。
<!-- -->
:::

### 忽略清单文件{#ignoring-manifest-files}

如果项目的子目录中包含与清单文件同名的 Swift 文件（如`Project.swift` ），而这些文件并非真正的 Tuist
清单，则可以在项目根目录下创建`.tuistignore` 文件，将其排除在编辑项目之外。

`.tuistignore` 文件使用 glob 模式指定应忽略的文件：

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

当测试夹具或示例代码恰好与 Tuist 清单文件使用相同的命名约定时，这一点尤其有用。

## 编辑和生成工作流程{#edit-and-generate-workflow}

您可能已经注意到，在生成的 Xcode 项目中无法进行编辑。这样做的目的是防止生成的项目依赖于 Tuist，从而确保您将来可以毫不费力地从 Tuist
迁移到其他项目。

在迭代项目时，我们建议在终端会话中运行`tuist edit` 以获取 Xcode 项目来编辑项目，然后使用另一个终端会话运行`tuist generate`
。
