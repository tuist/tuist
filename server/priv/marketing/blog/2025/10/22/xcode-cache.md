---
title: "Speed up your builds with the remote Tuist cache for Xcode"
category: "product"
tags: ["xcode", "product"]
excerpt: "Learn how to use the new Xcode compilation cache with Tuist to cut build times in local and CI environments"
highlighted: true
og_image_path: /marketing/images/blog/2025/10/22/xcode-cache/og.jpg
author: fortmarek
---

[Swift](https://www.swift.org) is an amazing and modern programming language. It's also a language that's statically typed, allowing the compiler to highlight issues before an application is even run. And the earlier in the development process an issue is detected, the easier it typically is to fix. But statically typed languages come at a cost – and that is build time. Ever since the migration from Objective-C, this has been a sore point of the language. And while the compiler and the hardware have both improved over the years, they haven't been able to keep up with the pace of growth of Swift codebases. A problem more acute with the broader usage of AI agents, like [Codex](https://openai.com/codex/) or [Claude Code](https://www.claude.com/product/claude-code), leading to even more Swift code being written.

This sometimes leads to drastic choices being made by iOS engineering teams, such as moving to other build systems like [Bazel](https://bazel.build/) that has a great support for caching or completely abstracting away the platform with technologies like [React Native](https://reactnative.dev/). We've developed our own solution to help teams with their build times by leveraging generation to cache modules as `.xcframework`s. And we believe that, at the time of writing, the Tuist module cache is still the best solution for iOS teams looking to speed up their builds.

However, now you can **improve your incremental and clean build times in just a couple of minutes**, regardless of your Xcode setup, with the **new Xcode compilation cache** [introduced in Xcode 26](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes#New-Features).

<iframe title="Get started with the Tuist cache for Xcode" width="560" height="315" src="https://videos.tuist.dev/videos/embed/ewgDzSbw5DojtpUHqk6hxP" style="border: 0px;" allow="fullscreen" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>

### How is this different than derived data

You might be wondering how the new Xcode compilation cache is different than derived data. 

Build artifacts in the derived data directory are stored in a location-based structure. When Xcode builds your project, it places compiled objects, indexes, and intermediate build products in paths tied to your project's location and configuration. On the surface, this seems reasonable-put the outputs next to the inputs. But this seemingly simple design decision has created a cascade of problems as our development workflows have evolved.

Consider a typical scenario: you're working on a feature branch, building and testing locally. Your colleague in another time zone is working on a different feature. Your CI system is running builds for every pull request. All of you are compiling the same dependencies-maybe a large framework like [Alamofire](https://github.com/Alamofire/Alamofire) or a set of internal modules that rarely change. Yet each of you is doing this work independently, from scratch, because derived data can't safely share these artifacts.

Why not? The problems run deep:

**Non-deterministic builds**: The same source code compiled on different machines or in different locations can produce different artifacts. This isn't just theoretical-debug symbols contain absolute paths, frameworks reference their build location, and various metadata gets embedded during compilation. If you build on your MacBook Pro and I build on my Mac Studio, we get different bytes, even though the source code is identical. This makes caching across environments fragile at best and incorrect at worst.

**Path dependencies**: Artifacts often contain hardcoded absolute paths. Your framework compiled at `/Users/you/Projects/App` doesn't work when I try to use it at `/Users/me/Code/App`. These path references break when moved between machines or when the project is located in different directories. It's not just about where the framework is-it's about where it was built, where its dependencies were, where the SDK is installed. It's turtles all the way down.

**Coarse invalidation**: When something goes wrong-and something always eventually goes wrong-developers resort to deleting the entire derived data directory. Hours of compilation work, discarded in seconds, because there's no reliable way to determine which artifacts are still valid and which are corrupted or stale. We throw away the good with the bad because we can't tell them apart.

**Limited sharing**: These characteristics combine to make it nearly impossible to reliably share build artifacts across team members or between local development and CI environments. Some teams have tried-setting up shared network drives, syncing derived data directories, elaborate rsync scripts. These approaches are fragile and often cause more problems than they solve. The fundamental architecture just wasn't designed for this use case.

### Moving beyond derived data: Xcode compilation cache

All of these problems are solved by the new Xcode compilation cache which, in many ways, is similar to other performant build systems like the already-mentioned Bazel or [Gradle](https://gradle.com). These build systems and now the Xcode compilation cache use a combination of a [key value store](https://en.wikipedia.org/wiki/Key%E2%80%93value_database) (also known as action cache) and a [content-addressable storage](https://en.wikipedia.org/wiki/Content-addressable_storage) (commonly referred to as CAS).

When the build system compiles your app, instead of storing artifacts based on file paths, it computes a [hermetic](https://bazel.build/basics/hermeticity) fingerprint for each build action and stores the compilation artifacts in the content-addressable storage where each artifact is identified by a unique digest of the contents. This makes builds deterministic, portable, and more efficient.

This shift has taken Apple multiple years to execute – the first RFC to add support for caching using the content-addressable storage in the LLVM project (which the Swift build system builds upon) [was proposed in 2022](https://discourse.llvm.org/t/rfc-add-an-llvm-cas-library-and-experiment-with-fine-grained-caching-for-builds/59864). But since Xcode 26, you can enable the Xcode compilation cache by setting the `COMPILATION_CACHE_ENABLE_CACHING` to `YES` in your build settings or in the `xcodebuild` invocation and reap the benefits – at least locally.

### Sharing cache across environments

Improving local incremental builds is already a huge improvement to our daily Swift development. But since the new compilation cache is _portable_, shouldn't we be able to reuse build artifacts from the CI on our local machines? Or between individual CI runs? Can we finally stop rebuilding the same code over and over again?

You might wonder if you can cache the whole compilation cache across CI runs and then download the whole directory to your local machines – and while you _can_, this directory will be continuously growing and there's no direct way to tell which artifacts are still actively being used and which not.

Instead, the build system uses a [gRPC contract](https://github.com/swiftlang/llvm-project/tree/d7ed79de3369c94f62f25fb48fbfcfbf152ae350/llvm/lib/RemoteCachingService/RemoteCacheProto) to communicate with external services. Whenever the build system needs to look up a value in the key-value store or the content-addressable storage, if it's not found in the local compilation cache, it will connect to the remote service, if available, and attempt to retrieve the missing data from there. Similarly, when storing new artifacts, the build system will store them both in locally and remotely.

So, how do you get started with remote caching using Tuist?

1. Install the [Tuist CLI](https://tuist.io/docs/getting-started/installation/) if you haven't already.
2. Integrate your project with Tuist by running `tuist init`.
3. Run `tuist setup cache`.

The `tuist setup cache` then lists out the build settings that you need to configure in your project:
- `COMPILATION_CACHE_ENABLE_CACHING=YES` to enable local or remote caching
-`COMPILATION_CACHE_ENABLE_PLUGIN=YES` to enable a plugin that communicates with the remote cache
- `COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/your-organization-handle_your-project-handle.sock` to instruct plugin where it can find the gRPC socket proxy

The gRPC socket proxy acts as a bridge between the build system and needs to be running as a daemon in your system. Note that `tuist setup cache` will automatically start the gRPC socket proxy for you.

### The Xcode compilation cache in the real world

Let's take a look at how the Xcode compilation cache helps to reduce build times in real world projects. We've benchmarked the performance of the Xcode compilation cache in the following projects:
- [Pocket Casts](https://github.com/Automattic/pocket-casts-ios/)
- [Wikipedia](https://github.com/wikipedia/wikipedia-ios)
- [Tuist CLI](https://github.com/tuist/tuist)

**Note:** The following benchmarks were conducted on [Namespace](https://namespace.so/) M4 Pro runners on 20th and 21st October 2025 using Xcode 26.0.1. All benchmark results are available in our [cache-benchmark](https://github.com/tuist/cache-benchmark) repository.

Here's what we've found:

<img alt="Benchmark compilation cache results" src="/marketing/images/blog/2025/10/22/xcode-cache/benchmark.png">

For Wikipedia, the build time was reduced by 24% when using the local cache (simulating clean builds with local compilation cache already populated) and by 18% when using the remote cache (simulating clean builds with remote, not local, compilation cache already populated). For Pocket Casts, the build times were reduced by 36% for the local cache and by 20% for the remote cache.

We've observed the biggest improvement in build times for Tuist CLI, where the build time was reduced by 77% when using the local cache and by 53% when using the remote cache. Why is the cache so much faster against the Tuist CLI project? We'll need to talk about the current state of the cache.

### Not everything is cacheable (yet)

The compilation cache is still an early, opt-in feature. In the latest Xcode release (26.0.1), there are still a lot of tasks that are _not_ cacheable, like computing the build graph or compiling parts of Swift packages. This is why the Tuist CLI performs better than other projects because we integrate our packages as [Xcode projects](https://docs.tuist.dev/en/guides/features/projects/dependencies#xcodeprojcodified-graphs). In fact, we've also measured the performance of the cache against Mastodon – in one case using the default SwiftPM integration, in the other generating those dependencies as Xcode projects. The difference was significant:

<img alt="Benchmark compilation cache results" src="/marketing/images/blog/2025/10/22/xcode-cache/mastodon-benchmark.png">

Whereas building Mastodon with the local cache and the remote cache with the default SwiftPM integration improved the build by 19% and 30%, respectively, the improvements were 55% and 69% for the Mastodon project generated with Tuist.

We certainly expect the types of tasks that Xcode can cache to expand, including a better support for Swift packages, but it's important to highlight the current limitations of the cache.

### Latency is key

Apart from a difference between generated and non-generated projects, you might have also noticed that the remote cache is typically slower than the local cache – and that will always be the case as file operations are faster than going over the network–because physics. The build system is making thousands or tens of thousands of requests per build and each request has a cost associated with it.

This is why we're investing heavily in our edge infrastructure to minimize that cost and serve the cache requests at the minimum latency. We're also exploring the possibility of pushing the edge concept into our customers' offices-deploying cache nodes on local networks to improve the latency even further. And we expect that Apple will invest more into optimizing the distributed cache, such as by computing which artifacts will be needed during the build earlier and prefetching them.

### The power of module-based caching 

While Apple continues to invest into the build caching, we've already iterated on [module-based binary caching](https://docs.tuist.dev/en/guides/develop/build/cache) over the years and based on our [benchmarks](https://github.com/tuist/cache-benchmark), our approach currently **outperforms** the remote cache – achieving better or similar build times (including generation and fetching of binaries) as the _local_ compilation cache. Instead of caching individual compilation units, we cache entire frameworks and libraries, pre-fetch them before generating the project and then letting the build system compile only what has changed. This also has the side effect that Xcode projects are leaner and Xcode is faster.

And the combination of both approaches can achieve even greater improvements. Xcode compilation cache provides a more granular level caching that works seamlessly with Xcode, while module-based caching delivers the coarse-grained reuse that dramatically cuts build times in modular architectures.

### Looking ahead

If you've been intrigued, head over to our [documentation](https://docs.tuist.dev/en/guides/features/cache) to get started with the Tuist cache. We're currently offering the remote Xcode cache **for free** while we iterate on the integration of this feature with pricing being announced later in the year. In the meantime, we will continue to improve the latency and introduce detailed analytics to help you understand the impact of the cache on your build times. You can already leverage our [build insights](https://docs.tuist.dev/en/guides/features/insights#builds) to track the build performance in both local and CI environments.

And if you have any questions or feedback, reach out to us [in our  community forum](https://community.tuist.dev/), [Slack](https://slack.tuist.dev/) or send me a mail directly at [marek@tuist.dev](mailto:marek@tuist.dev).
