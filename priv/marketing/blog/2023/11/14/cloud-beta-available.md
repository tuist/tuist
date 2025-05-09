---
title: "Tuist Cloud public beta is here"
category: "product"
tags: ["Swift", "Tuist Cloud", "Xcode"]
excerpt: "Tuist Cloud's public beta is here, offering innovative solutions for Xcode projects. Free for open-source, with exciting plans post-beta in 2024."
author: pepicrft
---

In our ongoing quest to revolutionize the world of Xcode development, we've moved beyond just addressing [XcodeProj](https://github.com/tuist/xcodeproj) conflicts and the complexities of modular project maintenance. We discovered that the explicit graphs provided by developers, enriched with our extensive knowledge and models, are vital in empowering teams to overcome a broad spectrum of challenges. These include **enhancing productivity and making strategic, healthful decisions for project evolution.** We've crafted [Tuist Cloud](https://tuist.io/cloud),  new extension of Tuist, tailored for teams aspiring to elevate their app development process while optimizing costs and time efficiency.

**I am thrilled to announce that Tuist Cloud is now entering its public beta phase, accessible for free to all Tuist users.**

## What is Tuist Cloud

### Transformative Binary Caching

Tuist Cloud **introduces an array of new workflows and enhancements**. Its flagship feature, binary caching, revolutionizes project graph management by caching targets as binaries, streamlining generated projects. This not only benefits local development but also extends its advantages to team members and CI environments, significantly reducing time and costs. Moreover, it seamlessly integrates with [Swift Packages](https://developer.apple.com/documentation/xcode/swift-packages) and soon, [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/), eliminating redundant target compilations in every clean build.

> We saw a huge benefit to using tuist locally for the last 6-8 months for project generation and modularisation, but Tuist Cloud is a game changer for us. We were actively considering moving to [Bazel](https://bazel.build) for extreme module caching as we will soon be scaling the team, I think Tuist saved us a lot of time not only on CI/Development but with the potential Bazel migration - [Alex Little](https://www.linkedin.com/in/alexanderjameslittle) - Head of iOS at [Lapse](https://www.lapse.com)

### Incremental Workflows: Bridging Environments

Our commitment extends to what we term **incremental workflows across environments**. Utilizing our fingerprinting technology, used in caching, we pinpoint precisely what needs building or testing. This approach is a game-changer for large codebases, where building and testing everything per commit prolongs feedback cycles. Tuist and Tuist Cloud identify and focus only on the impacted tests and targets, simplifying your workflow without the need for additional tools. We take over the complexity from your pipelines and automations, allowing you to concentrate on what truly matters.

### Empowering Teams with Actionable Data

In the realm of Xcode project evolution, teams often navigate blindly, lacking critical data for informed decision-making. Tuist Cloud aims to change this, by offering tools and metrics to help you with necessary changes to optimize caching efficiency, identify flaky tests impacting team productivity, and more. Our initial dashboard is just the beginning, as we plan to expand it with deeper insights and data based on what you, our users, need.

## Embrace Tuist Cloud Today

Embark on this journey with Tuist Cloud right now. Create an account and kickstart your project with a few simple commands:

```bash
tuist cloud auth
tuist cloud init
```

Once initialized, you can prime the cache with tuist cache warm, followed by project generation with tuist generate. Tuist defaults to using cache for dependencies, with options to target specific dependencies or opt-out of caching entirely:


```bash
tuist cache warm
tuist generate # Only dependencies from the cache
tuist generate MyTarget # Dependencies + MyTarget dependencies from the cache
tuist generate --no-cache # Disables the cache
```

## Next steps

We're excited for you to try Tuist Cloud and we'd love to hear what you think about it. It's important for us to get [**feedback from users**](mailto:contact@tuist.dev) like you as we continue to improve and evolve the tool. Don't forget to check out [the documentation](https://docs.tuist.io/cloud/get-started) to learn more about Tuist Cloud.

Please note that starting January 2024, after the beta period, Tuist Cloud will become a paid product. The pricing will be based on how much you use the cache, which is part of our plan to make sure Tuist can keep improving for a long time.

In addition, **Tuist Cloud will be free for open source projects**, which is our way of supporting the wider developer community.
