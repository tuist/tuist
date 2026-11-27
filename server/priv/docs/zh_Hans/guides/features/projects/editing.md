---
{
  "title": "编辑",
  "titleTemplate": ":title · 项目 · 功能 · 指南 · Tuist",
  "description": "使用 Xcode 自动补全和构建验证功能编辑 Tuist 项目清单。"
}
---
# 编辑 {#editing}

与通过 Xcode 界面进行修改的传统 Xcode 项目或 Swift Package 不同，由 Tuist 管理的项目是在 **清单文件**中包含的 Swift 代码中定义的。如果你熟悉 Swift Package 和 `Package.swift` 文件，这种方法非常相似。

你可以使用任何文本编辑器来编辑这些文件，但我们建议使用 Tuist 提供的工作流，即 `tuist edit`。该工作流会创建一个包含所有清单文件的 Xcode 项目，并允许你编辑和编译它们。借助 Xcode，你可以获得 **代码补全、语法高亮和错误检查**的所有优势。

## 编辑项目 {#edit-the-project}

要编辑你的项目，你可以在 Tuist 项目目录或子目录中运行以下命令：

```bash
tuist edit
```

该命令会在全局目录中创建一个 Xcode 项目并在 Xcode 中打开它。该项目包含一个 `Manifests` 目录，你可以构建该目录以确保所有清单都有效。

> [!NOTE]
> **通过 Glob 解析的清单**
>
> `tuist edit` 通过使用项目根目录（包含 `Tuist.swift` 文件的目录）中的 glob `**/{Manifest}.swift` 来解析要包含的清单。请确保项目根目录下有一个有效的 `Tuist.swift`。


### 忽略清单文件 {#ignoring-manifest-files}

如果你的项目在并非实际 Tuist 清单的子目录中包含与清单文件同名（例如 `Project.swift`）的 Swift 文件，你可以在项目根目录下创建一个 `.tuistignore` 文件，将它们从编辑项目中排除。

`.tuistignore` 文件使用 glob 模式来指定应忽略哪些文件：

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

当你拥有恰好使用与 Tuist 清单文件相同命名约定的测试夹具或示例代码时，这尤其有用。

## 编辑和生成工作流 {#edit-and-generate-workflow}

你可能已经注意到，无法从生成的 Xcode 项目中进行编辑。这是有意为之的设计，目的是防止生成的项目依赖于 Tuist，从而确保你将来可以轻松地从 Tuist 迁移。

在迭代项目时，我们建议在一个终端会话中运行 `tuist edit` 以获取用于编辑项目的 Xcode 项目，并使用另一个终端会话运行 `tuist generate`。
