---
title: "SwifterPM: faster Swift package resolution for generated, Bazel, and Buck2 projects"
category: "product"
tags: ["product", "swift", "spm", "cli", "bazel", "buck2", "performance"]
excerpt: "Our users kept telling us that resolving Swift packages was slow, and that the directories where they get resolved ate gigabytes of disk. That pain has only grown as people run several agents across worktrees at once. So we built SwifterPM. It leaves resolution to the Swift Package Manager and speeds up everything around it: fetching the pinned sources, putting them on disk, and reading their manifests. Starting today it's the default for Tuist generated projects, with an environment variable to opt out, and it ships as a rule for Bazel and Buck2."
author: pepicrft
og_image_path: /marketing/images/blog/2026/07/16/swifterpm/og.jpg
---

For a while now our users have been telling us the same thing, and lately they've been telling us louder. Installing the dependencies of their Swift packages is slow, and the directory where those dependencies get resolved takes an uncomfortable amount of disk space. The itch has been getting worse, not better, and the reason isn't hard to point at: people are doing far more concurrent work with coding agents, each agent on its own [git worktree](https://git-scm.com/docs/git-worktree), each resolving the same dependencies from scratch. Several copies of the same packages, resolved several times, sitting on disk several times over.

We couldn't let that sit, because if there's one thing we care about it's productivity, and we shouldn't be in the business of letting slow things stay slow. So we built [**SwifterPM**](https://github.com/tuist/tuist/tree/main/swifterpm), which leaves the resolution itself to the Swift Package Manager and makes everything around it much faster: getting the pinned sources onto disk, and reading their manifests.

## Where the time and the disk go

For those who don't know how this part of the world works, a quick tour. Tuist, like Xcode and like [Bazel](https://bazel.build), uses the [Swift Package Manager](https://github.com/swiftlang/swift-package-manager) to resolve the dependency graph locally, and each tool keeps that resolution in its own place: Tuist in a `.build` directory relative to the root of the repository, Xcode somewhere internal of its own, and Bazel under its own tree.

The interesting part is what happens after the graph is resolved, because it doesn't stay a generic graph. It gets reconciled into the primitives of whatever build system you're using, so with Bazel it becomes the graph that [the Apple rules](https://github.com/bazelbuild/rules_apple) construct, with Tuist the graph of the generated project, and so on.

This is why it's a hard problem to fix well: touching it properly means changing something fundamental about how resolution and reconciliation happen, and a change like that has a very large blast radius, so we took our time and looked around.

## Borrowing from a neighbor

The ecosystem we looked at for reference is JavaScript. Not because it's tidy, it's famously not, but because it has many package managers that have spent years pushing each other forward through plain competition. Every package manager, at the end of the day, does roughly the same thing: there's a manifest file that declares dependencies on other packages, there's a registry, a graph gets constructed, and once it's constructed everything is pulled locally into a directory structure the consumers understand, which in Node means reproducing everything under `node_modules` following the conventions of the runtime.

[pnpm](https://pnpm.io) was one of the first to take this seriously, with a global content-addressable store and cheap project-local links instead of full copies. More recently [aube](https://github.com/endevco/aube) from the creators of [mise](https://mise.jdx.dev) pushed install performance a lot further, and that in turn nudged pnpm and [Bun](https://bun.sh) to do similar rewriting. Someone moves the line of what's possible, and everyone else has to follow.

We wanted that for the Swift Package Manager too.

## What we leave to SwiftPM, and what we speed up

There are limits to what we can do, and the most basic one comes from the ecosystem itself. Unlike NPM, which has a central registry and an API you can hit for fast answers like "which versions of this package exist", the Swift package ecosystem is decentralized by design. That's a real strength, but it has a cost: solving the dependency graph means going out to each source and working out which versions satisfy the constraints, and that isn't something we can fundamentally make faster from the outside. A registry-first world would change that, but it isn't the world we live in.

So we didn't touch it. SwifterPM doesn't reimplement the resolver, it hands resolution straight to the Swift Package Manager: under the hood it runs `swift package resolve`, lets SwiftPM solve the graph and do any source-control-to-registry transformation, and reads the resulting `Package.resolved` back. We sort and normalize the pins so the lockfile comes out identical to what SwiftPM would have written, and nothing downstream can tell the difference. We also get Apple's correctness fixes and new manifest features for free, instead of forking the one part of the system you really don't want to get wrong.

What we do own is everything after the versions are pinned: getting those sources onto disk, and reading their manifests. That's where the time and the disk actually go, so that's where we put the work.

## A global store, and links instead of copies

The bigger change is how things are laid out on disk. Everything is arranged so that reproducing the dependencies for any project links back to the same content-addressable store, which becomes the single source of truth for all package data. Archives and extracted source trees are stored once under `$XDG_CACHE_HOME/swifterpm` (or `~/.cache/swifterpm`), keyed by package identity, version, and revision.

There's an easy win in how that store gets populated, one the community has raised several times. Once a revision is pinned, you don't need the whole repository to put its sources on disk, you only need that one revision. So instead of cloning the full history of every dependency, SwifterPM downloads a source tarball of the exact pinned revision through the GitHub or GitLab API, with a shallow Git fetch kept as a fallback. Packages declared through the Swift registry with `.package(id:)` come down as checksum-verified archives. Cloning entire histories just to lay down a single revision is one of the most expensive parts of getting a graph onto disk, and skipping it is a big part of where the cold-run speedups below come from.

The directory where the dependencies get reproduced, `.build/checkouts`, is no longer a full copy of the graph. The entries stay as real directories so the paths Xcode and Tuist expect keep resolving inside the worktree, but their contents are symlinks back into that global store. So instead of materializing the entire source tree of every dependency into each worktree, we lay down a thin set of links that point at bytes that already exist once on disk.

Two things come out of this. Reproducing a package graph gets fast, milliseconds against the seconds it takes to populate a fresh worktree or a new Bazel workspace the usual way, and it barely touches disk because we don't make copies, which matters once you've watched those checkout directories climb into several gigabytes per worktree and felt how unnecessary that is when it's the same bytes over and over.

Writes are concurrency-safe by construction. Restoration runs in parallel, and cache writes use file locks, temporary files, and atomic moves, so several installs across several worktrees can share the same store without stepping on each other. That's precisely the agents-on-worktrees situation our users kept reporting.

## Paying the manifest cost once

There's one more piece, on the reconciliation side. To turn a resolved graph into something a build system can use, you have to read each package's `Package.swift` manifest. Apple is [leaning on statically analyzing the manifest](https://forums.swift.org/t/improving-manifest-loading-performance-for-declarative-package-manifests/85994) and falling back to compiling it when analysis isn't enough. The trouble is that if you look at the real ecosystem, an enormous number of packages aren't meaningfully static. Take one that turns up deep in a lot of dependency graphs, like [SwiftNIO](https://github.com/apple/swift-nio), whose manifest reads environment variables, branches on the platform, and loops over its targets to apply settings. Static analysis can't help you there.

So instead of trying to avoid compiling the manifest, SwifterPM pays that cost deliberately, while it has the package sources in hand, and turns each manifest into a JSON representation it persists locally under `.build/swifterpm/package-info`. Later, when Tuist reconciles the nodes of the graph into a generated project, the format is already there and is very fast to decode. You pay once, up front, and the generation step downstream gets cheaper. The benchmarks below deliberately leave this cache off so they isolate the resolve-and-restore path, which means it's an additional win on top of the numbers you're about to see, not part of them.

## The benchmarks

Numbers, since they're the point. These come from the [SwifterPM benchmark script](https://github.com/tuist/tuist/blob/main/swifterpm/mise/tasks/benchmark/resolution.sh), three runs each, on macOS 26 with Apple Swift 6.3.2. Both tools run against the same `Package.resolved` with forced resolved versions, so we're comparing the cost of getting those exact pins onto disk and nothing else. SwiftPM is pointed at its own isolated cache so its cold run isn't accidentally warmed by caches already on the machine, and the manifest cache is off on both sides. Cold resolution wipes the package-local scratch directories and each tool's shared cache before each run. Worktree-warm resolution wipes the package-local scratch but keeps the primed shared cache, which is exactly what happens when you switch to another clean worktree, the scenario that hurts most with agents.

| Codebase | Scenario | SwiftPM | SwifterPM | Speedup |
|:---|:---|---:|---:|---:|
| Pocket Casts iOS (`Modules/Package.swift`) | Cold | 245.89 s | 140.16 s | 1.75x |
| Pocket Casts iOS (`Modules/Package.swift`) | Worktree-warm | 126.28 s | 0.70 s | **180.40x** |
| Firefox iOS (root `Package.swift`) | Cold | 51.07 s | 14.71 s | 3.47x |
| Firefox iOS (root `Package.swift`) | Worktree-warm | 15.54 s | 0.48 s | **32.27x** |

The cold runs are already a clear win, between 1.75x and 3.47x faster, even though that's the moment SwifterPM is doing its most expensive up-front work, compiling and persisting every manifest. But the cold run isn't the number to fixate on, because the one that matters is worktree-warm: that's the cost a developer running several agents actually pays, again and again, all day, and there resolving Pocket Casts' modules drops from over two minutes to under a second, and Firefox from fifteen seconds to under half a second. Notice that those two warm times are close to each other even though Pocket Casts is about ten times the graph Firefox is when resolved cold, and that's because once the global store is primed, warm restoration is mostly laying down symlinks, so it stays sub-second more or less regardless of how big the graph is. Disk follows the same shape: the global store is populated once instead of being copied into every worktree.

## How to use it

If you integrate Swift packages through Tuist's XcodeProj-based integration, declaring them in `Tuist/Package.swift` and running `tuist install` rather than through Xcode's own package integration, there's nothing to turn on. `tuist install` uses SwifterPM before generation by default on a recent enough Tuist: it's on canary today, with a stable release right behind it. We validated it against real graphs before flipping that default, but there may still be scenarios we don't handle yet, and if you hit one you can fall back to SwiftPM by setting `TUIST_USE_SWIFTERPM=0` in your environment while we fix it.

If you use Bazel, SwifterPM ships a Bzlmod extension with the same resolver shape as `rules_swift_package_manager`:

```python
bazel_dep(name = "swifterpm", version = "0.9.0")

swift_deps = use_extension("@swifterpm//:extensions.bzl", "swift_deps")
swift_deps.from_package(
    resolved = "//:Package.resolved",
    swift = "//:Package.swift",
)
use_repo(swift_deps, "swift_package")
```

And if you build Apple targets with Buck2, SwifterPM ships a small macro that creates a restore target you run before your build:

```python
load("//build_defs:swifterpm.bzl", "swifterpm_restore")

swifterpm_restore(
    name = "restore_swift_packages",
    package = "Package.swift",
)
```

That target resolves and restores the packages, so your Apple build targets can read sources straight from `.build/checkouts` against the shared global store, the same way Bazel and Tuist do.

We're taking our first real steps into Bazel and Buck2, and we wanted this to be useful to those communities from the start. Any company already on one of them, or weighing the move, can pick up the rule and get the same speedups. This is part of a bigger appetite we're building to plug our caching and infrastructure into more technologies, from cacheable generated projects through to Bazel and Buck2, and there's a lot more exploration ahead of us there.

## Where we go from here

I wish I could say this helps everyone, and it doesn't. The integration between Xcode and the Swift Package Manager happens inside Xcode itself, through code we don't control, and it doesn't expose a supported hook where we could swap in a faster resolver or restorer. So we can't bring any of this to plain Xcode projects, even though we'd love to. The best we can hope for there is that it sparks some discussion.

Our next step is to keep iterating on SwifterPM with the help of our users, because real projects are the only way to surface the graph scenarios we don't handle yet. Once we land on something we're happy with, we might consider socializing the contribution upstream. Might, because what SwifterPM changes is a major piece of how SwiftPM operates internally, and a change that size deserves a proper conversation with the maintainers, backed by evidence from real-world usage, before anyone should spend time reviewing it.

In the meantime our users couldn't keep waiting for some future Xcode release to maybe address the pain, and we're in a good spot: as long as we stay aligned with how resolution works, with the state files SwiftPM writes, and with what the clients (Bazel, Buck2, and Tuist) expect, Apple can keep adding things at the language and manifest level, as they did with [traits](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0450-swiftpm-package-traits.md), without that changing the resolution logic underneath.

Give it a try. If you hit a graph we don't handle yet, please [open an issue](https://github.com/tuist/tuist/issues) and include your Swift version and the errors you saw, so we can take a look. This has been a genuinely fun piece to work on, and as always, we'll keep iterating in the open and sharing what we find.
