---
{
  "title": "Editing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's edit workflow to declare your project leveraging Xcode's build system and editor capabilities."
}
---
# 编辑{#editing}

与通过Xcode界面修改的传统Xcode项目或Swift包不同，Tuist管理的项目通过**清单文件中的Swift代码定义（**
）。若您熟悉Swift包及其`Package.swift文件（` ），此方法极为相似。

您可使用任意文本编辑器修改这些文件，但建议采用Tuist提供的编辑流程：`tuist edit`
。该流程会创建包含所有清单文件的Xcode项目，便于编辑和编译。借助Xcode，您可享受**代码补全、语法高亮及错误检查等全部功能** 。

## 编辑项目{#edit-the-project}

要编辑项目，可在 Tuist 项目目录或子目录中运行以下命令：

```bash
tuist edit
```

该命令会在全局目录中创建Xcode项目并通过Xcode打开。项目包含`Manifests` 目录，可通过构建确保所有清单文件有效。

::: info GLOB-RESOLVED MANIFESTS
<!-- -->
`tuist编辑` 通过全局模式`**/{Manifest}.swift` 解析项目根目录（包含`Tuist.swift`
文件的目录）中需包含的清单文件。请确保项目根目录下存在有效的`Tuist.swift` 文件。
<!-- -->
:::

### 忽略清单文件{#ignoring-manifest-files}

若项目中存在与清单文件同名的Swift文件（例如：`Project.swift`
），且这些文件位于非实际Tuist清单的子目录中，可在项目根目录创建`.tuistignore` 文件将其排除在编辑项目之外。

`` 文件通过通配符模式指定应忽略的文件：

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

当测试用例或示例代码恰好采用与Tuist清单文件相同的命名规范时，此规则尤为重要。

## 编辑并生成工作流{#edit-and-generate-workflow}

您可能已注意到，无法直接在生成的 Xcode 项目中进行编辑。此设计旨在避免生成的项目依赖 Tuist，确保您未来能轻松迁移至其他工具。

在迭代项目时，建议通过终端会话执行以下命令：`tuist edit` 以获取Xcode项目进行编辑，同时另开终端会话运行：`tuist generate`
