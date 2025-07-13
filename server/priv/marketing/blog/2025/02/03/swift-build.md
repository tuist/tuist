---
title: "What Swift Build means for the Swift ecosystem"
category: "learn"
tags: ["Swift", "Ecosystem"]
excerpt: "In blog post we share our perspective on what Swift Build might mean for the Swift ecosystem, drawing from our extensive experience working with Xcode projects, and how it aligns with the plans we have for Tuist."
author: pepicrft
---

With the introduction of [Swift](https://www.swift.org/getting-started/), it became clear that Apple wanted the language to run everywhere. In the years that followed, we witnessed various initiatives aligned with that vision, such as frameworks like [Vapor](https://vapor.codes) enabling Swift to run on servers and support for compiling [Swift for embedded devices](https://www.swift.org/blog/embedded-swift-examples/). At the same time, this presented Apple with an interesting challenge: reconciling a world designed for Apple platforms with one where Apple is just one of many supported platforms.

This reconciliation effort had to happen at various levels, from frameworks to tooling. You might have seen Apple’s initiative to open-source [Foundation](https://github.com/swiftlang/swift-foundation). Foundation is so *"foundational"* to crafting software in Swift that Apple decided to decouple it from Apple platforms and make it open source.

One of the reconciliation layers that took longer to receive attention is the build system. With the recent announcement of [Swift Build](https://www.swift.org/blog/the-next-chapter-in-swift-build-technologies/), Apple has signaled that this is finally changing.

In this blog post, we’d like to provide our perspective into what this might mean for the ecosystem, drawing from our extensive experience working with Xcode projects, and how it aligns with the plans we have for Tuist. But first, let’s talk about build systems.

## Build Systems

A build system is software responsible for producing runnable or shareable software artifacts, such as a static library or a macOS app. Every modern programming language comes with a build system, typically integrated with other tools like test runners, formatters, or dependency managers. [Rust](https://www.rust-lang.org) has [Cargo](https://doc.rust-lang.org/cargo/), [Elixir](https://elixir-lang.org) has [Mix](https://hexdocs.pm/mix/Mix.html), and [Go](https://go.dev) has its `go` tool. In the Apple ecosystem, we have two: `xcodebuild` and [SwiftPM](https://github.com/swiftlang/swift-package-manager). This duality exists as a consequence of reconciling two worlds.

Build systems require a representation of a project, which can be codified in the build system using conventions, serializable configuration files like `Cargo.toml`, or a mix of both. In the case of `xcodebuild` and SwiftPM, projects are represented in the hardly-serializable `.pbxproj` format and `Package.swift` files, respectively.

**Build tools construct an in-memory representation of projects**, typically resembling a graph. With this graph in memory, the build system can not only compile the project but also analyze it, optimize it, or even provide a foundation for coding experiences like [language server protocols](https://en.wikipedia.org/wiki/Language_Server_Protocol) (LSPs).

In the Swift ecosystem, we’ve long had two graphs with significant overlap: one generic enough to work across many operating systems, and another tightly coupled to Apple’s OSs and Xcode. This resulted in duplicated efforts and challenges in delivering a great developer experience (DX). For years, the ecosystem suffered from features that either didn’t work, worked unreliably, or were simply slow.

## A unified graph

With [Swift Build](https://github.com/swiftlang/swift-build), Apple is unifying the build system and the graph used by both SwiftPM and Xcode. If the toolchain is a stack of layers, with the build system sitting at the bottom of SwiftPM and Xcode, this unification is akin to pushing that layer down to share it across both tools. We think this is a great idea.

Note that the formats remain different—on one side, you have Swift packages, and on the other, Xcode projects. These are converted into a Project Interchange Format (PIF) before being passed to the build system.

## The impact on developer experience

This unification will take time to fully materialize, but once it does, we believe the improvements to the developer experience will be unprecedented:

- **Faster rollout of improvements**: New features and improvements will only need to be implemented once, speeding up their availability.
- **Increased reliability**: Eliminating part of the reconciliation challenge should result in more reliable features, such as build determinism or SwiftUI previews.
- **Extensibility**: The new build system is designed to be extensible, making it easier for the community to add support for new platforms without directly contributing to the build system repository. Imagine selecting WebAssembly as a build destination directly from Xcode’s UI.
- **Build-time optimizations**: Apple is taking the opportunity to enable build-time optimizations similar to Bazel. Explicit modules were the first step in this direction, and the presence of a [CAS (Content Addressable Storage)](https://en.wikipedia.org/wiki/Content-addressable_storage) in the codebase suggests more optimizations are on the horizon.
- **Foundation for new coding experiences**: This unified build system can serve as a foundation for innovative coding experiences, pushing the boundaries of what’s possible in Xcode. AI is already proving that letting the market or ecosystem explore new ideas can be a catalyst for innovation.

We strongly recommend trying Swift Build in your projects and reporting any issues you encounter. Your feedback will help Apple refine this new foundation into something truly incredible.

## How it relates to our plans

Tuist aims to improve the experience of building apps by extending Apple’s toolchain. An extensible foundation is something we’re very excited about because it unlocks new opportunities that feel more mature and aligned with the platform.

While the foundation provides all the information needed to understand and optimize projects, improving projects often requires a more holistic view of the data—how it evolves over time and how it connects to work happening in places like GitHub. That’s where our strength lies. We bring the server infrastructure, standardize the data, make it accessible to you, and build useful server features on top of it. This allows you to focus on checking out the code and building your apps with Xcode—or maybe Cursor in the future.

Reverse-engineering the internals of Xcode’s build system or Xcode projects is something we’ve done for many years. The possibility of not having to do that anymore is amazing because **it frees up our creative energy to focus on other areas while supporting Apple in evolving this new open foundation.**

## The overlap between Swift Packages and Xcode Projects

You might have noticed that while the build system is being unified, there are still two formats with some overlap: Xcode projects and Swift packages. The former has its flaws, which have allowed us to build a thriving community at Tuist around generated projects. The latter is being used by many teams to address the shortcomings of Xcode projects. However, because Swift packages were never designed for this purpose, the developer experience starts to suffer at scale.

What will the future look like? It’s uncertain, but we doubt we’ll have two formats forever. Like `xcodebuild`, the Xcode project format was designed for Apple platforms and has accumulated a lot of legacy over the years, making it a nightmare to maintain at scale. On the other hand, Swift packages, where manifests need to be compiled and can easily introduce side effects, don’t seem ideal either—at least not without significant changes.

Perhaps we’ll see a Swift Build DSL, similar to Gradle’s [Kotlin DSL](https://docs.gradle.org/current/userguide/kotlin_dsl.html), specifically designed for declaring build graphs without side effects. This DSL could be evaluated so that changes in it translate to graph changes almost instantly, Or who knows... perhaps [PKL](https://github.com/apple/pkl) becomes the language. Regardless of the path, we at Tuist would love to see this developed in the open and would even like to take part in it if possible. We have many ideas from our experience understanding and optimizing Xcode projects that we’d love to contribute to the ecosystem.

## Closing words

This is a move worth celebrating. Every new component that Apple makes open source is an opportunity for diverse ideas to emerge and for the entire ecosystem to improve. So, thank you to everyone who made this possible. We couldn’t be more excited about it, and we’re eager to see what the future holds for Swift.
