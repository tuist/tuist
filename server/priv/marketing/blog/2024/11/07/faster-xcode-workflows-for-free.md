---
title: "Speed up your Xcode CI workflows for free"
category: "product"
tags: ["Product"]
excerpt: "Discover how to significantly speed up your Xcode CI workflows without spending a dime. Learn about common challenges and how Tuist can help you overcome them, improving your development process and productivity."
author: pepicrft
---

It’s Monday. You show up to work, grab a coffee, attend the morning standup, and then you’re tasked with fixing a few minor design inconsistencies in the app you’re working on. "This should take five minutes," you think.

In a few moments, you have the fix ready in [SwiftUI](https://developer.apple.com/xcode/swiftui/). You run linters, format the code, and prepare a PR for review.

But then CI kicks in. The 100-module project needs to compile – and only after building the 30 external packages and parsing the [SwiftSyntax](https://github.com/swiftlang/swift-syntax) tree for dependencies. Fifteen minutes pass, and the project is still compiling. You scroll through Mastodon, make a latte, and come back half an hour later, expecting to see a green checkmark. But **CI is red**. Flaky tests strike again.

You don’t have the time (or the context) to dig into the flakiness, so you hit retry, check your emails, read a new Swift newsletter, and follow some rants about Swift's concurrency model. Finally, CI is green. But wait – there’s a conflict in `.pbxproj` because another PR was merged while you were away. Fixing that will take another 30 minutes.

After 1.5 hours, you get the green checkmark and can merge your PR. The five-minute task has taken over an hour. Welcome to Xcode development.

## Leadership weighs In

This is happening more often. Eventually, leadership asks questions. During your 1:1, your manager raises an important topic: [React Native](https://reactnative.dev/).

Leadership is concerned about the iOS team’s velocity compared to the web and Android teams, who adopted [Develocity](https://gradle.com/develocity/). As the team lead, you’re asked to weigh the costs and benefits of adopting React Native or other tools to catch up.

The team is skeptical about React Native. They’ve heard of companies that adopted it only to regret it, with valuable engineering resources diverted to support the migration. The app relies heavily on platform-specific features that would be cumbersome to handle in a cross-platform setup. In other words, enthusiasm is low.

At some point, you remember hearing about [Bazel](https://bazel.build/) at a conference. It replaces Xcode’s build system, caches steps, and runs tests selectively. But setting it up is complex and maintaining it could strain your team’s resources. You’ve also heard of companies reverting their Bazel setups because the people who implemented them left. Not ideal.

Migrating to SPM? Perhaps, but after reading [Bumble’s blog](https://medium.com/bumble-tech/scaling-ios-at-bumble-6f0602682903), you see that it introduces its own challenges. React Native starts to look like the most viable option, despite the cost.

## There must be a better way

This is a common scenario in the [Tuist community](https://community.tuist.io). Teams are frustrated with Xcode’s implicit configuration and the complications of managing a large build graph. Many try SPM, but this just adds another build graph to maintain. Sticking to the “Apple way” doesn’t always help either.

Xcode and Xcode projects are legacies. When configured well, they can be powerful tools for development. However, decisions made for convenience years ago now limit productivity, like linking binaries implicitly from system directories. It’s convenient – until it breaks and you’re waiting on a new Xcode update to fix it.

If only the build system were more explicit and flexible. This is where Tuist comes in. We might be new to you, but let me tell you: you can reduce these headaches for free. [Trendyol](https://www.youtube.com/watch?v=s9bqf01gciA&list=PLfCiO1zYKkAStEDxfttXZy4EJlPON4kYm&index=15) cut CI times by 70% by adopting Tuist, which improved developer happiness by making it easier to manage the project graph.

Giving Tuist a try could save you hours. While not widely talked about, it’s an [open-source solution](https://github.com/tuist/tuist) developed over seven years, trusted by large organizations to deliver software faster.

## Getting started with Tuist

Defining your project with Tuist’s Swift DSL feels natural and intuitive. The APIs mirror Xcode’s terminology, abstracting complex parts like linking dependencies and mapping build settings. Migrating the project only takes a week, and suddenly, builds are 20% faster – just from a cleaner, more explicit configuration.

Even LLDB, which had been flaky, starts working smoothly. And best of all, team members can now add or remove modules as needed. The platform team finally has a foundation for defining architecture and rules, giving everyone a productive development environment.

## Speeding Up Compilation and Testing

Remember the original problem of waiting 1.5 hours to merge a simple fix? While Tuist minimizes conflicts, flaky tests and slow compilation times remain issues. But Tuist has solutions for these too, without replacing Xcode or adding the complexity of cross-platform tools like React Native.

By signing up with `tuist auth`, creating a project with `tuist projects create`, and configuring your CI pipeline to use `tuist cache`, you enable caching for external Swift packages. In CI, Tuist reuses binaries, reducing those 30-minute waits to about five minutes. Tuist even caches test results, so only relevant tests run after code changes. It feels like magic.

## Going further with metrics and tripwires

Flakiness, cache inefficiencies, or bundle size increases can still arise. Tuist has built-in metrics and tripwires to prevent regressions. At the end of each run, you get a URL with a detailed project report:

```bash
tuist build
# ...some logs
Results: https://tuist.dev/tuist/tuist/runs/592368
```

## Use it for free

If these challenges sound familiar, consider giving Tuist a try. Our advanced features are available under a [free tier](/pricing), and you can explore with a small project by running tuist init. Even our team uses Tuist daily, leveraging Xcode projects to their fullest potential.

If you’d like to see Tuist in action, have questions, or want to discuss how it could transform your project, schedule a call with us. We’d love to help.

If you would like to see it live, ask us questions, or walk you through how Tuist could impact your project,
you can [schedule a call with us](https://cal.tuist.io/team/tuist/tuist) and we'll gladly help you.
