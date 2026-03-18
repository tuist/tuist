---
{
  "title": "Implicit imports",
  "titleTemplate": ":title · Inspect · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to find implicit imports."
}
---
# 隐式导入{#implicit-imports}

为简化原始 Xcode 项目中项目图的维护复杂度，Apple
设计了允许隐式定义依赖关系的构建系统。这意味着某个产品（例如应用程序）可以依赖某个框架，即使未显式声明该依赖关系。在小规模项目中，这种设计尚可，但随着项目图复杂度的增加，这种隐式依赖可能会导致增量构建不可靠，或影响预览、代码补全等基于编辑器的功能。

问题在于无法阻止隐式依赖的产生。任何开发者都可以在 Swift 代码中添加`import` 语句，从而创建隐式依赖。这就是 Tuist
派上用场的地方。Tuist 提供了一条命令，通过静态分析项目中的代码来检查隐式依赖。以下命令将输出项目的隐式依赖：

```bash
tuist inspect dependencies --only implicit
```

如果该命令检测到任何隐式导入，则会以非零退出代码退出。

::: tip VALIDATE IN CI
<!-- -->
我们强烈建议您在每次将新代码推送到上游时，将此命令作为
<LocalizedLink href="/guides/features/automate/continuous-integration">持续集成</LocalizedLink>
流程的一部分执行。
<!-- -->
:::

::: warning NOT ALL IMPLICIT CASES ARE DETECTED
<!-- -->
由于 Tuist 依赖静态代码分析来检测隐式依赖关系，因此可能无法捕获所有情况。例如，Tuist 无法识别代码中通过编译器指令实现的条件导入。
<!-- -->
:::
