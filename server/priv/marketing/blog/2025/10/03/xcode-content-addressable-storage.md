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

What's promising about Apple's CAS implementation is its plugin architecture. Xcode loads a dynamic library (`.dylib`) at runtime that implements the caching backend. The plugin interface itself is open source and available in the [Swift Build repository](https://github.com/swiftlang/swift-build)-meaning anyone can build their own caching implementation.

You have two options: bring your own plugin by implementing the interface defined in Swift Build, or use the plugin that ships with Xcode. Apple's built-in plugin uses local storage by default, but the architecture supports passing a path to a gRPC server running at a local Unix socket-opening the door for remote caching implementations.

The challenge? While the plugin interface is open source, Apple's implementation is closed source. If you want to build a remote caching solution that works with Xcode's built-in plugin, you need to understand the gRPC protocol it expects. That's the problem we set out to solve.

### Reverse-Engineering the Protocol

When we set out to build remote caching support in Tuist, we faced a challenge: Apple's CAS protocol isn't publicly documented. We needed to understand how Xcode communicates with the caching backend to build a compatible implementation.

We took a systematic approach to reverse-engineer the protocol, documented in our [xcode-cas repository](https://github.com/tuist/xcode-cas):

**Traffic Capture**: We built a custom HTTP/2 server using Python's [h2 library](https://python-hyper.org/projects/h2/) and intercepted Unix socket traffic with [socat](http://www.dest-unreach.org/socat/). This let us observe the raw communication between Xcode and the CAS plugin.

**Protocol Analysis**: By inspecting [HTTP/2](https://http2.github.io/) headers, [gRPC](https://grpc.io/) paths, and [Protobuf](https://protobuf.dev/) messages, we identified the request/response patterns. The protocol uses gRPC over HTTP/2, communicates exclusively through Unix domain sockets, and transfers artifacts inline in responses.

**Experimental Verification**: We implemented a test server with artifact storage to validate our understanding. Through experimentation, we confirmed that `GetValue` returns full artifacts inline and that cache hits succeed when artifacts are available-no separate Load/Get/Fetch operations exist.

**Using Codex to Decode Protobuf**: The most challenging part was understanding the Protobuf message structure. We used [Codex](https://github.com/google/codex), a tool for reverse-engineering Protobuf definitions from binary data. By capturing message bytes and feeding them to Codex, we reconstructed the `.proto` definitions that describe the gRPC service contract. This gave us the message schemas needed to implement a compatible server.

### Making It Available to Everyone

At Tuist, we believe in the value of openness to advance the ecosystem. While we could have kept this reverse-engineering work proprietary, we chose to make it publicly available at [github.com/tuist/xcode-cas](https://github.com/tuist/xcode-cas).

Why? Because the iOS and macOS development community is stronger when we share knowledge. If you're building developer tools, implementing your own caching solution, or just curious about how Xcode's build system works, you shouldn't have to repeat the same reverse-engineering work we did. The repository includes:

- Complete documentation of our reverse-engineering methodology
- The reconstructed Protobuf definitions for the gRPC service
- A reference implementation of a CAS server (see the [server directory](https://github.com/tuist/tuist/tree/main/server) in our open-source repository)

This work demonstrates how open collaboration and tooling like Codex can help the community build on Apple's platforms even when official documentation is limited. We hope that by sharing our findings, we can accelerate innovation in build tooling and make it easier for others to build solutions that integrate with Xcode's caching infrastructure.

## Tuist's Approach: Bringing Cache to the Edge

The real challenge isn't the software implementation-it's physics. If the compiler can plan ahead of time and fetch artifacts before they're needed, and if those artifacts are milliseconds away instead of continents away, the improvements are transformative. The bottleneck isn't computation; it's latency.

This is why we're investing heavily in edge infrastructure. Rather than a single cache server that developers in Tokyo access with 200ms latency, we're building distributed architectures where cached artifacts are automatically replicated to [edge locations](https://en.wikipedia.org/wiki/Edge_computing) closest to where they're needed. We're even exploring the possibility of pushing the edge concept into our customers' offices-deploying cache nodes on local networks where latency is measured in microseconds, not milliseconds.

**We're making this available to everyone for free, from any environment.** Whether you're building locally, in CI, or in a hybrid setup, you get the same edge-optimized infrastructure. This wouldn't be possible with solutions that aim at locking you into their infrastructure. By building on open protocols and supporting self-hosted deployments, we give teams the flexibility to optimize for their specific needs.

### The Power of Module-Level Caching

While CAS operates at the file level, Tuist's [module-based binary caching](https://docs.tuist.dev/en/guides/develop/build/cache) achieves even greater efficiency-up to 80% build time reduction-thanks to module-level granularity. Instead of caching individual compilation units, we cache entire frameworks and libraries. When you change a single file in one module, only that module rebuilds; everything else is reused from cache.

The combination of both approaches can achieve even greater improvements. CAS provides the infrastructure-level caching that works seamlessly with Xcode, while module-based caching delivers the coarse-grained reuse that dramatically cuts build times in modular architectures. Together, they complement each other: CAS handles the low-level build artifacts, while our module caching optimizes the high-level project structure.

We're also partnering with players like [Namespace](https://namespace.so), whose ephemeral preview environments complement our caching infrastructure. Mobile development challenges-caching, code signing, preview environments, selective testing-are too complex for any single company to solve alone. We're building the ecosystem that makes fast, efficient mobile development the default.

## Shipping Early, Building in the Open

Let's be honest: this technology is not production-ready for distributed caching. Apple's CAS implementation is a foundation with significant potential, but it requires further investment to reach the maturity of systems like Bazel's remote cache.

The Swift community has been actively discussing these issues on the [Swift Forums](https://forums.swift.org/t/about-swift-shared-cache-across-machines/81850). The core problems are well-documented: absolute path dependencies in [bridging headers](https://developer.apple.com/documentation/swift/importing-objective-c-into-swift), distributed caching being a work in progress ("will be the next focus for swift caching build, presumably for Swift 6.3"), edge cases with [Swift macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/), and module cache path requirements.

While you can see impressive improvements with local caching (some developers report build times dropping from 170s to 61s), sharing those caches across machines or with CI remains problematic.

**So why ship it now?** Because we believe in building in the open and shipping early. By making Tuist's CAS support available now, we invite the community to experiment, discover edge cases, and surface scenarios that Apple needs to address. Every bug report, every "this doesn't work when..." issue is valuable feedback that helps improve the foundation for everyone.

The alternative-waiting until the system is "perfect" or building proprietary solutions behind closed doors-serves no one. The more teams that experiment with CAS, the faster we can collectively identify what needs improvement. When you hit a limitation, you're not alone. The [Swift Forums thread on shared caching](https://forums.swift.org/t/about-swift-shared-cache-across-machines/81850) is full of developers working through the same challenges.

Want to try it? Run `tuist init` in your project and check our [documentation](https://docs.tuist.dev) to configure caching. Share your experiences in our [community Slack](https://slack.tuist.dev) or on [GitHub](https://github.com/tuist/tuist)-every experiment helps us build better tools for everyone.
