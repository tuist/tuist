---
{
  "title": "Implicit imports",
  "titleTemplate": ":title · Inspect · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to find implicit imports."
}
---
# 隐式导入 {#implicit-imports}

为了减轻在原始 Xcode 项目中维护 Xcode
项目图的复杂性，苹果在设计构建系统时允许隐式定义依赖关系。这意味着，即使不明确声明依赖关系，产品（例如应用程序）也可以依赖于框架。在小范围内，这样做没有问题，但随着项目图的复杂性增加，隐含性可能会表现为不可靠的增量构建或基于编辑器的功能（如预览或代码完成）。

问题在于，你无法阻止隐式依赖的发生。任何开发人员都可以在自己的 Swift 代码中添加`import` 语句，然后就会创建隐式依赖关系。这就是 Tuist
的作用所在。Tuist 提供了一条命令，可通过静态分析项目中的代码来检查隐式依赖关系。以下命令将输出项目的隐式依赖关系：

```bash
tuist inspect implicit-imports
```

如果命令检测到任何隐式导入，它将以 0 以外的退出代码退出。

> [提示] 在 CI 中验证
> 我们强烈建议在每次向上游推送新代码时，将此命令作为<LocalizedLink href="/guides/features/automate/continuous-integration">持续集成</LocalizedLink>命令的一部分运行。

> [重要] 并非所有隐含情况都会被检测到 由于 Tuist 依靠静态代码分析来检测隐含依赖关系，因此可能无法捕捉到所有情况。例如，Tuist
> 无法通过代码中的编译器指令理解条件导入。
