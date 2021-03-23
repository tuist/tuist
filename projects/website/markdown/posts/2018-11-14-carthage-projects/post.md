---
layout: post
title: "Generate Carthage-compatible Xcode projects for your open source libraries"
date: 2018-11-14
categories: [tuist, carthage, cocoapods, swift]
excerpt: Learn how you can leverage Tuist and the project generation to make the generation of Carthage-compatible projects more convenient and aligned with the approach other package managers follow.
author: pepibumur
---

If you are o have been a maintainer of an open source Swift project, you might have realized how inconvenient it is giving support to all package managers out there: [CocoaPods](https://cocoapods.org/), [Carthage](https://github.com/carthage) and the [Swift Package Manager](https://github.com/apple/swift-package-manager). Each of those package managers follows a different approach for defining the structure of your package. A Ruby `.podspec` file if it’s CocoaPods, a Swift `Package.swift` manifest in case of the Swift Package Manager and an Xcode project in Carthage.

The latter is perhaps the most inconvenient. **Any change in your project files need to be reflected in the Xcode project**. Otherwise, you get a package ready for CocoaPods and Swift Package Manager, but that is broken for Carthage. Those changes are usually done manually, and projects set up the CI pipeline that compiles the Carthage project and makes sure that the integration doesn’t break.

In this short blog post, I’d like to show you how we can make generating the Carthage project more convenient and aligned with the other package managers’ approach.

To generate an Xcode project for Carthage, you need to have Tuist installed in your system. You can do it by just running the following command in your terminal:

```bash
eval \"\$(curl -sL https://bit.ly/2JWMfx8)\"

```

Once installed, we need to generate a manifest `Project.swift` file in the project directory. You can look at that file as an equivalent to the `Package.swift` but more generic and valid for any type of Xcode project:

```swift
// Project.swift
import ProjectDescription

let project = Project(name: "MyProject-Carthage",
                      targets: [
                        Target(name: "MyProject",
                               platform: .macOS,
                               product: .framework,
                               bundleId: "io.tuist.MyProject",
                               infoPlist: "Info.plist",
                               sources: "Sources/MyProject/\*\*",
                               dependencies: [
                                  .framework(path: "Carthage/Build/Mac/SwiftShell.framework")
                               ])
                              ]
)
```

As you can see in the code snippet, a project has a name, which is the name of the Xcode project that will get generated, and a list of targets, which represent Xcode project targets. In that example, we are creating a framework for macOS with the name `MyProject`, and that compiles all the sources in the `Sources/MyProject/` recursively. Note that you can also include resources and specify custom build settings. You can check all the attributes that are available on [this link].

> You can define dependencies with other Carthage frameworks passing them in the `dependencies` attribute. Tuist will set up the linking build phase.

With the manifest created in the project directory, we can run the following command:

```bash
tuist generate

```

It’ll generate the Xcode project automatically 🚀. **The project generation is deterministic**, that means that the same command executed several times should produce the same Xcode project. You can run that command as part of your CI and fail if the command results in a diff in the git repository. [Danger](https://danger.systems) is a great tool to report the error back to GitHub and ask developers to re-generate the project and push the changes.

### Shortcomings

- Tuist doesn’t support defining schemes yet _(but we are working on it)_. That means that you need to double check if the scheme that Xcode generates automatically is shared.
- If you want to support multiple platforms, you need a target per platform with the same name but with a different product name. Although you can change that by passing build settings, we plan to expose a new attribute in the `Target` model to make it more explicit.

### Wrapping up

I hope you liked the blog post. As you can see, **Tuist is opening the door to having more automation in your projects and saving a lot of time** that you’d have spent tweaking the projects yourself. This is just a use case for Tuist, but there are many others. If you are eager to know more about what’s coming to Tuist, I recommend you to check out the [organization roadmap](https://github.com/orgs/tuist/projects/4).

Can’t wait to share more with you soon! 👩‍💻
