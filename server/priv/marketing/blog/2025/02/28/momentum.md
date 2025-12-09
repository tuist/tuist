---
title: "Momentum"
category: "product"
tags: ["productivity", "creativity"]
excerpt: "Protect your developers' momentum to build better apps."
author: pepicrft
---

Engineering resources are one of the most costly assets in any tech organization, hence the many conversations around AI taking their jobs or helping make more effective use of them. It's common to see organizations forming teams with names like "platform" or "core," which are responsible for ensuring teams closer to product are productive by providing them with optimized tools and workflows. Those teams are a human-powered "copilot" and can have a significant impact in meeting the needs of the organization. If you've tried to assemble IKEA furniture with a professional screwdriver as opposed to the provided tools, you'll likely know how much different and more productive the experience is.

## Productivity goes beyond efficiency

When we think of productivity, we tend to think of achieving something in less time. However, in creative jobs such as software crafting, when someone doesn't feel slowed down by the tools they use, they are also inspired to explore new ideas, which transitively benefit the business. In other words, unproductive environments are poor grounds for innovation.

**Developers' momentum is crucial**

This is why we are so interested in productivity in the app development space—it's the way to impact the quality of the apps that organizations put out there.

But staying productive while building for Apple platforms is a challenge. When an app is small—one or two targets, a few dependencies, one product, and one platform to support—it's all fine. But how realistic is that? Very unrealistic. Sooner than later, momentum blockers knock at your door:

- A new dependency that comes with a Swift macro significantly increasing your compilation times.
- Recurrent random compilation errors that only go away once you clean derived data and waste your time in a clean build.
- One-liner PRs that need more than half an hour to get CI feedback.
- Tests unrelated to your changes causing your PR CI to fail, forcing you to retry and wait for another half an hour.

The manifestation of all this is usually teams unable to match the speed of other platforms (e.g., web), leadership being extremely concerned about it, and radical decisions like adopting [React Native](https://reactnative.dev) or swapping the build system with something like [Bazel](https://bazel.build). Other times, if organizations can afford it, they throw more engineering resources at the problem, as if productivity were only directly correlated to the number of engineers. It's way more complex than that.

At Tuist, we love this domain. And the fact that Apple is not focused on this space makes app development productivity a sweet spot. I'm not writing this post to sell you Tuist, which of course I'd be happy if you do; I simply want to create awareness around the importance of protecting developers' momentum and what some common momentum drains are in app development.

In the following sections, I'll walk you through the most common momentum obstacles that we've seen in organizations:

## 1. Multi-repos

We've seen organizations, especially those with different products (i.e., multiple apps), scattering their targets across repositories. This comes with a versioning scheme and reliance on developers to follow it strictly (we are humans, we make mistakes). Changes are no longer atomic and span across repositories, releases need to be coordinated, and configuration needs to be made consistent through yet more tooling and processes (or alternatively, configuration becomes inconsistent across repos). Unless you have a strong need to share a piece of logic with other repositories or as an open source project, going down this path is a terrible idea. You'd be surprised to see how common this is in our industry.

What's the alternative? Monorepos. But monorepos make some classic assumptions and models fall apart. One of them is the idea that every commit should integrate everything in CI. That works fine if your monorepo is small, but if you change one line in app Foo, you don't want to be compiling app Bar in CI. This requires some investment on your end to be selective about what happens in CI, and this is something that Tuist helps you with. We selectively build and test based on the changes and try to optimize the process by reusing binaries across builds. This is what can make your 1-hour CI pipeline go down to minutes. Alternatively, you can make the investment yourself and leverage Git forge features like [CODEOWNERS](https://docs.github.com/en/repositories/managing-your-repositories-settings-and-features/customizing-your-repository/about-code-owners) to improve the experience of working with monorepos, but I assure you it's worth the investment. Much better than having changes scattered across many repositories.
## 2. Slow feedback loops

When you change something, you want to see it instantly. This instant feedback loop is what keeps your ideas energized and what makes you stay hours building new ideas into your apps. Sadly, this instant feedback loop gets easily disrupted by the Apple toolchain:

- A cryptic error in Xcode
- A failing LLDB
- A failing SwiftUI preview
- A slow compilation

We've normalized all the above, but that's too bad if you ask me. We need to fight back and be more critical about how terrible this is for the ecosystem. There's some work on Apple's side to tackle this by making things more explicit and bringing capabilities of modern build systems into Xcode's, but things move slower than what the ecosystem really needs. Resources are scarce, and issues continue to pile up. A new version of Xcode comes out fixing one issue but introduces a regression somewhere else. Everything seems to be moving faster and more reliably outside of Xcode.

What does it take to improve the feedback and ensure things work more reliably? Embrace explicitness and consistency in your projects. Refrain from adding compile-time complexity, for example through script build phases, Swift Macros, or embeddable frameworks. The simpler and more explicit the compilation graph, the better for the reliability and performance of Xcode's build system, debugging tools, and editor. One thing that we don't cease to repeat is that the existence of a feature in Xcode doesn't mean it's the most suitable option at scale. For instance, while Swift Macros are cool, we'd use them sparingly. Or build scripts are something we try to avoid.

Hopefully with the above, developers will have to clean derived data less frequently (yay!). And if you still want a boost of performance in your feedback loop, you might consider something like Tuist binary caching and selective testing, which works with vanilla projects.

## 3. Friction while previewing

You've built a new feature or just fixed something, and you want to share that with the rest of the team, your leads, or the product designers who designed the feature in the first place? In the web ecosystem, you'd get a preview in seconds and share a link with your team that they can add feedback to. The frictionless nature of the process is an invitation to other people to participate in the feedback loop and help you shape the best work you can.

The same is not true when developing apps for Apple platforms. Sharing the app from the PR? Unthinkable. Building it locally if I'm a developer reviewing the PR? Too slow. The result? Trusting CI on their checks and reviewing the architecture of the code. But if the latter is something AI is going to be very good at, and there are signs of that because GitHub just announced that Copilot can be a reviewer too, how can humans support there? By manually testing the app:

- It feels slow
- It looks off on my iPhone 16
- The animation has too much delay

We need to match the web there. But we have nightly builds, Pedro... Nightly builds are terrible for this. Once the nightly build is created, you've lost the context of what has gone into it. If you have feedback, suddenly you have a new problem that you didn't have before—figuring out what introduced the bug that you are seeing, who authored that PR, and communicating what you saw with that person. Do you notice? It's just pure madness. That's why when we saw many companies rushing to build an App Center replacement, which is the easiest thing to do when you are a business and want to get customers, we didn't bother. It's not the right solution to the needs developers have.

Developers need a quick way to build and run apps to previsualize changes. You can build your own solution, use [Shopify's tophat](https://shopify.engineering/shopify-tophat-mobile-developer-testing), or [use Tuist Previews](https://docs.tuist.dev/en/guides/features/previews), but once you have something like this and educate not just developers but everyone, you'll make everyone part of the development process, not just developers, and this is a unique strength that you can have as an organization to build better products.

If web has got this, we can have it in app development too.

Imagine being on a PR and commenting, "Can you build a preview for me?" Or even better, chatting with your LLM of choice and saying, "Can I try the latest changes from main?" and getting an email with a preview link. We'll get there, and [commoditization of virtualization](/blog/2025/02/12/vm) is a key piece in enabling this.

## 4. Complexities

In large modular Xcode projects, complexity gets in the way. Complex errors like "framework not found" that people can't debug lead to cleaning derived data. Teams wanting to introduce new dependencies in the graph and not understanding the consequences of their actions can lead to unexpected behavior and bugs in the app.

Some complexity is accidental, other is inherent. Regardless of the type of complexity, if you [don't compress it](https://www.youtube.com/watch?v=zKyv-IGvgGE&t=1037s), you'll have a team of frustrated developers who waste their creative energy figuring out their tools and processes as opposed to building better apps.

We are big fans of the Ruby and Ruby on Rails mantra of optimizing for developer happiness. Usually, complexities, while an exciting challenge to understand for engineers, diminish any happiness in the process. Therefore, we find it quite useful to identify where complexity lies to ask oneself, "Is this fun?"

This question drives many of the product decisions that we make at Tuist and helps us determine which complexities we need to compress:

- Managing and evolving Xcode projects is not fun: We conceptually compress it with a DSL.
- Waiting for half an hour to get feedback in a PR is not fun: We conceptually compress the complexities to optimize the processes (it's just one command, `tuist cache`).
- Signing successfully is not fun: We'll conceptually compress the intricacies of managing certificates and profiles and signing for teams.

Eliminating complexities to make development fun should be an [infinite game for teams](https://en.wikipedia.org/wiki/The_Infinite_Game). It's ours, so if you prefer to delegate that to us, we'd be glad to help.

## 5. Flaky tests

Flaky tests are non-deterministic tests—tests that sometimes pass and other times fail. Flaky tests are damn annoying. You open a PR, wait for a potentially slow CI to complete, just to see that a test unrelated to your changes failed. Then you retry because you are too busy and too far from that test to fix it, and move on. But someone else runs into the same issue, and another person too, and your team is wasting their time throughout the day. But it's all fine because your "test coverage" is high, and that's all that matters at the end of the day, right? I dare to say little to no flakiness is even better than high test coverage, which at the end of the day is not really an indicator of the quality of your tests or your business logic. This sounds too controversial, but I had to say it.

Flakiness is a momentum disruptor. A huge one. One that goes unnoticed and only becomes apparent when it's too serious.

And with Swift Testing encouraging parallelization, if you have flakiness in your codebase, it might become more apparent. Swift is not a functional programming language where state navigates deterministically in one direction. Global state will appear somewhere, making your tests and logic prone to race conditions, and voila—flakiness is there. If you think flakiness won't happen to you, think again.

Sadly, the tooling to address this is very scarce. Most of the tooling in the ecosystem consists of native apps, which don't have a shared globally accessible database where one can track how a test yields different results over time. Some CI platforms like [Buildkite](https://buildkite.com/resources/blog/fixing-flaky-tests/) provide a solution for it, but since they don't have an understanding of the graph, they approximate a fingerprint to determine if a test has changed or not, disregarding the dependencies of the test. Tuist is graph-aware, so we can precisely calculate that at the module level and provide teams with a [selective testing](https://docs.tuist.dev/en/guides/develop/selective-testing) solution that's very accurate. And we just recently added support for Xcode projects, so you can use it in your projects already.

## Closing thoughts

Your team is a valuable source of creative energy. Don't waste it. Really. Spend some time understanding what hampers their momentum, and invest in mitigating those factors. And if you need a hand with it, we'll be more than happy to help.

We are obsessed with making developers happy building apps, and we've made this our full-time job. Through our solutions, we've proved that abstracting the platform with something like React Native or replacing the build system with all the complexity of a build system like Bazel is not necessary. It's possible with your existing toolchain, believe us.
