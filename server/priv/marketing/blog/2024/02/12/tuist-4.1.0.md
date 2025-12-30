---
title: "Tuist 4.1.0"
category: "product"
tags: ["tuist", "release", "cloud"]
excerpt: "Tuist 4.1.0 is out with new features, improvements, and bug fixes. In this blog post, we'll cover the highlights of this release."
author: pepicrft
---

And after the exhaustive work to release Tuist 4, we are back shipping new features and improvements. Today we just released [Tuist 4.1.0](https://github.com/tuist/tuist/releases/tag/4.1.0), which includes new features, improvements, and bug fixes. In this blog post, we'll cover the highlights of this release.

### Better support for Objective-C packages

One of our long-standing issues in our backlog were problems trying to integrate Swift Packages with Objective-C code in them. The Swift Package Manager, which was designed as a package manager for packages with Swift code, succumbed to the complexity of integrating Objective-C code. To make them work, the Swift Package Manager has some logic for generating module maps and passing the right build settings to the dependent targets. This is logic that Tuist didn't have, and therefore users had to manually figure out what were the right settings to pass to the dependent targets.

Luckily, that's no longer needed from Tuist 4.1.0. [Marek](https://github.com/fortmarek) did an [amazing job](https://github.com/tuist/tuist/pull/5887) going deep into understanding Swift Package Manager's logic and porting it over to Tuist. If you were having issues with Objective-C packages, you can try again with Tuist 4.1.0. Please, note that there might be package scenarios out there (we look at you Google), that are convoluted and that might require additional work from us. If so, please, file an issue and we'll look into it.

### Add support for visionOS to our resource synthesizing templates

As you might know, Tuist supports generating code interfaces to access resources and leverage the compiler's type safety. This is a feature that we call resource synthesizing. In Tuist 4.1.0, we added support for `visionOS` to our resource synthesizing templates. If you are building an app for visionOS, you can now use the resource synthesizing feature to access your resources in a type-safe way.

### How to update

You can use [Mise](https://mise.jdx.dev/) to install the latest version and pin it to your project. To do so, run the following command:

```bash
mise install tuist@4.1.0
mise local tuist 4.1.0
```

Happy Xcoding!
