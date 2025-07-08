---
title: "Debugging the communication between Xcode and XCBBuildService"
category: "engineering"
tags: ["oss", "devtools"]
excerpt: "Learn how to debug the communication between Xcode and XCBBuildService with XCBLoggingBuildService."
author: pepicrft
---

Xcode and `xcodebuild` use an internal service named `XCBBuildService` to perform build tasks. The contract between Xcode and `XCBBuildService` has been leveraged by some organizations, such as to proxy calls to other build systems like [Bazel](https://bazel.build). More recently, Apple has utilized it to add support for their new build system, [swift-build](https://github.com/swiftlang/swift-build), which we discussed in [this blog post](/blog/2025/02/03/swift-build).

As a developer, this is generally not something you need to worry about. However, at Tuist, understanding this system has been on our backlog for some time, as we wanted to explore introducing optimizations and telemetry at a lower layer of the build process. The introduction of `swift-build` has shifted our focus, as it now makes more sense for us to explore that layer.

While working with one of Tuist's customers, we observed some unusual behaviors, including Xcode projects and `xcodebuild` processes hanging, without a clear explanation. This prompted us to investigate the communication between Xcode and `XCBBuildService` and build a small utility to help debug it.

> XCBBuildService has been recently [open sourced](https://forums.swift.org/t/evolving-swiftpm-builds-with-swift-build/77596/23) and rebranded as SWBBuildService.

## The Format

Xcode spawns `XCBBuildService` as a system process and communicates with it through standard pipelines. Messages are formatted using [MessagePack](https://msgpack.org/index.html), a format similar to JSON but smaller and faster.

The types of messages exchanged can be found in the Mobile Native Foundation's [XCBBuildServiceProxyKit](https://github.com/MobileNativeFoundation/XCBBuildServiceProxyKit/tree/main/Sources) project or in the [`SWBProtocol`](https://github.com/swiftlang/swift-build/tree/main/Sources/SWBProtocol) target of `swift-build`. Among others, you will find messages for:

- Requesting indexing information
- Pinging the service
- Listing the available sessions (since multiple can exist)
- Starting a build operation
- Notifying about the completion of a build operation

As mentioned earlier, you do not directly interact with these messages. Xcode and `xcodebuild`, acting as presentation layers, translate these internals into a debuggable UI or CLI output.

## Debugging Messages with XCBLoggingBuildService

To facilitate debugging this communication, we built a new Swift package, [XCBLoggingBuildService](https://github.com/tuist/XCBLoggingBuildService). It serves as a simple wrapper around `XCBBuildService`, logging the messages exchanged between Xcode and the service.

You can use it with Xcode or `xcodebuild` by following these steps:

First, clone and build the project the repository:

```bash
git clone https://github.com/tuist/XCBLoggingBuildService
swift build
```

You can then use it with **xcodebuild** or **Xcode**

```bash
# xcodebuild
XCBBUILDSERVICE_PATH=$(pwd)/.build/debug/XCBLoggingBuildService xcodebuild ...

# Xcode
env XCBBUILDSERVICE_PATH=$(pwd)/.build/debug/XCBLoggingBuildService /Applications/Xcode.app/Contents/MacOS/Xcode
```

The logs are saved in /tmp/XCBLoggingBuildService.log. You can monitor them in real time using:

```bash
tail -f /tmp/XCBLoggingBuildService.log
```

## What's next

In the coming months, we'll explore the internals of swift-build, its extensibility, and the capabilities it offers for Tuist to optimize your projects and enhance telemetry for better decision-making. Of course, we'll document our learnings in this blog.
