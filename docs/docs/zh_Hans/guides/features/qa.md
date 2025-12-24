---
{
  "title": "QA",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "AI-powered testing agent that tests your iOS apps automatically with comprehensive QA coverage."
}
---
# 质量保证{#qa}

::: warning EARLY PREVIEW
<!-- -->
Tuist QA 目前处于早期预览阶段。登录 [tuist.dev/qa](https://tuist.dev/qa) 获取访问权限。
<!-- -->
:::

高质量的移动应用开发依赖于全面的测试，但传统方法存在局限性。单元测试速度快、成本低，但会遗漏真实的用户场景。验收测试和人工质量保证可以捕捉到这些差距，但它们需要大量资源，而且不能很好地扩展。

Tuist 的 QA
代理通过模拟真实的用户行为解决了这一难题。它可以自主探索您的应用程序，识别界面元素，执行真实的交互，并标记潜在的问题。这种方法可以帮助您在开发早期识别错误和可用性问题，同时避免传统验收和质量保证测试的开销和维护负担。

## 先决条件{#prerequisites}

要开始使用 Tuist QA，您需要
- 从 PR CI 工作流程中设置上传 <LocalizedLink href="/guides/features/previews">预览 </LocalizedLink>，然后代理就可以使用这些预览进行测试了
- <LocalizedLink href="/guides/integrations/gitforge/github">与 GitHub 集成</LocalizedLink>，因此您可以直接从 PR 触发代理

## 用法 {#usage｝

Tuist QA 目前可直接从 PR 触发。一旦您的 PR 关联了预览，您就可以通过在 PR 上注释`/qa test I want to test
feature A` 来触发 QA 代理：

[质量保证触发评论](/images/guides/features/qa/qa-trigger-comment.png)。

注释中包含一个实时会话链接，您可以实时查看质量保证代理的进度和发现的任何问题。代理完成运行后，会将结果摘要发回 PR：

![质量保证测试摘要](/images/guides/features/qa/qa-test-summary.png)!

作为公关评论链接到的仪表板报告的一部分，您将获得问题列表和时间轴，以便查看问题的具体发生过程：

质量保证时间表](/images/guides/features/qa/qa-timeline.png)。

您可以在我们的公共控制面板中查看我们为<LocalizedLink href="/guides/features/previews#tuist-ios-app">iOS 应用程序</LocalizedLink>进行的所有 QA 运行： https://tuist.dev/tuist/tuist/qa

信息
<!-- -->
质量保证代理可自主运行，启动后不会被其他提示打断。我们会在整个执行过程中提供详细的日志，帮助您了解代理是如何与您的应用程序交互的。这些日志对于迭代应用程序上下文和测试提示以更好地指导代理行为非常有价值。如果您对代理如何执行您的应用有任何反馈，请通过
[GitHub Issues](https://github.com/tuist/tuist/issues)、[Slack
社区](https://slack.tuist.dev) 或[社区论坛](https://community.tuist.dev)告知我们。
<!-- -->
:::

### 应用程序背景{#app-context}

代理可能需要更多关于您应用程序的上下文，以便能够很好地导航。我们有三种应用程序上下文：
- 应用程序说明
- 证书
- 启动争论小组

所有这些都可以在项目的仪表板设置中进行配置 (`Settings` >`QA`)。

#### 应用程序说明{#app-description}

应用程序描述用于提供有关应用程序功能和工作原理的额外信息。这是一个长格式文本字段，在启动代理时作为提示的一部分传递。举例如下

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### 证书{#credentials}

如果代理需要登录应用程序来测试某些功能，您可以提供凭证供代理使用。如果代理意识到需要登录，就会填写这些凭据。

#### 启动争论小组{#launch-argument-groups}

启动参数组是根据运行代理前的测试提示选择的。例如，如果不想让代理重复登录，浪费令牌和运行时间，可以在此处指定凭据。如果代理认为它应该以登录方式启动会话，那么它将在启动应用程序时使用凭据启动参数组。

![启动参数组](/images/guides/features/qa/launch-argument-groups.png)!

这些启动参数是标准的 Xcode 启动参数。下面是一个如何使用它们自动登录的示例：

```swift
import ArgumentParser
import SwiftUI

@main
struct TuistApp: App {
    var body: some Scene {
        ContentView()
        #if DEBUG
            .task {
                await checkForAutomaticLogin()
            }
        #endif
    }
    /// When launch arguments with credentials are passed, such as when running QA tests, we can skip the log in and
    /// automatically log in
    private func checkForAutomaticLogin() async {
        struct LaunchArguments: ParsableArguments {
            @Option var email: String?
            @Option var password: String?
        }

        do {
            let parsedArguments = try LaunchArguments.parse(Array(ProcessInfo.processInfo.arguments.dropFirst()))

            guard let email = parsedArguments.email,
                  let password = parsedArguments.password
            else {
                return
            }

            try await authenticationService.signInWithEmailAndPassword(email: email, password: password)
        } catch {
            // Skipping automatic log in
        }
    }
}
```
