---
title: "Why you might want to generate your Xcode projects in 2025"
category: "product"
tags: ["project-generation", "modularization"]
excerpt: "Learn why Xcode project generation is still relevant in 2025."
author: pepicrft
---

With Apple unifying and open-sourcing the [build system](https://www.swift.org/blog/the-next-chapter-in-swift-build-technologies/) across SwiftPM and Xcode, and [Xcode 16](https://developer.apple.com/documentation/xcode-release-notes/xcode-16-release-notes) addressing the frequent Git conflicts, you might wonder about the continued relevance of project generation. In this guide, we'll explore the current landscape and share our optimistic vision for the future of the ecosystem.

## The challenges of modular Xcode projects

Managing a modular Xcode project in 2025 still presents unique challenges. At scale, configuring the right build settings and phases to link frameworks, libraries, and copy dynamic modules becomes increasingly complex. When your project contains dozens or even hundreds of modules, visualizing the dependency graph to make informed changes becomes difficult.

We've observed that your projects might occasionally compile successfully due to the build system sharing derived data across build steps. However, this can lead to unexpected issues with debugging tools or SwiftUI previews.

As applications expand to offer more products and support multiple platforms, **modularization becomes not just beneficial but necessary.** It's a sound architectural practice that enables you to use Swift access levels to define clear boundaries, making your applications more maintainable and allowing the compiler to optimize code effectively.

## The industry's response

The ecosystem is actively addressing these challenges. The growing adoption of SwiftPM as a project manager demonstrates developers' desire for simpler solutions to complex modular projects. While SwiftPM brings clarity by avoiding the complexities of "build phases" or "build settings" terminology, it represents an evolving approach that continues to mature.

Companies like [Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2) have contributed valuable insights by openly sharing benchmarks about developer experience challenges with large modular codebases using SwiftPM. These conversations are crucial for driving improvements in the ecosystem.

## Project generation: Enhancing accessibility and performance

Since 2017, we've been working to address these challenges, first by creating [XcodeProj](https://github.com/tuist/XcodeProj) for working with `.pbxproj` files, then developing Tuist as a project generator. Other tools like [XcodeGen](https://github.com/yonaskolb/XcodeGen) emerged with different approaches, giving developers options based on their specific needs.

In 2025, project generation continues to play a vital role by:

- Making modular codebase management at scale accessible to all developers
- Optimizing build times through features like [cache](https://docs.tuist.dev/en/guides/develop/cache) without requiring the complexity of systems like Bazel

For teams dealing with extended CI turnaround times—sometimes exceeding an hour—these optimizations transform the development workflow and dramatically improve productivity.

## An optimistic future

The future looks promising for iOS development tooling. The new [swift-build](https://www.swift.org/blog/the-next-chapter-in-swift-build-technologies/) system, with the [swift-driver](https://github.com/swiftlang/swift-driver)'s content-addressable store (CAS), suggests that Apple is actively working on addressing core optimization challenges.

While we can't predict exactly how SwiftPM will evolve, Apple has both the expertise and resources to revolutionize their development foundations by incorporating lessons from ecosystems like [Gradle](https://gradle.org) and [Bazel](https://bazel.build). The emergence of AI, LLMs, and innovative editors is creating exciting opportunities for Xcode to expand its capabilities and experiences.

At Tuist, we're committed to building a complementary productivity platform that extends these native foundations. We're continually expanding our feature set for standard Xcode projects, as demonstrated by our recent [selective testing for Xcode projects](/blog/2025/02/18/selective-testing-for-xcode-projects) feature.

The iOS development landscape is evolving rapidly, with multiple solutions working in tandem to create the best possible experience. As tools mature and new approaches emerge, developers will benefit from increased flexibility, improved performance, and smoother workflows.

If you're a developer, lead, or head of a mobile organization interested in designing a thriving development environment, [let's chat](https://cal.tuist.dev/team/tuist/tuist). We're always eager to learn from and support organizations in making app development the most enjoyable experience possible.
