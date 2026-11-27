---
title: "Implicit and redundant dependencies in Xcode projects"
category: "engineering"
tags: ["engineering", "xcode", "dependencies", "build-times"]
excerpt: "A target that imports a module it never declared builds on your machine and fails on CI. Here is why Xcode lets that happen, how to find those implicit dependencies, and why the dependencies nobody uses are worth removing too."
author: rofle100lvl
---

My name is Roman Gorbenko and I work on the iOS app of Yandex Travel. While modularizing our project, I kept running into a class of bug that is hard to argue with: the build worked on my machine and failed on continuous integration, with nothing in the diff to explain it.

The cause was implicit dependencies. This post covers what they are, why Xcode produces them, how to find and remove them, and — at the end — their mirror image: redundant dependencies, which cost build time instead of correctness.

## A build that succeeds only sometimes

Implicit dependencies are a design mistake in Xcode. I am not the only one who thinks so; [Pedro Piñera](https://github.com/pepicrft), Tuist's founder, has made the same argument. What they introduce is inconsistent build behaviour. Here is what that looks like.

Take two targets, `A` and `B`. Target `A` contains `A.swift`, which imports `B`:

![A Swift file in Target A containing the statement "import TargetB"](/marketing/images/blog/2026/08/30/implicit-dependencies/a-swift.png)

In the manifest, both `Target Dependencies` and `Link Binary With Libraries` for target `A` are empty:

![Xcode's Target Dependencies section for target A, showing zero items](/marketing/images/blog/2026/08/30/implicit-dependencies/target-dependencies-empty.png)

![Xcode's Link Binary With Libraries section for target A, showing zero items](/marketing/images/blog/2026/08/30/implicit-dependencies/link-binary-empty.png)

Build `A` from a clean state and you get exactly what you would expect:

![An Xcode error banner reading "No such module 'B'"](/marketing/images/blog/2026/08/30/implicit-dependencies/no-such-module.png)

That is reasonable. `B` is not among `A`'s dependencies. But now build `B` first, and then build `A`:

**Build Succeeded.**

That is no longer reasonable. Whether target `A` compiles depends on which other targets happen to have been built already. The same thing happens with Swift Package Manager packages, so switching manifest format does not save you.

## Why it happens

To explain it, we need to look at what a build actually does.

Xcode starts by building the dependency graph of the targets. Then it builds that graph from the leaves towards the root. The root is normally your host app target, or whichever target you asked for.

![A target dependency graph with Target A at the root, depending on Target B, Target C and Target D, with a chain descending from Target C down to Target X, and an arrow labelled "Build" pointing from the leaves upwards](/marketing/images/blog/2026/08/30/implicit-dependencies/build-order.jpg)

The compiled modules end up in DerivedData. That directory contains a `Build` folder and an `Index.noindex` folder, and under `Build/Products` you find every target that has been built so far:

![A directory tree of Build/Products/Debug-iphonesimulator containing A.framework and B.framework, each with their binary, Headers, Info.plist, Modules and _CodeSignature](/marketing/images/blog/2026/08/30/implicit-dependencies/derived-data-products.jpg)

The last piece is the command Xcode uses to compile target `A`. Open the failed build in the report navigator and expand the compilation step. Xcode calls a plain `swiftc`, and among its arguments is this one:

```bash
swiftc -module-name A -Onone \
  ... \
  -F /Users/rofle100lvl/Library/Developer/Xcode/DerivedData/BS-acsgxrgrmnqlmtbgnzxkitbhbwfa/Build/Products/Debug-iphonesimulator \
  ...
```

`swiftc --help` explains what `-F` is:

```
-F <value>    Add directory to framework search path
```

That directory is `Build/Products` — the place where every already-built target lives. So when Xcode compiles a target, it knows about everything that has been built up to that point, and it never checks whether the import was declared in the manifest. That is where implicit dependencies come from.

## What this means in practice

The simple case is the one above: target `A` builds or fails depending on whether target `B` was built first.

The chains are worse.

![Three targets in a row: Target A points to Target B, Target B points to Target C, and a dotted arc runs from Target A directly to Target C](/marketing/images/blog/2026/08/30/implicit-dependencies/implicit-chain.jpg)

Here the manifest declares `A -> B` and `B -> C`, but not `A -> C`, even though `A` imports `C`. The project builds, because `C` is on disk by the time `A` is compiled. Later, a refactor removes the dependency between `B` and `C`. Locally the project still builds. On CI it fails with `No such module C`, because nothing tells `A` about `C` any more.

## Why this is a problem

Because a local build is not consistent with a CI build. Building the project on your machine tells you nothing reliable about whether it will build on CI.

How often does this bite? If you never touch the module structure of your project, possibly never. I was deep in a modularization effort and hit it every single day for a month. Dozens of hours spent on pointless CI runs are what pushed me to look for a solution, and to build one inside Tuist.

## Defining the problem

Let's be precise. An implicit dependency is **a dependency used in code but not declared in the manifest**.

So finding all of them means finding every import in the code, finding every dependency in the manifest, and subtracting the second set from the first. What is left over is undeclared.

![Two circles labelled "Manifest dependencies" and "Code imports". The part of "Code imports" that falls outside the manifest circle is highlighted and captioned "Implicit dependencies"](/marketing/images/blog/2026/08/30/implicit-dependencies/sets-implicit.jpg)

The picture we want is a single circle: the two sets coincide.

That gives four steps:

1. Find the imports in the code.
2. Find the dependencies in the manifest.
3. Subtract the manifest set from the code set.
4. Add the missing dependencies.

## Step 1: finding imports in the code

There are two realistic options: SwiftSyntax, or searching by hand.

SwiftSyntax has two problems that ruled it out. It can be slow compared to running a regular expression, and it only handles Swift — which is fair enough, but in Tuist we wanted Objective-C too. So regular expressions became the main tool.

Swift has four kinds of import to account for: the plain `import A`, several on one line as `import A; import B`, a submodule as `import A.submodule`, and a type import as `import struct A.SomeStruct`. One expression covers all of them, because everything after the module name can be ignored:

```
import\s+(?:struct\s+|enum\s+|class\s+)?([\w]+)
```

Objective-C has three: `#import <UIKit/UIKit.h>`, `#include <CoreFoundation/CFLogUtilities.h>` and `@import Foundation;`. Two alternatives are enough, since the first two forms differ only in the keyword:

```
@import\s+([A-Za-z_0-9]+)|#(?:import|include)\s+<([A-Za-z_0-9-]+)/
```

The one thing that will bite you is comments. A line like `// import TargetA` matches the import expression perfectly well, and a commented-out import is not a dependency. So comments are stripped from the source first, with `//.*?$` for single-line ones and `/\*[\s\S]*?\*/` for multi-line ones, and only then does the import expression run over what is left.

## Step 2: finding dependencies in the manifest

What we need here is small: for every target, the set of module names it declares as dependencies. That means target dependencies, linked frameworks, and package products, all flattened into one set of names comparable with the imports we just scanned.

The awkward part is that the declaration can live in three different places — a Tuist manifest, a `Package.swift`, or an `.xcodeproj` / `.xcworkspace` — and none of them are shaped alike.

Tuist's answer is not to write a reader per format. It loads all three into a single representation of the project, the same dependency graph it uses everywhere else, and everything downstream works on that. If it finds a root Tuist manifest at the given path, it loads the graph from the manifests. If it doesn't, it maps the raw Xcode project, workspace, or package into the very same graph, with [XcodeProj](https://github.com/tuist/XcodeProj) doing the parsing underneath.

There is one wrinkle worth knowing about. In a non-generated project, a target usually depends on a *package product*, not on a target, and a single product can contain several targets. Comparing product names against import statements would report imports of those inner targets as undeclared. So before comparing, Tuist expands each package product into the targets it actually vends.

Once that's done, the check no longer cares which manifest format the project started from.

## Step 3: subtract

With both sets in hand, the answer is one line:

```swift
let implicitImports = sourceDependencies
    .subtracting(explicitTargetDependencies)
```

## Step 4: add what's missing

Removing an implicit dependency means opening the manifest and declaring it. For the `A` and `B` example at the top of this post, that means adding `B` to `A`'s target dependencies:

![Xcode's Link Binary With Libraries section for target A, now listing TargetB.framework](/marketing/images/blog/2026/08/30/implicit-dependencies/link-binary-targetb.png)

## Existing tooling

Tuist ships this check. If you use Tuist, you get it with:

```bash
tuist inspect dependencies --only implicit
```

It exits with a non-zero code when it finds anything, which is what makes it useful in CI. It works with generated projects, Swift packages, and raw Xcode projects and workspaces.

## The nearly-free second feature

Once every implicit dependency has been added to the manifest, the two sets should coincide. In reality, this is what you get:

![A large orange circle labelled "Manifest dependencies" fully containing a small white circle labelled "Code imports", with a question mark in the surrounding area, captioned "Redundant dependencies"](/marketing/images/blog/2026/08/30/implicit-dependencies/sets-redundant.jpg)

The leftover region is the second kind of problem: **redundant dependencies**. They are declared in the manifest and used nowhere. They usually arrive by accident — a refactor removes the code that used another module, and nobody removes the entry from the manifest.

Why not just leave them? Because of how Xcode builds, again. It builds along the declared edges. If one of those edges points at a module the target does not need, that module gets built anyway. When you build the whole app it is hard to notice, since every target gets built regardless. When you build one specific target, the redundant subtree can take a real bite out of its build time.

![The same target graph. The edge below Target C is marked in red, and Target C and Target X are highlighted as built while Target B and Target D are not](/marketing/images/blog/2026/08/30/implicit-dependencies/redundant-build-order.jpg)

Finding them is the subtraction we already have, run the other way round:

```swift
let redundantImports = explicitTargetDependencies
    .subtracting(sourceDependencies)
```

Removing them means deleting the entry from the manifest. In Tuist:

```bash
tuist inspect dependencies --only redundant
```

Running `tuist inspect dependencies` without `--only` runs both checks.

## Results

Adding every implicit dependency to the manifest, and wiring the check into CI, stopped the project from breaking on CI. The work itself is routine and quick — it took about two days — and we clearly saved more time than we spent.

Cleaning out the redundant dependencies took a couple of hours. The full application build time stayed the same, as expected. But targets that had been dragging redundant dependencies along built between 5% and 20% faster.

Neither of these is a heroic optimization. Both are the kind of thing worth doing once and then keeping honest with a check on CI.
