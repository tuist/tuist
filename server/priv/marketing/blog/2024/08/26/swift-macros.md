---
title: "Swift Macros at scale"
category: "product"
tags: ["Swift"]
excerpt: "Swift Macros, while powerful, can hinder build times. This blog post explains why and what we can do to mitigate the issue."
author: pepicrft
---

[Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) were introduced in September 2023 alongside Xcode 15 and have become a powerful tool for developers to leverage the compiler to generate code. The community quickly adopted them and started building and [sharing them](https://github.com/krzysztofzablocki/Swift-Macros) as Swift Packages that teams could integrate into their projects. At Tuist, we started using [Mockable](https://github.com/Kolos65/Mockable) as a tool to generate mocks from protocols, which we had previously been doing manually.

However, Swift Macros quickly revealed a serious challenge: they can significantly increase build times, causing slow feedback cycles both locally and in CI environments. This blog post aims to explain where the build time slowness comes from, what potential solutions we might see Apple adopting, and what we can do in the meantime to mitigate the issue.

## What is a Swift Macro?

A Swift Macro is an executable that receives and outputs an abstract syntax tree (AST) via standard input and output. This process is called Macro Expansion. When a Swift Macro is added to an Xcode project, Xcode builds the Swift Macro into a static binary and then invokes it when the compiler encounters a piece of code that references a macro. Swift Macros typically depend on [SwiftSyntax](https://github.com/swiftlang/swift-syntax), a package for working with AST representations of Swift code. The compiler needs to compile SwiftSyntax along with its more than ten transitive dependencies and then link them statically against the binary to ensure the executable runs instantly.

To back this blog post with data, we created a Swift Macro and used the [hyperfine](https://github.com/sharkdp/hyperfine) tool to measure the time it takes to create a clean release build of a recently-created Swift Macro:


```bash
mkdir BenchmarkMacro && cd BenchmarkMacro
swift package init --type macro
hyperfine --warmup 3 --runs 5 'rm -rf .build && swift build -c release'
```

The above test on a MacBook Air M2 from 2022 with 16GB of RAM yielded the following results:

```bash
Time (mean ± σ):     196.288 s ± 23.299 s    [User: 286.626 s, System: 12.698 s]
Range (min … max):   178.014 s … 235.620 s    5 runs
```

~3 minutes seems reasonable, but the times get worse when you add more Swift Macros to your project.

## A non-API-stable SwiftSyntax

If you add multiple macros that depend on multiple SwiftSyntax versions, Swift Package Manager will fail to resolve the dependencies due to conflicting versions. As [PointFree](https://www.pointfree.co/blog/posts/116-being-a-good-citizen-in-the-land-of-swiftsyntax#be-as-flexible-as-possible-in-your-dependence-on-swiftsyntax) recommends, authors should be as flexible as possible in their dependence on SwiftSyntax.

Softening the version requirements of SwiftSyntax in the Swift Macros might help, but it requires SwiftSyntax to be API-stable, which will hopefully happen according to [this comment](https://forums.swift.org/t/macro-adoption-concerns-around-swiftsyntax/66588/15) after the Swift 5.9-aligned release. Even with that in place, you'd still have to rely on Apple doing a good job of making the API stable—which I think is a fair assumption—and on developers adjusting their Swift Macros to soften the version requirements.

## What if we pre-compile SwiftSyntax?

Even with the above, you wouldn't get rid of the X minutes it takes to compile SwiftSyntax. One might think that Apple could provide a pre-compiled version of SwiftSyntax, but as of today, there are two large obstacles:

- SwiftSyntax is not ABI stable, so they would have to solve that first.
- Swift is not ABI stable on non-Darwin platforms (e.g., Windows, Linux).

What this means is that even if Apple made SwiftSyntax ABI stable, providing binaries of the package wouldn't work in non-Darwin environments. Will Apple invest in that effort? That's a big question that only Apple can answer, but past work on non-Darwin platforms was traditionally done by the community.

## WebAssembly to the rescue

There's a technology that ticks all the boxes for what a Swift Macro needs:

- A way to run safely in a runtime.
- A way to ship a compiled version of it that runs in any version of the runtime.

That technology is [WebAssembly](https://webassembly.org), and [Kabir Oberai](https://github.com/kabiroberai) had the brilliant idea to support that as the technology to run Swift Macros. And thanks to the [WasmKit](https://github.com/swiftwasm/WasmKit) runtime, the problem is not only solved for the Darwin platform but also for Windows and Linux. There's an [ongoing conversation](https://forums.swift.org/t/poc-improving-macro-build-times-with-webassembly/70967/32) in the Swift Community forum, so hopefully, we'll see this technology being adopted soon, which will require Swift Macro authors to compile their Swift Macros to .wasm binaries and ship them alongside the source code.

## What Tuist is doing

Tuist is uniquely positioned to solve this problem thanks to our ability to optimize a source's dependency graph with binaries generated from previous builds. As soon as Swift Macros came out and we started seeing the build time issues, we extended [caching](https://docs.tuist.io/guides/develop/build/cache) to support Swift Macros too. Adopting this is very straightforward if you are using [Tuist Projects](https://docs.tuist.io/guides/develop/projects). All you need to do is run the following command to fingerprint and store your Swift Macros, frameworks, and bundles:

```
tuist cache
```

And the next time you or anyone on your team generates an Xcode project, they'll be using a previously-generated binary. It feels truly magical to see how fast the build times are after adopting this feature.

If you want to see this in action, you can play with one of the Tuist project's fixtures:

1. Clone the repository: `git clone https://github.com/tuist/tuist`.
2. Install the repository dependencies: `mise install`.
3. Choose the example directory: `cd examples/xcode/generated_framework_with_native_swift_macro`
4. Install the project dependencies: `tuist install`
5. Cache the dependencies: `tuist cache`
6. Generate the Xcode project: `tuist generate`

The following image shows the generated Xcode project where all the dependencies, including the Swift Macros, have been cached:

![Tuist Xcode project with cached Swift Macros](/marketing/images/blog/2024/08/26/swift-macros/cached-swift-macro.png)

## Closing

There are three possible solutions we might see Apple adopting:

1. Making SwiftSyntax ABI and API stable, and Swift ABI stable on non-Darwin platforms.
2. Using WebAssembly to run Swift Macros.
3. Supporting fingerprint-based binary caching in Xcode and Swift Package Manager.

(1) would be highly beneficial for the community, but it will test Apple's willingness to invest in other platforms or leverage the community to make that happen. (2) would show Apple's willingness to embrace web technologies, avoid reinventing the wheel, and help advance the web ecosystem, but Apple hasn't had a good record of doing that in the past. (3) would be the most pragmatic solution, but it would require Apple to make a significant investment in the build system, which has been historically slow to evolve, and there are many projects out there that accidentally build through implicit configuration that might break if such a feature is introduced.

Regardless of what happens, Tuist will continue to address these challenges in the simplest and most fun way. If you are interested in learning more about Tuist, you can check out [our documentation](https://docs.tuist.io/).
