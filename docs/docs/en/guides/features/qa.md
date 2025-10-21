---
{
  "title": "QA",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "AI-powered testing agent that tests your iOS apps automatically with comprehensive QA coverage."
}
---
# QA {#qa}

::: warning EARLY PREVIEW
<!-- -->
Tuist QA is currently in early preview. Sign up at [tuist.dev/qa](https://tuist.dev/qa) to get access.
<!-- -->
:::

Quality mobile app development relies on comprehensive testing, but traditional approaches have limitations. Unit tests are fast and cost-effective, yet they miss real-world user scenarios. Acceptance testing and manual QA can capture these gaps, but they're resource-intensive and don't scale well.

Tuist's QA agent solves this challenge by simulating authentic user behavior. It autonomously explores your app, recognizes interface elements, executes realistic interactions, and flags potential issues. This approach helps you identify bugs and usability problems early in development while avoiding the overhead and maintenance burden of conventional acceptance and QA testing.

## Prerequisities {#prerequisites}

To start using Tuist QA, you need to:
- Set up uploading <LocalizedLink href="/guides/features/previews">Previews</LocalizedLink> from your PR CI workflow, which the agent can then use for testing
- <LocalizedLink href="/guides/integrations/gitforge/github">Integrate</LocalizedLink> with GitHub, so you can trigger the agent directly from your PR

## Usage {#usage}

Tuist QA is currently triggered directly from a PR. Once you have a preview associated with your PR, you can trigger the QA agent by commenting `/qa test I want to test feature A` on the PR:

![QA trigger comment](/images/guides/features/qa/qa-trigger-comment.png)

The comment includes a link to the live session where you can see in realtime the QA agent's progress and any issues it finds. Once the agent completes its run, it will post a summary of the results back to the PR:

![QA test summary](/images/guides/features/qa/qa-test-summary.png)

As part of the report in the dashboard, which the PR comment links to, you will get a list of issues and a timeline, so you can inspect how the issue exactly happened:

![QA timeline](/images/guides/features/qa/qa-timeline.png)

You can see all QA runs that we do for our <LocalizedLink href="/guides/features/previews#tuist-ios-app">iOS app</LocalizedLink> in our public dashboard: https://tuist.dev/tuist/tuist/qa

::: info
<!-- -->
The QA agent runs autonomously and cannot be interrupted with additional prompts once started. We provide detailed logs throughout the execution to help you understand how the agent interacted with your app. These logs are valuable for iterating on your app context and testing prompts to better guide the agent's behavior. If you have feedback about how the agent performs with your app, please let us know through [GitHub Issues](https://github.com/tuist/tuist/issues), our [Slack community](https://slack.tuist.dev) or our [community forum](https://community.tuist.dev).
<!-- -->
:::

### App context {#app-context}

The agent might need more context about your app to be able to navigate it well. We have three types of app context:
- App description
- Credentials
- Launch argument groups

All of them can be configured in the dashboard settings of your project (`Settings` > `QA`).

#### App description {#app-description}

App description is for providing extra context about what your app does and how it works. This is a long-form text field that is passed as part of the prompt when kicking off the agent. An example could be:

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### Credentials {#credentials}

In case the agent needs to sign in to the app to test some features, you can provide credentials for the agent to use. The agent will fill in these credentials if it recognizes that it needs to sign in.

#### Launch argument groups {#launch-argument-groups}

Launch argument groups are selected based on your testing prompt before running the agent. For example, if you don't want the agent to repeatedly sign in, wasting your tokens and runner minutes, you can specify your credentials here instead. If the agent recognizes that it should start the session signed in, it will use the credentials launch argument group when launching the app.

![Launch argument groups](/images/guides/features/qa/launch-argument-groups.png)

These launch arguments are your standard Xcode launch arguments. Here's an example for how to use them to automatically sign in:

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
