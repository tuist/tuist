---
layout: post
title: Visualize your projects graph from Tuist 0.17.0
date: 2019-06-21
categories: [tuist, release, swift]
excerpt: One of the difficulties of scaling up Xcode projects comes from the fact that Xcode doesn't provide a high-level picture of the structure of the project. Tuist 0.17.0 fixes that by providing a new command, 'tuist graph', that exports a graph of the project to help users of the tool visualize their project dependencies. This version also adds support for configuring Tuist globally, and also indicate the version of Xcode that is required to run the project.
author: pepibumur
---

Hola 👋

Last week we released a new version of Tuist,
0.17.0,
which comes packed with a handful of great improvements that will make your experience interacting with your projects more pleasing.

In this post,
I'd like to guide you through some of those new features,
as well as showing you some minor improvements and bug fixes that we have also introduced.

Let's get started.

## Support for multiple configurations 📝

It's a common practice to use build configurations to define variants for our apps other than `Debug` and `Release`.
Unfortunately,
Tuist only supported configuring `Debug` and `Release`,
and that was a limiting factor for some users to adopt Tuist.

We have good news for you; with the latest version of Tuist, you can define all the configurations that your project needs:

```swift
let targetSettings = Settings(
  base: [:],
  configurations: [
    .debug(name: "Debug", settings: [:], xcconfig: "xcconfigs/Debug.xcconfig"),
    .release(name: "Release", settings: [:], xcconfig: "xcconfigs/Release.xcconfig"),

    // Beta build variant
    .release(name: "Beta", settings: [:], xcconfig: "xcconfigs/Beta.xcconfig"),
  ],
  defaultSettings: .recommended
)

```

## Graph 🔀

When Xcode projects get larger,
being able to see how projects and targets depend on each other is handy to make decisions to extend the modularity of the project.
Moreover,
it makes it easier for newcomers to have a picture of the whole project without having to open Xcode and wander around.

The usage is very simple.
Being in a directory that contains a project,
run the following command:

```
tuist graph
```

That generates a `graph.dot` file that we can turn into a visual representation using [Graphviz](https://www.graphviz.org/) or [this online tool](https://dreampuf.github.io/GraphvizOnline).

## Global configuration 📝

We are glad to welcome `TuistConfig.swift` to the family!
We realized that configuring Tuist for all the projects that are part of a repository was not possible and required having to pass argument when calling different tuist commands.
To make that easier we introduced the concept of a configuration that is globally applied to all the projects that are part of a repository.
Imagine we have the following folder structure:

```bash
/.git
/TuistConfig.swift
/Core/Project.swift
/Settings/Project.swift
/App/Project.swift
```

And the following content in the `TuistConfig.swift` file:

```swift
import ProjectDescription

let config = TuistConfig(
  generationOptions: [
    .xcodeProjectName("MyCompany-\(.projectName)")
  ]
)
```

With the configuration above,
all the generated Xcode projects will follow the configured naming convention.

> Note how Swift and its powerful type system allows interpolating pre-defined variables into the strings.

## Compatible Xcode versions ✅

_Have you ever tried to compile a project with an Xcode version that the project is not compatible with?_
It often results in compilation errors because the project hasn't been updated yet.
Xcode doesn't allow pinning a project to a specific Xcode version,
and thus when the OS updates Xcode automatically,
developers run into this issue.

The latest version of Tuist allows defining a version or list of versions that your projects are compatible with.
We can do so by using the global configuration:

```swift
import ProjectDescription

let config = TuistConfig(
  compatibleXcodeVersions: ["11.3"]
)
```

If a developer in your team tries to use the project with a non-compatible version of Xcode,
Tuist will fail letting developers know why.

## CocoaPods support 📦

In order to use CocoaPods with Tuist,
developers had to manually execute `pod install` right after the project generation.

That's not necessary anymore because we've added support for a new type of dependency, `.cocoapods`. Targets can use that type of dependency to indicate that `pod install` needs to be run after generating the project the target belongs to.

Note that Tuist doesn't validate the right configuration of the `Podfile` nor makes sure that Tuist's dependency graph and CocoaPod's merge gracefully.
For that reason,
we suggest defining CocoaPods dependencies from the app targets and not from its dependencies.

## Other improvements ⭐️

### productName support

Targets can now specify their product name without having to define a build setting for that:

```swift
let macosTarget = Target(name: "CoremacOS", productName: "Core")
let iosTarget = Target(name: "CoreiOS", productName: "Core")
```

### Support static products depending on dynamic frameworks

Before this version,
it was not possible to link a static product against a dynamic framework.
That's possible now.
As always,
Tuist will take care of defining the right build settings and phases for you.

### Swift project

Tuist is now more integrated into the `swift` command line namespace.
Its command line interface is now available through the `swift project` namespace.
For example,
if you try to run `swift project init`,
It'll generate an empty project using Tuist.

### Generate a single project

By default,
`tuist generate` generates all the projects that are part of the dependency graph.
However,
there are some scenarios where the users might just be interested in generating the project in the current directory.
For that reason,
we added support for generating only the project in the current directory.

It's as easy as passing the `--project-only` argument to the generate command:

```bash
tuist generate --project-only
```

### Support for multiple header globs

Before this version,
it was only possible to specify the headers that were part of a target by passing a string with a glob pattern.
This was limiting so we made it more flexible by supporting a list of patterns:

```swift
let headers = Headers(public: ["Headers/**/*.h", "Other/**/*.h"])
```

## Bug fixes 🐛

This release also fixes bugs that have been detected and reported by users:

- Ensure that transitive SDK dependencies are added correctly.
- Ensure that the correct platform SDK dependencies path is set.
- Update manifest target name such that its product has a valid name.
- Do not create Derived/InfoPlists folder when no InfoPlist dictionary is specified.
- Set the correct `lastKnownFileType` for localized files.

## Some final words

I'm tremendously grateful to all the maintainers and contributors that made this release possible without breaking changes, and putting emphasis into the simplicity and sustainability of the codebase.

We look forward to your feedback; it's very valuable for us to keep improving Tuist to address the needs and challenges you face in the problem of scaling app Xcode projects.

Remember,
you can join our [Slack channel](https://slack.tuist.io) and talk to another users that are already benefiting from Tuist in their projects.
