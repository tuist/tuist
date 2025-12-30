---
{
  "title": "Implicit imports",
  "titleTemplate": ":title · Inspect · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to find implicit imports."
}
---
# Implicit imports {#implicit-imports}

To alleviate the complexity of maintaining an Xcode project graph with raw Xcode project, Apple designed the build system in a way that allows dependencies to be implicitly defined. This means that a product, for example an app, can depend on a framework, even without declaring the dependency explicitly. At a small scale, this is fine, but as the project graph grows in complexity, the implicitness might manifest as unreliable incremental builds or editor-based features such as previews or code completion.

The problem is that you can't prevent implicit dependencies from happening. Any developer can add an `import` statement to their Swift code, and the implicit dependency will be created. This is where Tuist comes in. Tuist provides a command to inspect the implicit dependencies by statically analyzing the code in your project. The following command will output the implicit dependencies of your project:

```bash
tuist inspect implicit-imports
```

If the command detects any implicit imports, it exits with an exit code other than zero.

::: tip VALIDATE IN CI
<!-- -->
We strongly recommend to run this command as part of your <LocalizedLink href="/guides/features/automate/continuous-integration">continuous integration</LocalizedLink> command every time new code is pushed upstream.
<!-- -->
:::

::: warning NOT ALL IMPLICIT CASES ARE DETECTED
<!-- -->
Since Tuist relies on static code analysis to detect implicit dependencies, it might not catch all cases. For example, Tuist is unable to understand conditional imports through compiler directives in code.
<!-- -->
:::
