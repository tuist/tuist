---
title: "Our Swift CLI now runs on Linux"
category: "product"
tags: ["product", "linux"]
excerpt: "Tuist is no longer macOS-only. You can now run analytical workflows or leverage the upcoming Tuist Gradle support on Linux."
author: fortmarek
og_image_path: /marketing/images/blog/2026/02/16/linux/og.png
highlighted: true
---

Tuist has started as a macOS-only tool. That made sense when its scope was Xcode project generation and building your projects for Apple platforms. But Tuist has grown well beyond that. We now offer build and test insights, flaky test detection, build caching, and more. And we're adding [Gradle support](https://community.tuist.dev/t/tuist-is-coming-to-android/838), for example, for Android projects. Restricting the CLI to macOS no longer reflects what Tuist does or where developers need it.

That's why we're very excited to announce that the Tuist CLI runs on Linux.

## Why Linux matters

There are three main reasons we invested in Linux support:

- **Gradle on Android:** We're bringing Gradle project integration to Tuist. Android builds commonly run on Linux CI machines, and requiring macOS for a tool that manages Gradle projects would be a dealbreaker. Linux support makes Tuist viable for Android workflows out of the box.

- **Analytical workflows on CI:** Commands like `tuist test case list` don't need Xcode or macOS. They talk to the Tuist server, process data, and return results. Linux machines are typically much cheaper than macOS ones, so running analytical and data-ingestion workflows there is a straightforward cost saving.

- **Agentic environments:** AI coding agents are increasingly running in cloud environments that default to Linux. Whether it's an agent that checks build analytics, manages project settings, or automates test quarantining, it needs a CLI that runs where it lives. Linux support makes Tuist accessible in these agentic workflows without requiring a macOS VM.

## Supported commands

Not every command makes sense on Linux — commands like `tuist generate` or `tuist xcodebuild` inherently depend on Xcode and remain macOS-only. What does work on Linux are the commands that don't need Xcode: authentication, account and project management, analytical commands for browsing builds and test cases, cache configuration, and `tuist init` for scaffolding new projects. In short, anything that talks to the Tuist server or sets up your project works on Linux today.

## How we got here

Getting a Swift CLI to compile and run on Linux is not trivial. Here's how we approached it.

### Modularization and incremental migration

Before touching the Tuist CLI itself, we had already invested in Linux support across our open-source libraries, such as [Noora](https://github.com/tuist/Noora), our terminal UI framework, or [FileSystem](https://github.com/tuist/FileSystem), our file system abstraction. This meant the foundational layers were ready.

When we started to add Linux support, we knew we wanted to do so gradually by cross-compiling individual modules instead of doing everything in a single PR. And while Tuist was already heavily modularized, we still had a couple of monolith modules that mixed platform-specific and platform-independent code. `TuistSupport`, our shared utility layer, was broken into focused modules like `TuistConstants`, `TuistEnvironment`, and `TuistLogging`. `TuistKit`, which contained all the command logic, was split into per-command modules: `TuistAuthCommand`, `TuistCacheCommand`, `TuistBuildCommand`, and so on. Once separated, each module could independently target Linux compilation without pulling in macOS-only dependencies. That not only allowed for a gradual migration, but it allowed us to use compiler directives like `#if os(macOS)` and `#if canImport(...)` sparingly, keeping the code easier to read and maintain.

### Fully static binaries with musl

Our first Linux builds linked the Swift standard library and system libraries like `libcurl` dynamically, meaning the binary required the Swift runtime and matching system libraries on the target machine. Instead, we switched to Swift's [Static Linux SDK](https://www.swift.org/documentation/articles/static-linux-getting-started.html) which cross-compiles against [musl libc](https://musl.libc.org/) to produce fully static binaries with zero shared library dependencies:

```bash
swift sdk install https://download.swift.org/swift-6.1.2-release/static-sdk/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz
swift build --product tuist --configuration release --swift-sdk x86_64-swift-linux-musl
```

The resulting binary runs identically on Ubuntu, Fedora, Alpine, or any other Linux distribution. No dynamic linker, no shared libraries, no Swift installation required. The trade-off is a larger binary since everything is bundled in, but for a CLI tool that's distributed once and run many times, portability is worth it.

The switch to musl did require some code changes. The C library module is named `Musl` rather than `Glibc`, so platform imports became three-way:

```swift
#if canImport(Glibc)
    import Glibc
    let systemGlob = Glibc.glob
#elseif canImport(Musl)
    import Musl
    let systemGlob = Musl.glob
#elseif canImport(Darwin)
    import Darwin
    let systemGlob = Darwin.glob
#endif
```

### Distribution

We wanted the installation experience on Linux to be identical to macOS. Tuist is installed via [mise](https://mise.jdx.dev/), so we updated the [aqua-registry](https://github.com/aquaproj/aqua-registry) and [mise itself](https://github.com/jdx/mise/pull/8102) to recognize Tuist's Linux binaries. The result is that installing Tuist on Linux is the same single command you're already used to from macOS:

```bash
mise use -g tuist
```

## What's next

The Linux support is our first step outside of macOS and Apple platforms, but not the last one. We already have plans for support of:
- **Gradle**: We'll be officially releasing Gradle project integration soon, enabling Tuist to optimize and track Android builds.
- **Windows**: We'd like to bring Tuist to Windows as well. However, some of our transitive dependencies, like [swift-nio](https://github.com/apple/swift-nio/issues/2065) (used via our [FileSystem](https://github.com/tuist/filesystem) library), don't yet support Windows. We're keeping an eye on upstream progress and will revisit this as the Swift-on-Windows ecosystem matures.

If you're running CI on Linux or exploring cross-platform workflows, give the Linux CLI a try and let us know how it goes. Reach out to us in our [community forum](https://community.tuist.dev) or send us an email at [contact@tuist.dev](mailto:contact@tuist.dev) for sharing your feedback
