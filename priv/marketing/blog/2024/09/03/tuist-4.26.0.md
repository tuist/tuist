---
title: "Tuist 4.26.0: GitHub integration and a new command to find implicit dependencies"
category: "product"
tags: ["Releases"]
excerpt: "Learn more about the new features and improvements in Tuist 4.26.0."
author: pepicrft
---

[Tuist 4.26.0](https://github.com/tuist/tuist/releases/tag/4.26.0) is out, and we'd like to share with you the new features and improvements that come with it.

## Meeting developers where they are: GitHub integration

One of the principles we embrace at Tuist is to meet developers where they are.

- We chose Swift over [YAML](https://yaml.org/) for the manifest format because developers love writing in Swift. This choice also unlocks many possibilities that aren't achievable with YAML.
- We integrated with and aligned ourselves with the [Swift Package Manager](https://www.swift.org/documentation/package-manager/) because it has become the standard for managing dependencies in the Swift ecosystem.
- We added support for [binary caching](https://docs.tuist.io/guides/develop/build/cache) using Xcode project primitives instead of asking developers to change their build system.

**But where exactly are Xcode developers?** While they spend a large portion of their time in Xcode, they also spend significant time on platforms like [GitHub](https://github.com) or [Slack](https://slack.com), collaborating with their peers. **Should we meet them there?** We think so!

Traditionally, meeting developers on these platforms meant teams had to develop and maintain complex CI workflows that pushed data to these platforms. Although this approach worked, it exposed organizations to malicious actors because secrets were often revealed in CI workflows. Furthermore, the absence of a place to store data over time limited what teams could do with these integrations. **Imagine being notified when a pull request introduces a regression in build times** or **when a newly introduced test in the codebase is flaky.**

At Tuist, we had the most crucial element to enable this type of developer experience: [a server](https://docs.tuist.io/server/introduction/why-a-server) that persists information from your projects and runs over time. However, we were missing one key piece—the integration of our server with one of the platforms where developers spend most of their time, [GitHub](https://github.com). That’s why we’re excited to announce that Tuist now integrates with GitHub. With a simple command, you can connect your remote project with a GitHub repository.

```bash
tuist project update tuist/tuist --repository-url https://github.com/tuist/tuist
```

You also need to install the [Tuist GitHub app](https://github.com/marketplace/tuist) in your repository.

Once you integrate with GitHub, Tuist can automatically post your test results and previews that you can run with [a single click](/blog/2024/08/28/tuist-macos-app).

![A screenshot that shows a GitHub comment with some links to run previews and the results from running tests](/marketing/images/blog/2024/09/03/tuist-4.26.0/github-app-comment.png)

## Implicit dependencies: Developers' worst nightmare

Xcode can resolve dependencies implicitly. Imagine this scenario: a developer adds the following line to a source file:

```swift
import Network
```

Suddenly, the module containing that source file depends on Network. This seemingly small change is a frequent cause of build-time slowness and Xcode instability. Implicit dependencies introduce new variables that must be resolved, not only during the build process but also while editing—when you're trying to load SwiftUI previews or get LLDB to work. In other words, Xcode's editor and build system are unexpectedly faced with new questions that need quick, reliable, and deterministic answers. And this isn't something that's widely discussed.

Unfortunately, Tuist can't fix this issue due to how Xcode builds artifacts. However, many organizations that adopt Tuist report improved build times. This isn't because of Tuist itself but because the process of adopting Tuist often involves reviewing the dependency graph and converting implicit dependencies into explicit ones. Our frequent advice is to embrace explicitness as much as possible and remove uncertainties from the build system.

Since we can't configure Xcode's build system to disallow implicit dependencies and tweaking build settings didn't produce the desired results, we decided to add a new command that uses static code analysis to catch implicit dependencies. It won't catch every instance, but it will identify many of them. We hope this command helps you detect implicit dependencies early in your development process.

If you have a Tuist project, you can use the following command:

```bash
tuist inspect implicit-imports
```

The command will output any implicit imports it finds and fail if any are detected. Magic 🪄, right? Special thanks to [Gorbenko Roman](https://github.com/rofle100lvl) for leading the development of this feature. He's already planning an even tighter integration with Xcode.

## Other changes

- [Hilton Campbell](https://github.com/hiltonc) [added support](https://github.com/tuist/tuist/pull/6663) for detecting when dependencies are outdated and a `tuist install` is required.
- [Hilton Campbell](https://github.com/hiltonc) also [fixed](https://github.com/tuist/tuist/pull/6675) a bug that caused false positives reporting side effects with static dependencies.

## What's next

We are working on a new website, which we plan to release soon, and we are starting to work on [Tuist Workflows](https://docs.tuist.io/guides/develop/automate/workflows) and Swift-based automation solution that blurs environments, decouples organizations from proprietary CI YAMLs, and takes a CLI-first approach to automation. We expect the infrastructure and technology work required to enable this feature to be the foundation for many other features in the future.
