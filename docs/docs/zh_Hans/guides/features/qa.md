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
Tuist QA 目前处于早期预览阶段。请访问 [tuist.dev/qa](https://tuist.dev/qa) 注册获取使用权限。
<!-- -->
:::

优质移动应用开发依赖全面测试，但传统方法存在局限。单元测试虽快速且成本效益高，却无法覆盖真实用户场景。验收测试和人工质量保证虽能弥补这些缺口，但资源密集且难以扩展。

Tuist的QA代理通过模拟真实用户行为解决此难题。它能自主探索应用程序，识别界面元素，执行真实交互，并标记潜在问题。这种方法有助于在开发早期发现缺陷和可用性问题，同时避免传统验收测试和质量保证测试带来的开销与维护负担。

## 先决条件{#prerequisites}

要开始使用 Tuist QA，您需要：
- 在PR
  CI工作流中设置上传<LocalizedLink href="/guides/features/previews">预览图</LocalizedLink>，供代理程序用于测试
- <LocalizedLink href="/guides/integrations/gitforge/github">将</LocalizedLink>与GitHub集成，以便您可直接从PR中触发代理

## 用法 {#usage｝

Tuist QA 当前可直接从 PR 触发。当 PR 关联预览后，您可在 PR 中通过评论`/qa test I want to test feature A`
触发 QA 代理：

![QA触发评论](/images/guides/features/qa/qa-trigger-comment.png)

该注释包含一个实时会话链接，您可通过该链接实时查看QA代理的运行进度及其发现的问题。代理完成运行后，将把结果摘要反馈至PR：

![QA测试摘要](/images/guides/features/qa/qa-test-summary.png)

作为仪表板报告的一部分（PR评论链接指向该报告），您将获得问题列表和时间线，以便查明问题确切的发生过程：

![QA时间线](/images/guides/features/qa/qa-timeline.png)

您可在我们的公开仪表盘查看所有针对<LocalizedLink href="/guides/features/previews#tuist-ios-app">iOS应用</LocalizedLink>的质量保证测试：https://tuist.dev/tuist/tuist/qa

信息
<!-- -->
QA代理程序启动后将自主运行，无法通过额外提示中断其进程。
我们提供详细的执行日志，助您理解代理与应用的交互过程。这些日志对迭代应用上下文和测试提示语至关重要，可优化代理行为引导。若您对代理在应用中的表现有反馈，请通过[GitHub
Issues](https://github.com/tuist/tuist/issues)、[Slack社区](https://slack.tuist.dev)或[社区论坛](https://community.tuist.dev)告知我们。
<!-- -->
:::

### 应用上下文{#app-context}

客服人员可能需要更多应用背景信息才能更好地操作。我们提供三类应用背景：
- 应用描述
- 凭证
- 启动参数组

所有设置均可在项目控制面板中配置（`设置` >`质量保证` ）。

#### 应用描述{#app-description}

应用描述用于提供关于应用功能及运作方式的补充说明。这是长文本字段，在启动智能体时作为提示的一部分传递。示例如下：

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### 凭证{#credentials}

若代理需登录应用测试某些功能，可提供凭证供其使用。当代理识别到需要登录时，将自动填写这些凭证。

#### 启动参数组{#launch-argument-groups}

启动参数组的选择基于您在运行代理前的测试提示。例如，若您不希望代理反复登录导致令牌和运行器分钟数浪费，可在此处指定凭据。当代理识别到应以登录状态启动会话时，将在应用启动时使用凭据启动参数组。

![启动参数组](/images/guides/features/qa/launch-argument-groups.png)

这些启动参数是标准的Xcode启动参数。以下是使用它们实现自动登录的示例：

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
