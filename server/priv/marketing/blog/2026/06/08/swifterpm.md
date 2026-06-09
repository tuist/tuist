---
title: "SwifterPM: faster Swift package resolution for generated and Bazel projects"
category: "product"
tags: ["product", "swift", "spm", "cli", "bazel", "performance"]
excerpt: "Our users kept telling us that resolving Swift packages was slow and that the resulting directories ate gigabytes of disk, and that pain has only grown as people run several agents across worktrees at once. So we built SwifterPM, a faster resolver and restorer for Swift packages, available today as an opt-in feature for Tuist generated projects and as a Bazel rule. Here is how it works, what it does not solve, and the benchmarks."
author: pepicrft
og_image_path: /marketing/images/blog/2026/06/08/swifterpm/og.jpg
---

For a while now our users have been telling us the same thing, and lately they have been telling us louder. Installing the dependencies of their Swift packages is slow, and the directory where those dependencies get resolved takes an uncomfortable amount of disk space. The itch has been getting worse, not better, and the reason is easy to point at: people are doing far more concurrent work with coding agents, each agent on its own [git worktree](https://git-scm.com/docs/git-worktree), each resolving the same dependencies from scratch. Several copies of the same packages, resolved several times, sitting on disk several times over.

At Tuist we could not let that sit. If there is one thing we are about, it is productivity, and we should not be in the business of letting slow things stay slow. So we did something about it. It is called [**SwifterPM**](https://github.com/tuist/swifterpm), and it is a faster resolver and restorer for Swift packages.

## Where the time and the disk go

For those who do not know how this part of the world works, a quick tour. Tuist, like Xcode and like [Bazel](https://bazel.build), uses the [Swift Package Manager](https://github.com/swiftlang/swift-package-manager) to resolve the dependency graph locally. Each tool keeps that resolution in its own place. Tuist uses a `.build` directory relative to the root of the repository, Xcode keeps it in an internal location of its own, and Bazel does something similar under its own tree.

The interesting part is what happens after the graph is resolved. It does not stay as a generic graph. It gets reconciled into the primitives of whatever build system you are using. With Bazel it becomes the graph that [the Apple rules](https://github.com/bazelbuild/rules_apple) construct. With Tuist it becomes the graph of the generated project. And so on.

This is why it is a hard problem to fix well. Touching it properly means changing something fundamental about how resolution and reconciliation happen, and a change like that has a very large blast radius. So we took our time and we looked around.

## Borrowing from a neighbor

The ecosystem we looked at for reference is JavaScript. Not because it is tidy, it is famously not, but because it has many package managers that have spent years pushing each other forward through plain competition. Every package manager, at the end of the day, does roughly the same thing. There is a manifest file that declares dependencies on other packages, there is a registry, a graph gets constructed, and once it is constructed everything is pulled locally into a directory structure that the consumers understand. In Node that means reproducing everything under `node_modules` following the conventions of the runtime.

[pnpm](https://pnpm.io) was one of the first to take this seriously, with a global content-addressable store and cheap project-local links instead of full copies. More recently [aube](https://github.com/endevco/aube) from the creators of [mise](https://mise.jdx.dev) pushed install performance significantly further, and that in turn nudged pnpm and [Bun](https://bun.sh) to do similar rewriting. That is the beauty of it. Someone moves the line of what is possible, and everyone else has to follow.

The question we asked ourselves was simple. Could we reproduce something like that for the Swift Package Manager?

## What we can speed up, and what we cannot

There are limits to what we can do, though. Unlike NPM, which has a central registry and an API you can hit to get fast answers like "which versions of this package exist", the Swift package ecosystem is decentralized by design. That is a real strength, but it has a cost: traversing the graph is not something we can fundamentally speed up. A registry-first approach would change that, but it is not the world we live in, so we worked within the constraints we have.

That said, there was an easy win sitting in plain sight, one the community has raised several times. If you have a GitHub session, you can hit the GitHub API and use it as the source of truth for the versions available in a repository, instead of cloning the entire repository just to read its tags. Cloning the whole history only to enumerate versions is one of the most expensive parts of resolution, and it is noticeable. So SwifterPM resolves versions through the GitHub API, with a shallow Git fetch kept as a fallback. For packages declared through the Swift registry with `.package(id:)`, it resolves them through registry configuration and downloads checksum-verified archives.

## A global store, and links instead of copies

The bigger change is how things are laid out on disk. Everything is arranged so that reproducing the dependencies for any project links back to the same content-addressable store, which becomes the single source of truth for all package data. Archives and extracted source trees are stored once under `$XDG_CACHE_HOME/swifterpm` (or `~/.cache/swifterpm`), keyed by package identity, version, and revision.

The directory where the dependencies get reproduced, `.build/checkouts`, is no longer a full copy of the graph. The entries stay as real directories so the paths Xcode and Tuist expect keep resolving inside the worktree, but their contents are symlinks back into that global store. So instead of materializing the entire source tree of every dependency into each worktree, we lay down a thin set of links that point at bytes that already exist once on disk.

This buys two things that matter a lot:

1. **Reproducing a package graph is fast.** We are talking milliseconds, against the seconds it takes to populate a fresh worktree or a new Bazel workspace with the same set of dependencies the usual way.
2. **It barely touches disk.** We do not make copies. We have all seen those checkout directories that climb into several gigabytes per worktree, which feels terribly unnecessary when it is the same bytes over and over.

Writes are concurrency-safe by construction. Restoration runs in parallel, and cache writes use file locks, temporary files, and atomic moves, so several installs across several worktrees can share the same store without stepping on each other. That is precisely the agents-on-worktrees situation our users kept reporting.

## Paying the manifest cost once

There is one more piece, on the reconciliation side. To turn a resolved graph into something a build system can use, you have to read each package's `Package.swift` manifest. Apple is [leaning on statically analyzing the manifest](https://forums.swift.org/t/improving-manifest-loading-performance-for-declarative-package-manifests/85994) and falling back to compiling it when analysis is not enough. The trouble is that if you look at the real ecosystem, an enormous number of packages are not meaningfully static. Take the ones everyone depends on, like [Firebase](https://github.com/firebase/firebase-ios-sdk), and you find genuine logic in the manifest. Static analysis cannot help you there.

So instead of trying to avoid compiling the manifest, SwifterPM pays that cost deliberately, at resolution time, and turns each manifest into a JSON representation that it persists locally under `.build/swifterpm/package-info`. Later, when the nodes of the graph are reconciled, the format is already there and is very fast to decode. You pay once, up front, and everything downstream gets cheaper. This shows up in the benchmarks below: even a cold run, where we are doing all of that up-front work, comes out ahead, and every run after that is dramatically faster.

## The benchmarks

Numbers, since they are the point. These come from the [SwifterPM benchmark script](https://github.com/tuist/swifterpm), three runs each, on macOS 26.4.1 with Apple Swift 6.3.2. Cold resolution wipes both the package-local scratch directories and the global cache before each run. Worktree-warm resolution wipes the package-local scratch but keeps the primed global cache, which is exactly what happens when you switch to another clean worktree, the scenario that hurts most with agents.

| Codebase | Scenario | SwiftPM | SwifterPM | Speedup |
|:---|:---|---:|---:|---:|
| Pocket Casts iOS (`Modules/Package.swift`) | Cold | 245.89 s | 140.16 s | 1.75x |
| Pocket Casts iOS (`Modules/Package.swift`) | Worktree-warm | 126.28 s | 0.70 s | **180.40x** |
| Firefox iOS (root `Package.swift`) | Cold | 51.07 s | 14.71 s | 3.47x |
| Firefox iOS (root `Package.swift`) | Worktree-warm | 15.54 s | 0.48 s | **32.27x** |

The cold runs are already a clear win, between 1.75x and 3.47x faster, even though that is the moment SwifterPM is doing its most expensive up-front work, compiling and persisting every manifest. But the cold run is not the number to fixate on. The one that matters is worktree-warm, because that is the cost a developer running several agents actually pays, again and again, all day. There a resolution of Pocket Casts' modules drops from over two minutes to under a second, and Firefox from fifteen seconds to under half a second. Disk follows the same shape: the global store is populated once instead of being copied into every worktree.

## How to turn it on

We have been rolling this out as an opt-in feature, because we would rather validate it carefully than surprise anyone. There may be graph scenarios we do not handle yet, and the honest way to find them is with real projects.

If you use Tuist generated projects, you can opt in with a flag and let `tuist install` use SwifterPM before generation. If you use Bazel, SwifterPM ships a Bzlmod extension with the same resolver shape as `rules_swift_package_manager`:

```starlark
bazel_dep(name = "swifterpm", version = "0.7.0")

swift_deps = use_extension("@swifterpm//:extensions.bzl", "swift_deps")
swift_deps.from_package(
    resolved = "//:Package.resolved",
    swift = "//:Package.swift",
)
use_repo(swift_deps, "swift_package")
```

We are taking our first real steps into Bazel, and we wanted this to be useful to that community from the start. Any company already on Bazel, or weighing the move, can pick up the rule and get the same speedups. This is part of a larger appetite we are building to plug our caching and infrastructure into more technologies, from cacheable generated projects through to Bazel, and there is a lot more exploration ahead of us in that space.

## The one place we cannot reach, and the one we would like to

I wish I could say this helps everyone, and it does not. The integration between Xcode and the Swift Package Manager happens inside Xcode itself, through code we do not control, and it does not expose a supported hook where we could swap in a faster resolver or restorer. So we cannot bring any of this to plain Xcode projects, even though we would love to. The best we can hope for there is that this sparks some discussion.

Which brings me to the part I want to put in writing. We are open to upstreaming these changes once we have validated that they work reliably and fast with a broader community. We do not want to fork the ecosystem, we want to raise its floor. aube is the example I keep in my head: it shipped, it forced a healthy round of competition, and the whole ecosystem got faster for it. If SwifterPM can do a small version of that for Swift, that is a win we are happy to share rather than hoard.

We had to move on this quickly, because our users could not keep waiting for some future Xcode release to maybe address it. As long as we stay aligned with how resolution works, with the state files SwiftPM writes, and with what the clients (Bazel and Tuist) expect, we are in a good spot. Apple will keep adding things at the language and manifest level, as they did with [traits](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0450-swiftpm-package-traits.md), and that does not really change the resolution logic underneath.

Give it a try. If you hit a graph we do not handle yet, please [open an issue](https://github.com/tuist/swifterpm/issues) and include your Swift version and the errors you saw, so we can take a look. This has been a genuinely fun piece to work on, and as always, we will keep iterating in the open and sharing what we find.
