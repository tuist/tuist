---
title: "Xcode's Content Addressable Storage: Building Cache at the Edge"
category: "product"
tags: ["Product", "Xcode", "Performance"]
excerpt: "Apple's introduction of Content Addressable Storage in Xcode marks a fundamental shift in build caching. Learn how this technology works, what it enables, and how Tuist is bringing cache to the edge for developers worldwide."
author: pepicrft
---

If you've been developing for Apple platforms long enough, you've probably found yourself in a familiar situation: something goes wrong with your build, nothing makes sense, and someone inevitably suggests "have you tried cleaning DerivedData?" It's become a meme in the iOS development community, but it points to a deeper truth-our build system has been showing its age.

For years, iOS and macOS developers have wrestled with DerivedData-Xcode's build output directory that has become synonymous with this troubleshooting ritual. While this approach served the ecosystem well in the early days when projects were smaller and teams were co-located, the limitations have become increasingly apparent. As projects grow in complexity, as teams become distributed across time zones, and as CI infrastructure becomes central to delivering quality software, the need for reliable, shareable build caching has moved from "nice to have" to "essential."

With the introduction of Content Addressable Storage (CAS), Apple is taking a fundamental step toward modern build caching. This isn't just an incremental improvement-it's a fundamental shift in how we think about build artifacts. In this post, we'll explore how CAS works under the hood, what it enables for distributed teams, and how Tuist is building infrastructure to make it viable for teams worldwide. But first, let's talk about why DerivedData became a problem in the first place.

## The DerivedData Problem

DerivedData stores build artifacts in a location-based structure. When Xcode builds your project, it places compiled objects, indexes, and intermediate build products in paths tied to your project's location and configuration. On the surface, this seems reasonable-put the outputs next to the inputs. But this seemingly simple design decision has created a cascade of problems as our development workflows have evolved.

Consider a typical scenario: you're working on a feature branch, building and testing locally. Your colleague in another time zone is working on a different feature. Your CI system is running builds for every pull request. All of you are compiling the same dependencies-maybe a large framework like [Alamofire](https://github.com/Alamofire/Alamofire) or a set of internal modules that rarely change. Yet each of you is doing this work independently, from scratch, because DerivedData can't safely share these artifacts.

Why not? The problems run deep:

**Non-deterministic builds**: The same source code compiled on different machines or in different locations can produce different artifacts. This isn't just theoretical-debug symbols contain absolute paths, frameworks reference their build location, and various metadata gets embedded during compilation. If you build on your MacBook Pro and I build on my Mac Studio, we get different bytes, even though the source code is identical. This makes caching across environments fragile at best and incorrect at worst.

**Path dependencies**: Artifacts often contain hardcoded absolute paths. Your framework compiled at `/Users/you/Projects/App` doesn't work when I try to use it at `/Users/me/Code/App`. These path references break when moved between machines or when the project is located in different directories. It's not just about where the framework is-it's about where it was built, where its dependencies were, where the SDK is installed. It's turtles all the way down.

**Coarse invalidation**: When something goes wrong-and something always eventually goes wrong-developers resort to deleting the entire DerivedData directory. Hours of compilation work, discarded in seconds, because there's no reliable way to determine which artifacts are still valid and which are corrupted or stale. We throw away the good with the bad because we can't tell them apart.

**Limited sharing**: These characteristics combine to make it nearly impossible to reliably share build artifacts across team members or between local development and CI environments. Some teams have tried-setting up shared network drives, syncing DerivedData directories, elaborate rsync scripts. These approaches are fragile and often cause more problems than they solve. The fundamental architecture just wasn't designed for this use case.

## Content Addressable Storage: Learning from the Industry

Apple's introduction of [Content Addressable Storage](https://en.wikipedia.org/wiki/Content-addressable_storage) represents a fundamental shift in how build artifacts are managed-a shift that build systems like [Bazel](https://bazel.build/) and [Gradle](https://gradle.org/) pioneered years ago. It's one of those ideas that seems obvious in retrospect but required years of experience with large-scale builds to fully appreciate.

The core insight is elegantly simple: instead of identifying artifacts by where they live, identify them by what they contain. In a content-addressable system, artifacts are identified by a cryptographic hash of their content rather than their location. When Xcode needs a compiled module, it asks: "Do we have an artifact with hash ABC123?" rather than "Is there a file at path X/Y/Z?"

This seemingly simple change has profound implications. If two developers compile the same code with the same compiler and the same settings, they produce identical bytes-and crucially, they produce the same hash. That hash becomes a globally unique identifier for that artifact. It doesn't matter where it was built, when it was built, or who built it. The content is the identity.

This is the same principle that powers [Git](https://git-scm.com/). When you commit code, Git doesn't store it at a particular path-it computes a hash and uses that hash as the identifier. You can clone a repository anywhere on any machine, and as long as the content is the same, the hashes match. It's provably the same code. CAS brings this same philosophy to build artifacts.

### Hermeticity

Bazel introduced the concept of [hermetic builds](https://bazel.build/basics/hermeticity): builds that depend only on declared inputs and produce deterministic outputs. With CAS, Xcode moves toward this model. Each artifact is uniquely identified by its content hash, which is derived from the source files, compiler version, build settings, and all transitive dependencies.

To achieve this, the build system must become more explicit about what goes into a build. No more depending on environment variables that happen to be set. No more assuming certain tools are at certain paths. No more implicit dependencies on "whatever happens to be on the system." Everything that affects the output must be declared and accounted for in the hash. This is harder than it sounds, but it's the only way to make build caching reliable at scale.

### Deduplication

Like [Gradle's build cache](https://docs.gradle.org/current/userguide/build_cache.html), identical artifacts produced from different projects or configurations are stored only once and can be reused. If two projects compile the same version of a dependency with identical settings, they share the same cached artifact.

Think about how much duplication exists in today's workflows. Your iOS app and your watchOS extension both compile the same networking library. Your main target and your test target both compile shared utilities. Multiply this across your team members and your CI runners, and you're doing the same work dozens or hundreds of times per day. With content addressing, all of this duplication collapses into a single stored artifact that everyone references by its hash.

### Portability

CAS enables what Bazel calls "[remote execution](https://bazel.build/remote/rbe)": the ability to use build artifacts produced anywhere, not just on your local machine. As long as the hash matches, the artifact is valid, regardless of where it was built.

This transforms what's possible with distributed builds. A developer in San Francisco can build a feature branch, and their teammate in Berlin can pull that branch and instantly have all the compiled artifacts. A CI job can compile dependencies once, and every other job in the workflow can reuse those artifacts. This isn't a clever hack or a fragile optimization. It's a fundamental property of the system.

## What This Enables

These properties unlock new possibilities:

**Cross-environment sharing**: An artifact built in CI can be used locally, or vice versa. A module compiled by a teammate in San Francisco works for another in Berlin, as long as the hash matches.

**Incremental correctness**: The system makes fine-grained decisions about rebuilding. If only one file changed, only transitively dependent artifacts need recompilation-everything else is safely reused from cache.

**Location independence**: All internal references use relative paths, similar to how [Bazel's execution root](https://bazel.build/remote/output-directories) provides a hermetic sandbox.

## The Remote Cache Challenge: Latency Matters

However, there's a significant consideration that Apple's build system must address: network latency.

Bazel learned this lesson early. When artifacts are stored remotely, every cache lookup introduces network latency. Bazel optimizes for this through several strategies:

- **Batch requests**: Rather than making individual requests for each artifact, Bazel queries for multiple artifacts simultaneously.
- **Speculative execution**: Bazel may start building locally while simultaneously checking for cached artifacts, using whichever completes first.
- **Layered caching**: Local disk cache, shared team cache, and global build farm-each layer serving as a fallback with different latency characteristics.
- **Compression and delta transfers**: Minimizing data transfer through intelligent compression and sending only changed portions of artifacts.

Apple's build system will need to evolve similarly. The architecture must account for scenarios where fetching from remote cache might be slower than rebuilding locally, especially for small, fast-to-compile modules. The design needs to be intelligent about when to fetch and when to rebuild.

## A Plugin Architecture for the Future

What's promising about Apple's CAS implementation is its plugin architecture. Rather than hardcoding a single caching backend, Xcode allows third-party tools to provide caching implementations through a C-based plugin API. This design decision shows Apple learned from the ecosystem-different teams have different needs, different infrastructure, and different trade-offs between cost, latency, and reliability.

### How the Plugin System Works

The CAS plugin architecture is defined in [Swift Build's open-source codebase](https://github.com/swiftlang/swift-build). At its core, the system defines a clean separation between the build system and storage backend through the [`CASProtocol`](https://github.com/swiftlang/swift-build/blob/main/Sources/SWBCAS/CASProtocol.swift):

```swift
public protocol CASProtocol {
    func store(object: CASObject) async throws -> DataID
    func load(id: DataID) async throws -> CASObject?
}
```

This simple interface hides significant complexity. Objects in the CAS aren't just blobs of data-they're nodes in a [directed acyclic graph (DAG)](https://en.wikipedia.org/wiki/Directed_acyclic_graph), where each object contains raw data and references to other objects. This graph structure enables powerful deduplication: identical content is stored once and referenced many times.

The plugin implementation itself is a C API defined in [`PluginAPI.h`](https://github.com/swiftlang/swift-build/blob/main/Sources/SWBCSupport/PluginAPI.h), providing functions for object storage, retrieval, and action caching. Xcode loads the plugin dynamically from `libToolchainCASPlugin.dylib`, allowing Apple to update the storage implementation independently of [Xcode](https://developer.apple.com/xcode/) releases.

### Content Addressing in Practice

When a file is stored in CAS, it's represented as a [`CASFSNode`](https://github.com/swiftlang/swift-build/blob/main/Sources/SWBCAS/CASFSNode.swift). Large files are automatically chunked into 4MB segments, with each chunk stored as a separate CAS object. This chunking strategy has several benefits:

- **Incremental uploads**: Only changed chunks need to be transferred
- **Deduplication across files**: Common file segments (like vendored dependencies) are stored once
- **Parallel operations**: Multiple chunks can be imported/exported concurrently

For example, if you have two projects that both include the same version of a framework, all the identical files within that framework share the same CAS objects. Change one file, and only that file's chunks need to be re-stored-everything else is automatically deduplicated.

### Cache Keys and Action Caching

Beyond just storing content, the CAS includes an action cache-a key-value layer that maps build inputs to outputs. The cache key for a compilation task includes:

- Command line arguments
- Environment variables
- Working directory
- Content hashes of all input files
- A version number for cache invalidation

This is implemented in [`GenericCachingTaskAction.swift`](https://github.com/swiftlang/swift-build/blob/main/Sources/SWBTaskExecution/TaskActions/GenericCachingTaskAction.swift), which wraps build tasks with caching logic. Before executing a task, the system checks if a cache entry exists for the computed key. If found, it replays the cached outputs, diagnostics, and process output-skipping execution entirely. This is similar to how [Bazel's action cache](https://bazel.build/remote/caching) works.

This plugin architecture opens the door for specialized caching backends optimized for specific scenarios. CI environments might use a different strategy than local development. Global teams might prioritize geo-distributed edge caches over a single central repository. The build system doesn't care about these details-it just speaks the plugin protocol.

## Tuist's Approach: Cache at the Edge

At Tuist, we believe the challenge isn't just supporting CAS-it's ensuring latency is the lowest possible, regardless of where developers are located or where builds are executed.

We're partnering with advanced storage solutions to bring cache to the edge. Rather than a single cache server that developers in Tokyo access with 200ms latency, we're building distributed architectures where cached artifacts are automatically replicated to [edge locations](https://en.wikipedia.org/wiki/Edge_computing) closest to where they're needed.

This benefits not only CI environments, where build time directly translates to infrastructure costs and developer productivity, but also local development. When you pull a branch and rebuild, those cached artifacts should be milliseconds away, not continents away.

The technical challenge is significant: coordinating cache replication across global edge nodes, handling cache invalidation, managing storage costs, and ensuring consistency. But we believe this is the right investment to make build caching truly viable at scale.

## Early but Transparent: The Current Reality

We need to be honest with you: this technology is not production-ready for distributed caching. Apple's CAS implementation is a foundation with significant potential, but it requires further investment to reach the maturity of systems like Bazel's remote cache.

We prefer transparency over salesmanship. Rather than telling you Apple's foundations are complete and trying to sell you an incomplete solution, let's talk about what actually works and what doesn't.

### The Real Challenges

The Swift community has been actively discussing these issues on the [Swift Forums](https://forums.swift.org/t/about-swift-shared-cache-across-machines/81850). The core problems are well-documented:

**Absolute path dependencies**: As one developer reported, "When I have two identical copies of code in different directories, the caches between them cannot be shared." The issue stems from [bridging headers](https://developer.apple.com/documentation/swift/importing-objective-c-into-swift) and other artifacts containing hardcoded absolute paths. During compilation, Xcode generates files like `ChainedBridgingHeader.h` that embed these absolute paths, breaking cache reusability across different machines.

**Distributed caching is a work in progress**: According to discussions in the Swift community, "Distributed caching will be the next focus for swift caching build, presumably for Swift 6.3." The current implementation supports only local caching effectively. While you can see impressive improvements (some developers report build times dropping from 170s to 61s with local caching enabled), sharing those caches across machines or with CI remains problematic.

**Edge cases with Swift macros**: The system can produce false negatives when using [Swift macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/), requiring manual cache clearing and potentially causing more frustration than benefit.

**Module cache path requirements**: For caching to work across environments, module cache directories must be in identical locations, which is often impractical in real-world setups.

### Why Ship Early Anyway?

You might reasonably ask: if it's not ready, why support it? Why write this blog post?

Because we believe in building in the open and shipping early. By making Tuist's CAS support available now, we invite the community to experiment, discover edge cases, and surface scenarios that Apple needs to address. Every bug report, every "this doesn't work when..." issue is valuable feedback that helps improve the foundation for everyone.

The alternative-waiting until the system is "perfect" or building proprietary solutions behind closed doors-serves no one. We've seen too many developer tools evolve in isolation, only to discover real-world problems after release.

By putting this out early and building it in the open, we hope to invite more people to try it, surface real-world scenarios, and create feedback loops with Apple to make the system better. The more teams that experiment with CAS, the faster we can collectively identify what needs improvement.

When you hit a limitation, you're not alone. The [Swift Forums thread on shared caching](https://forums.swift.org/t/about-swift-shared-cache-across-machines/81850) is full of developers working through the same challenges. These discussions are valuable-they document what doesn't work, share workarounds, and create a paper trail that helps Apple prioritize fixes.

## Building Infrastructure for Mobile

At Tuist, we built our caching solution using [generated projects](https://docs.tuist.dev/en/guides/features/projects)-a technology born to make modular projects manageable. But we've always believed caching should be solved at the build system level. CAS is the foundation we've been waiting for.

We're becoming infrastructure for mobile development, and we believe the challenges-caching, code signing, preview environments, selective testing-are too complex for any single company to solve alone. That's why we're partnering with players like [Namespace](https://namespace.so), whose ephemeral preview environments complement our caching infrastructure.

For years, teams accepted slow builds as inevitable. CAS changes this-for the first time, we have a foundation that makes remote caching reliable and built into the platform.

Want to try it? Run `tuist init` in your project and check our [documentation](https://docs.tuist.dev) to configure caching. Share your experiences in our [community Slack](https://slack.tuist.dev) or on [GitHub](https://github.com/tuist/tuist)-every experiment helps us build better tools for everyone.
