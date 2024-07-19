---
title: Use Tuist with a Swift Package
description: Learn how to use Tuist with a Swift Package.
---

# Using Tuist with a Swift Package <Badge type="warning" text="beta" />

Tuist supports using `Package.swift` as a DSL for your projects and it converts your package targets into a native Xcode project and targets.

> [!WARNING]
> The aim of this feature is to provide an easy way for developers to assess the impact of adopting Tuist in their Swift Packages. Therefore, we don't plan to support the full range of Swift Package Manager features nor to bring every Tuist's unique features like [project description helpers](/guides/develop/projects/code-sharing) to the packages world.

> [!NOTE] ROOT DIRECTORY
> Tuist commands expect a certain [directory structure](/guides/develop/projects/directory-structure#standard-tuist-projects) whose root is identified by a `Tuist` or a `.git` directory.

## Using Tuist with a Swift Package

We are going to use Tuist with the [TootSDK Package](https://github.com/TootSDK/TootSDK) repository, which contains a Swift Package. The first thing that we need to do is to clone the repository:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

Once in the repository's directory, we need to install the Swift Package Manager dependencies:

```bash
tuist install
```

Under the hood `tuist install` uses the Swift Package Manager to resolve and pull the dependencies of the package.
After the resolution completes, you can then generate the project:

```bash
tuist generate
```

Voilà! You have a native Xcode project that you can open and start working on.