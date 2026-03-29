---
{
  "title": "QA",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "AI-powered testing agent that tests your iOS apps automatically with comprehensive QA coverage."
}
---
# QA{#qa}

::: warning EARLY PREVIEW
<!-- -->
Tuist QA 目前处于早期预览阶段。请访问 [tuist.dev/qa](https://tuist.dev/qa) 注册以获取访问权限。
<!-- -->
:::

高质量的移动应用开发依赖于全面的测试，但传统方法存在局限性。单元测试虽然快速且经济高效，却无法涵盖真实的用户场景。验收测试和人工质量保证（QA）可以弥补这些不足，但它们资源消耗大且难以扩展。

Tuist 的 QA
代理通过模拟真实用户行为来解决这一难题。它会自主探索您的应用，识别界面元素，执行真实的交互操作，并标记潜在问题。这种方法有助于您在开发早期发现 bug
和可用性问题，同时避免了传统验收和 QA 测试带来的额外开销和维护负担。

## 先决条件{#prerequisites}

要开始使用 Tuist QA，您需要：
- 在 PR CI 工作流中设置上传
  <LocalizedLink href="/guides/features/previews">预览</LocalizedLink>，以便测试人员进行测试
- <LocalizedLink href="/guides/integrations/gitforge/github">将</LocalizedLink>与
  GitHub 集成，以便您可以直接从拉取请求（PR）中触发代理

## 用法 {#usage｝

Tuist QA 目前可直接从 PR 触发。当您的 PR 关联了预览后，您可以在 PR 上评论`/qa test I want to test feature
A` 来触发 QA 代理：

![QA 触发注释](/images/guides/features/qa/qa-trigger-comment.png)

该评论包含一个实时会话链接，您可通过该链接实时查看 QA 代理的运行进度及其发现的任何问题。代理完成运行后，会将结果摘要发布回 PR：

![QA 测试摘要](/images/guides/features/qa/qa-test-summary.png)

作为仪表盘报告的一部分（PR 评论中提供了该报告的链接），您将获得一份问题列表和时间线，以便您可以查看问题确切的发生过程：

![QA 时间线](/images/guides/features/qa/qa-timeline.png)

您可在我们的公开仪表盘查看所有针对<LocalizedLink href="/guides/features/previews#tuist-ios-app">iOS应用</LocalizedLink>的质量保证测试：https://tuist.dev/tuist/tuist/qa

信息
<!-- -->
QA 代理会自主运行，一旦启动便无法通过额外提示中断。
我们在整个执行过程中会提供详细的日志，以帮助您了解代理与您的应用如何交互。这些日志对于迭代应用上下文和测试提示词非常有价值，有助于更好地引导代理的行为。如果您对代理在您的应用中的表现有任何反馈，请通过
[GitHub Issues](https://github.com/tuist/tuist/issues)、我们的 [Slack
社区](https://slack.tuist.dev) 或 [社区论坛](https://community.tuist.dev) 告知我们。
<!-- -->
:::

### 应用上下文{#app-context}

为了更好地操作您的应用，代理可能需要更多应用背景信息。我们提供三种应用背景类型：
- 应用描述
- 凭证
- 启动参数组

所有这些设置均可在项目的仪表板设置中进行配置（`Settings` >`QA` ）。

#### 应用描述{#app-description}

应用描述用于提供有关应用功能及工作原理的补充说明。这是一个长文本字段，在启动智能助手时会作为提示词的一部分传递。例如：

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### 凭证{#credentials}

如果测试人员需要登录应用以测试某些功能，您可以提供登录凭据供其使用。当测试人员识别出需要登录时，系统会自动填入这些凭据。

#### 启动参数组{#launch-argument-groups}

在运行代理之前，会根据您的测试提示选择启动参数组。例如，如果您不希望代理反复登录，从而浪费您的令牌和运行器时间，可以在此处指定凭据。如果代理识别到应以登录状态启动会话，它将在启动应用时使用凭据启动参数组。

![启动参数组](/images/guides/features/qa/launch-argument-groups.png)

这些启动参数是标准的 Xcode 启动参数。以下是一个示例，展示如何使用它们实现自动登录：

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
