---
{
  "title": "Implicit imports",
  "titleTemplate": ":title · Inspect · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to find implicit imports."
}
---
# 隐式导入{#implicit-imports}

为减轻维护原始Xcode项目图的复杂性，苹果设计了允许隐式定义依赖关系的构建系统。这意味着产品（例如应用程序）可依赖框架，而无需显式声明依赖关系。在小规模项目中这尚可接受，但随着项目图复杂度增加，隐式依赖可能导致增量构建不可靠，或影响基于编辑器的功能（如预览或代码补全）。

问题在于无法阻止隐式依赖关系的产生。任何开发者都可能在Swift代码中添加`import`
语句，从而创建隐式依赖。Tuist正是在此发挥作用。它提供命令通过静态分析项目代码来检查隐式依赖关系。以下命令将输出项目的隐式依赖：

```bash
tuist inspect dependencies --only implicit
```

若命令检测到任何隐式导入，则以非零退出代码退出。

::: tip VALIDATE IN CI
<!-- -->
我们强烈建议将此命令作为<LocalizedLink href="/guides/features/automate/continuous-integration">持续集成</LocalizedLink>流程的一部分，在每次向上游推送新代码时执行。
<!-- -->
:::

::: warning NOT ALL IMPLICIT CASES ARE DETECTED
<!-- -->
由于Tuist依赖静态代码分析来检测隐式依赖关系，可能无法捕捉所有情况。例如，Tuist无法理解代码中通过编译器指令实现的条件导入。
<!-- -->
:::
