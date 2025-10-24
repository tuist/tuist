---
title: "Tuist Registry is Now Public"
category: "product"
tags: ["Announcement", "Registry"]
excerpt: "We're opening up the Tuist Registry to everyone – no account required. Speed up your Swift package resolution in seconds."
author: pepicrft
---

When we [launched the Tuist Registry](/blog/announcing-tuist-registry) earlier this year, we had a hunch we were onto something. We'd been watching developers wait – sometimes for minutes – as SwiftPM cloned the entire Git history of packages they just wanted to use. We'd seen CI bills climb as teams stored gigabytes of unnecessary Git data. We knew there had to be a better way.

So we built it. And the response exceeded our expectations.

Teams integrated the registry and immediately saw build times drop. CI costs decreased. That frustrating wait during `swift package resolve` became almost instant. Developers who'd grown accustomed to context-switching during dependency resolution suddenly found themselves staying in flow.

But here's the thing: we launched the registry exclusively for Tuist users. You needed an account. You needed a project setup. It worked beautifully for our users, but every time someone outside the Tuist ecosystem asked about it, we had to say "sorry, you need to sign up first."

That never felt right.

If the registry could save time for our users, why shouldn't it save time for everyone? The Swift community has given us so much – from SwiftPM itself to the thousands of open-source packages we all rely on. It was time to give something back.

Today, we're making the Tuist Registry available to everyone. **No account required. No sign-up flow. No barriers.**

Just faster package resolution for the entire Swift community.

## The Problem We All Face

Swift Package Manager's decentralized approach is philosophically beautiful – no central authority, no gatekeepers, just packages living in their repositories. But this design choice comes with a cost that we pay every single day.

When you add a dependency, SwiftPM performs a deep clone of the entire Git repository. Not just the version you need – the entire history. Every commit, every branch, every tag. If you're adding Alamofire, you're downloading years of development history you'll never need. Multiply that by dozens of dependencies, and you're looking at gigabytes of wasted space and minutes of wasted time.

In local development, it's annoying. In CI, where you start fresh on every build, it's expensive and slow.

The Tuist Registry solves this by implementing the [Swift Package Registry protocol](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md). Instead of cloning repositories, it serves immutable snapshots of specific package versions – just the source code you actually need, nothing more. And thanks to our Tigris-based storage, these packages are distributed globally and served from edge locations close to you, ensuring minimal latency no matter where your team or CI infrastructure is located.

The numbers speak for themselves. Teams reported **91% smaller disk usage**, dropping from 6.6 GB to 600 MB. This dramatic reduction in local copy size means CI caching becomes significantly faster – restoring and saving caches that used to take 2 minutes now complete in 20 seconds. Some teams calculated they were saving hours of CI time per week, which translated directly to lower infrastructure costs.

## Real Impact for Real Teams

The feedback we've received since launch has been humbling. We've heard from solo developers who were frustrated by slow package resolution eating into their flow state. From small teams whose CI bills were climbing faster than their revenue. From large organizations managing dozens of internal projects, each with sprawling dependency graphs.

One team told us they'd been considering whether to stick with SwiftPM or move to a different dependency manager entirely. The registry kept them in the ecosystem. Another calculated that the time saved on CI alone paid for their entire Tuist subscription multiple times over.

But the stories that resonated most were simpler: developers who just appreciated not having to wait anymore. Who could `git clone` a fresh checkout and run `swift build` without making coffee first. Who didn't have to explain to new team members why their first build would take 10 minutes.

Here's what teams consistently report:

- **Smaller local copies**: 91% reduction in disk usage means your dependencies take up far less space
- **Faster CI caching**: Smaller caches restore and save significantly faster on every CI run
- **Low-latency access**: Packages served from edge locations close to your team via Tigris-based global storage
- **More deterministic builds**: Serving immutable snapshots instead of relying on Git tags eliminates a whole class of reproducibility issues
- **Lower infrastructure costs**: Smaller cache sizes translate directly to reduced storage and bandwidth costs in CI

The registry mirrors all packages from the [Swift Package Index](https://swiftpackageindex.com/), serving over 8,400 packages and 130,000 releases. Our Tigris-based storage infrastructure distributes these artifacts globally, ensuring they're served from edge locations near you for minimal latency.

## Going Public

We built the registry initially for Tuist users, requiring an account for access. But as we watched the impact it had, we realized this shouldn't be limited to our users. The entire Swift community deserves faster, more reliable package resolution.

The decision to go public wasn't just philosophical – it was practical. We've built infrastructure that can handle massive scale. We're serving millions of package requests every month with edge storage distributed globally. We've solved the hard problems around security, reliability, and performance. Keeping it locked behind an account requirement felt like artificial scarcity.

So we're removing the gate.

Starting today, **anyone can use the Tuist Registry without creating a Tuist account**. Just run one command in your project:

```bash
tuist registry setup
```

That's it. No sign-up, no authentication, no configuration files to manage. The command generates a registry configuration file that you commit to your repository, and your entire team benefits immediately.

We're betting that the value we provide – faster resolution, lower costs, better developer experience – will speak for itself. Some teams will eventually want our other features and become Tuist users. Others won't, and that's perfectly fine. The registry is useful on its own, and we're happy to provide it to the community.

## Choose Your Experience

We're offering two modes of access to fit different needs:

### Unauthenticated Access (Default)

Perfect for most projects and teams. No account required, no authentication needed. Standard rate limits (1,000 requests per minute) are more than sufficient for typical development workflows.

```bash
tuist registry setup
```

### Authenticated Access

For teams with heavy usage patterns or large monorepos that need higher throughput, authenticated access removes rate limits entirely. This mode requires a Tuist account and project:

```bash
tuist registry setup --authenticated
```

With authenticated access, only one person needs to run the setup command. Team members just run `tuist registry login` to authenticate themselves using the configuration already in the repository.

## Getting Started

If you don't have Tuist installed yet, [install it](https://docs.tuist.dev/en/guides/quick-start/install-tuist) first. Then, in your project directory:

```bash
tuist registry setup
```

The registry works with any Swift package setup – whether you're using Tuist, plain Xcode projects, or pure SwiftPM packages. No changes to your project structure required.

### How Package Resolution Works

When you reference a package, you can use the registry identifier convention instead of the Git URL. For example, instead of:

```swift
.package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0")
```

You can use:

```swift
.package(id: "alamofire.alamofire", from: "5.0.0")
```

The registry identifier follows the pattern `{organization}.{repository}` (all lowercase). When you use this identifier, SwiftPM automatically pulls the package from the Tuist Registry instead of cloning the Git repository. The identifier can't contain more than one dot – if the repository name contains a dot, it's replaced with an underscore (e.g., `GRDB.swift` becomes `groue.grdb_swift`).

You can continue using Git URLs if you prefer – the registry configuration works with both approaches. Using identifiers is optional but recommended for maximum efficiency.

For detailed setup instructions and integration guides for different project types, check out our [documentation](https://docs.tuist.dev/en/guides/features/registry).

## Our Commitment to the Community

The Tuist Registry is our contribution to making the Swift ecosystem better for everyone. We've contributed bug fixes to SwiftPM's registry implementation and even [contributed a PR to parallelize package retrieval](https://github.com/swiftlang/swift-package-manager/pull/8220) that has been merged and will make resolution up to 2x faster for everyone in the next Swift release – whether they use a registry or not.

We take security seriously. We mirror only packages from the Swift Package Index, pull sources directly from original repositories, and rely on SwiftPM's built-in checksum verification to ensure package integrity. We're proud to be **SOC 2 Type II compliant**, providing formal verification that our security practices meet the highest industry standards. Your dependencies deserve that level of protection.

## What's Next

Opening the registry to everyone is just the beginning. We're committed to making it faster, more reliable, and more useful. If you have ideas, feedback, or questions, we'd love to hear from you on our [community forum](https://community.tuist.dev/) or [GitHub](https://github.com/tuist/tuist).

Try it today. We think you'll love how much time you save.

```bash
tuist registry setup
```
