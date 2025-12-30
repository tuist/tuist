---
title: Bundling Javascript in Swift projects using ESBuild
category: "product"
tags: ['Swift', 'ESBuild', 'JavaScript']
excerpt: 'SwiftyESBuild: Streamlining Swift Web Bundling and JavaScript Integration for Effortless Development.'
author: pepicrft
---

In an ongoing effort to streamline the process of building web apps and sites with Swift, I am delighted to introduce a new Swift Package: [**SwiftyESBuild**](https://github.com/pepicrft/SwiftyESBuild). While modern browsers are capable of resolving and downloading [ES module graphs](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Modules), many projects still resort to bundling for various reasons, such as optimizing loading speed and supporting modern JavaScript features that may not be compatible with certain browsers. Nowadays, there is an abundance of tools available to assist with this task, but one tool, in particular, has gained significant popularity and serves as a foundational block for other tools like [Vite](https://vitejs.dev), [ESBuild](https://esbuild.github.io).

Communities like JavaScript's or Ruby's have already discovered a seamless installation path (e.g. [jsbundling-rails](https://github.com/rails/jsbundling-rails)) that doesn't require the installation of additional runtimes like Node. Unfortunately, the Swift community lacks a similar streamlined method to integrate it into projects powered by frameworks like [Vapor](https://vapor.codes) or [Publish](https://github.com/JohnSundell/Publish). This is where SwiftyESBuild comes in. By adding SwiftyESBuild as a dependency through a Swift Package, you can effortlessly incorporate the tool into your project. With just a few lines of code, you can use it to generate production-ready artifacts or keep it running in the background, automatically monitoring for any file changes.

## Getting started

To get started with `SwiftyESBuild`, all you have to do is add the dependency to your project:

```swift
.package(url: "https://github.com/tuist/SwiftyESBuild.git", .upToNextMinor(from: "0.1.0"))
```

After adding the dependency, you'll need to create an instance of `SwiftyESBuild`:

```swift
let esbuild = SwiftyESBuild(version: .latest)
```

If you don't pass any arguments, it defaults to the latest version in the system's default temporary directory. If you're working in a team, we recommend fixing the version to minimize non-determinism across environments.

## Running ESBuild

Running ESBuild is as easy as invoking the `run` function on the `esbuild` instance, passing the options you want to use:

```swift
import TSCBasic // AbsolutePath

let entryPointPath = AbsolutePath(validating: "/project/index.js")
let outputBundlePath = AbsolutePath(validating: "/projects/build/index.js")
try await esbuild.run(entryPoint: entryPointPath, options: .bundle, .outfile(outputBundlePath))
```

Check out [`SwiftyESBuild.RunOption`](https://github.com/tuist/SwiftyESBuild/blob/main/Sources/SwiftyESBuild/SwiftyESBuild.swift) to know the available options. Note that not all the options supported by ESBuild are available, which is why we've added an `.arguments` option that allows you to pass any argument to the ESBuild CLI.

## Next steps

We'll add some examples for how to use the tool with frameworks like [Vapor](https://vapor.codes) and [Publish](https://github.com/JohnSundell/Publish). Additionally, we plan to build a Swift Package to integrate [Orogene](https://orogene.dev) into Swift projects. This will allow developers to resolve and pull NPM packages without having to install Node in their system. It's the last missing step to have a fully integrated JavaScript bundling experience in Swift projects without requiring Node installation.
