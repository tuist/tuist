---
{
  "title": "隐式导入",
  "titleTemplate": ":title · 检查 · 项目 · 功能 · 指南 · Tuist",
  "description": "了解如何使用 Tuist 查找隐式导入。"
}
---
# 隐式导入 {#implicit-imports}

为了降低使用原始 Xcode 项目维护 Xcode 项目图的复杂性，Apple 设计的构建系统允许隐式定义依赖。这意味着一个产品（例如 App）可以依赖于某个框架，即使没有显式声明该依赖。在小规模项目中，这没有问题，但随着项目图复杂度的增加，这种隐式性可能导致增量构建不可靠，或影响基于编辑器的功能，如预览和代码补全。

问题在于你无法阻止隐式依赖的产生。任何开发者都可以在其 Swift 代码中添加 `import` 语句，从而创建隐式依赖。这正是 Tuist 发挥作用的地方。Tuist 提供了一个命令，通过静态分析项目中的代码来检查隐式依赖。以下命令将输出你项目中的隐式依赖：

```bash
tuist inspect dependencies --only implicit
```

如果命令检测到任何隐式导入，它将以非零退出码退出。

> [!TIP]
> **在 CI 中验证**
>
> 我们强烈建议每次向上游推送新代码时，都将此命令作为 <.localized_link href="/guides/integrations/continuous-integration">持续集成</.localized_link> 流程的一部分运行。


> [!WARNING]
> **并非所有隐式情况都能被检测到**
>
> 由于 Tuist 依赖静态代码分析来检测隐式依赖，它可能无法捕获所有情况。例如，Tuist 无法理解通过代码中的编译器指令进行的条件导入。
