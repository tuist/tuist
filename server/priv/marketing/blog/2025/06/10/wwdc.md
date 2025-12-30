---
title: "Developer experience wins from WWDC25"
category: "learn"
tags: ["wwdc", "developers", "devx"]
excerpt: "Apple's WWDC25 brought exciting developer tooling updates: new UI testing capabilities, in-code playgrounds, explicit modules by default, and their own container CLI. Here's how we think about them at Tuist."
author: pepicrft
og_image_path: /marketing/images/blog/2025/06/10/wwdc/og.jpg
---

Having slept on all the WWDC announcements and while drinking my first morning coffee, I think it's time to share a curated list of the announcements we're most excited about and how they relate to our plans for Tuist. Ready?

What follows is a curated, non-exhaustive list in no particular order.

**We are developer tooling nerds, so expect the updates we're excited about to be focused on the developer experience.**

## New testing capabilities

In Xcode 26, Apple has invested heavily in tools for writing and debugging UI tests. From recording UI interactions and getting the code written for you, to built-in editor capabilities for adjusting the generated code—we think these new tools are amazing. They've also added support for recording videos of your UI tests during execution, so when you see the test results on completion, you can more easily debug what happened. This is much better than just looking at logs or execution traces. I recommend watching the talk [Record, replay, and review: UI automation with Xcode - WWDC25](https://developer.apple.com/videos/play/wwdc2025/344) to learn more about these improvements. Note that all these improvements only work with XCTest, but hopefully they'll make them work with Swift Testing soon.

Additionally, they added an API that allows you to catch `fatalError()` and `precondition()` calls from your tests, plus [an attachment](https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0009-attachments.md) API so you can attach information that might be relevant later for debugging tests.

We think these improvements are fantastic, and you might want to explore pairing their adoption with [Task Locals](https://developer.apple.com/documentation/swift/tasklocal) to scope state to each test. This way, you can take advantage of all the cores in your Apple Silicon to increase test performance through parallelization.

Having these capabilities is great for Tuist. While Apple focuses on improving their foundations and making them more capable, we go the extra mile by using those APIs to make them more accessible via the web. We make them even more useful by correlating them with information from other sources (like GitHub) and bringing insights close to where developers spend their time, like Slack. We'll soon extend our [insights](https://docs.tuist.dev/en/guides/develop/insights) feature to include insights from your test runs, surfacing the most relevant information from your test results and giving you the option to download the result bundle and open it with Xcode if you need to dive deeper.

## A new [#playground](https://mastodon.social/@iKyle/114656391320509011) macro

With LLMs presenting developers with an opportunity to rethink how we develop, Apple has noticed the need for an isolated space within your project where you can play with your project's code building blocks without going through the scheme-based compilation cycle. Think of this as previews, but for non-UI code.

Traditionally, SwiftUI previews have been known for being unreliable, especially in large modular projects with many implicit dependencies where the preview panel can't reliably build the part of the graph necessary for the preview to work. Will it be the same case for playgrounds? We'll see once people start using them.

Our feeling is that with the default move to explicit modules and the introduction of a content addressable store (CAS) (more on this later), these are steps toward making SwiftUI previews more reliable, and potentially in-code playgrounds too.

## Xcode improvements

Apple shipped many incremental improvements in Xcode. A few that caught our attention:

- They're tracking many more metrics from your production apps if users opt into them. They expanded the list of supported metrics and added recommendations based on what Apple considers a good baseline.
- Months ago, Apple unified and open-sourced the build system that powers Xcode and SwiftPM, taking the opportunity to make it extensible. While it's not very user-facing, users will benefit transitively through more reliability and performance since it eliminates the need to reconcile SwiftPM and Xcode's build systems (both use the same one now). This is great news for the ecosystem, and the best part is that it's open source.
- They're defaulting to explicit modules now, which should lead to faster and more reliable builds, and through CAS, optimizable builds in the future.

Apple is taking steps in what we believe is the right direction and gives us ideas for how Tuist should evolve to augment the new capabilities of these tools.

![A screenshot of Apple's presentation that shows how the new explicit module feature translates into 3 build phases: scan, build modules, build source](/marketing/images/blog/2025/06/10/wwdc/explicit-modules.jpeg)

## Container

Apple has released their own open-source CLI to run Linux containers on macOS: [container](https://github.com/apple/container). It's written in Swift and builds on another open-source project of theirs, [containerization](https://github.com/apple/containerization), which builds on Apple's virtualization framework. If you've used Docker or Podman before, they serve similar roles—you can start Linux containers from images. However, unlike Docker, containerization uses Apple's virtualization framework. This provides stronger isolation, as each container has its own kernel, reducing the risk of kernel-level attacks.

Thanks to their use of VIRTIO drivers, they can achieve fast boot times and low memory usage, making VMs nearly as lightweight as traditional containers.

I can't help but wonder why Apple invested in their own open-source solution when we already have Docker and Podman. But I guess as Swift spreads to other ecosystems like web servers or Swift executables that run on Linux OSs, controlling the developer experience of using Swift in those environments at a lower level makes sense.

If you want to give it a shot, you can install it and then run the following command to build your Swift package on Linux using Swift 6.1:

```bash
container run --rm -v "$(pwd)":/workspace -w /workspace swift:6.1 swift build
```

## Content Addressable Store (CAS)

When Apple open-sourced their unified [build system](https://github.com/swiftlang/swift-build), we were excited to see Apple investing in a [content addressable store](https://github.com/swiftlang/swift-build/tree/main/Sources/SWBCAS). We thought we'd see a bigger announcement this WWDC, but it was just a soft release, perhaps because it's not yet stable.

You might not be familiar with [the concept](https://en.wikipedia.org/wiki/Content-addressable_storage), but you're probably familiar with the consequences of the build system not having it and doing everything through derived data: unreliable incremental builds and features like SwiftUI previews. A build system with a content addressable store works such that for build tasks, it can get a fingerprint knowing all the inputs and outputs of a build task. If the build system can assume it has all the information about inputs and outputs, then it can calculate a hash and look up the result of a previous build task by that hash. The problem is that due to how Xcode projects and the build system are designed, they're not fully hermetic and support implicit imports, which means files being built might depend on something the build system doesn't know about, causing the build system with CAS to fail compilation.

So before we get there, we need to move to a hermetic world at the build system level with explicit modules. I believe this is why Apple has made explicit modules the default in Xcode 26. You can try to opt into CAS by setting the following build setting, but it failed for us in a recently-created project:

```bash
COMPILATION_CACHE_ENABLE_CACHING=YES
```

We believe this is a multi-year effort, but the future looks bright because it'll bring not only stability but also native build-time optimizations by sharing those artifacts across environments. Sounds familiar? Yes! This is what [Bazel](https://bazel.build/) does. At Tuist, we'll start investigating how we can hook into that system to provide the fastest latency possible, potentially partnering with some providers and enhancing those capabilities with the best and most actionable metrics to optimize projects further.

## Small bites

- The Xcode editor [annotates](https://mastodon.social/@jsq/114655965764298620) the end of compiler directives to show which directive they belong to.
- The attention to detail that Apple has put into Liquid Glass is quite impressive, and [this is a testament to that](https://community.tuist.dev/t/tuists-take-on-the-wwdc/612/2).
- Xcode download size [has decreased](https://developer.apple.com/videos/play/wwdc2025/247/) by 24% and workspace loading performance has been boosted by 40%. So if you have a large workspace, this is a reason to be happy.

## Things we theorized about that didn't happen

Last year we saw frequent git conflicts being mitigated with buildable folders, so we wondered if Apple would continue addressing long-lasting issues by finally settling on a user-facing graph format that's unified across apps and packages. Developers are pushing Swift packages to be that format, trying to run away from the inconveniences of Xcode projects. That push has manifested in Swift packages starting to look more like Xcode projects, but in a DSL that wasn't designed for that purpose—the format might suffer as a result.

Part of me was expecting to see a decision there. I saw some people mentioning a `Project.swift` file, but it didn't happen. My bet is that before we get there, we need better sandboxing capabilities, perhaps a subset of Swift that can be evaluated quickly, and a migration path for people to start adopting it. With [swift-build](https://github.com/swiftlang/swift-build) being open source, I think that's a natural next step.

We also wondered if Apple would do anything in the area of developer productivity, and while we see signs of that, it's still too early. Their toolchain is becoming more capable, but the legacy of past decisions—like the design of derived data, which led to many projects accidentally building—is a hard place to move from. But it's slowly happening.

Seeing these things being solved at a lower level would be great because we can focus our efforts on areas where Apple hasn't traditionally been good or shown interest—like making dev tools accessible via the web, or correlating their data with data from other places where developers spend time to provide new developer experiences that would be hard to imagine Apple building.

## Closing words

There are many more improvements that span platforms and areas, so we recommend checking them out on the developer platform or in the app. We believe the ecosystem is more thriving than ever, developer tools keep getting better, and we couldn't be more excited to keep augmenting these capabilities with integrations, new insights, and optimizations to make teams more productive.

**This post has been written by a human, and its grammar has been edited by [Claude Sonnet 4](https://www.anthropic.com/claude/sonnet)**
