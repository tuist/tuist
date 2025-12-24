---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Selective testing · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing with `xcodebuild`."
}
---
# Xcode 项目{#xcode-project}

警告要求
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects">图斯特账户和项目</LocalizedLink>
<!-- -->
:::

您可以通过命令行有选择地运行 Xcode 项目的测试。为此，您可以在`xcodebuild` 命令前加上`tuist` - 例如，`tuist
xcodebuild test -scheme App` 。该命令会对您的项目进行散列，并在成功后持久化散列，以确定在未来的运行中发生了哪些变化。

在以后的运行中，`tuist xcodebuild test` 会透明地使用哈希值来过滤测试，只运行自上次成功运行测试以来发生变化的测试。

例如，假设依赖关系图如下：

- `FeatureA` 有测试`FeatureATests` ，并依赖于`核心`
- `FeatureB` 有测试`FeatureBTests` ，并依赖于`核心`
- `核心` 有测试`CoreTests`

`tuist xcodebuild test` 会有这样的表现：

| 行动                                 | 描述                                                  | 内部状态                                                      |
| ---------------------------------- | --------------------------------------------------- | --------------------------------------------------------- |
| `tuist xcodebuild test` invocation | 运行`CoreTests`,`FeatureATests` 和`FeatureBTests 中的测试` | `FeatureATests` 、`FeatureBTests` 和`CoreTests` 的哈希值被持久化。   |
| `功能A` 已更新                          | 开发人员修改目标代码                                          | 和以前一样                                                     |
| `tuist xcodebuild test` invocation | 运行`FeatureATests` 中的测试，因为它的哈希值已更改                   | `FeatureATests` 的新散列值被持久化                                 |
| `核心` 已更新                           | 开发人员修改目标代码                                          | 和以前一样                                                     |
| `tuist xcodebuild test` invocation | 运行`CoreTests`,`FeatureATests` 和`FeatureBTests 中的测试` | `FeatureATests` `FeatureBTests` ，以及`CoreTests` 的新散列值被持久化。 |

要在您的 CI 上使用`tuist xcodebuild test` ，请遵循
<LocalizedLink href="/guides/integrations/continuous-integration">持续集成指南</LocalizedLink>中的说明。

请观看以下视频，了解选择性测试的实际操作：

<iframe title="Run tests selectively in your Xcode projects" width="560" height="315" src="https://videos.tuist.dev/videos/embed/1SjekbWSYJ2HAaVjchwjfQ" frameborder="0" allowfullscreen="" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>
