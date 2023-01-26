---
title: Get started
slug: '/tutorial/get-started'
description: Learn how to install Tuist in your environment and generate your first project.
---

Tuist is a command line tool \(CLI\) that aims to facilitate the generation, maintenance, and interaction with Xcode projects. It's distributed as a binary, which you can easily install and use without having to depend on other tools to manage dependencies \(like you would do if the tool was written in other programming languages such as Ruby, or Java\).

### Install

The first thing that we need to do to get started is installing the tool. To do so, you can run the following commands in your terminal:

```bash
curl -Ls https://install.tuist.io | bash
```

The process is relatively fast because we are actually not installing the tool. We are installing `tuistenv` \(which gets renamed to `tuist`\) when you install it.

A very common issue working on iOS projects is **not having a reproducible environment**. Very often, projects depend on things that should be installed by other tools. To give you an example, if your project depends on [Fastlane](https://fastlane.tools/), chances are that it depends on [Bundler](https://bundler.io/) being installed in the system and a clean Ruby environment with the version that the project expects. If any of those things are missing or are not in a good state, it results in unexpected outputs and a really bad experience for your developers.  
To avoid that, Tuist is self-contained and comes with `tuistenv` which ensures that the right version is used. It manages different versions in your environment and runs the version your project is pinned to. Thanks to that, we ensure that anyone in your team will use the same version of Tuist.  
In a more advanced section on the documentation, we'll see the power of `tuistenv`. For now, we'll keep things simple and just assume that we are running Tuist directly.

### Creating our first project

Now that we have Tuist installed, we can create our first project. Create a directory for your app:

```bash
mkdir MyApp
cd MyApp
```

And then run:

```bash
tuist init --platform ios
```

The `init` command will bootstrap an iOS application, which includes the `Info.plist` files, an `AppDelegate.swift`, a tests file, and a **`Project.swift` that contains the definition of the project.**

> If you have used the Swift Package Manager before, the `Project.swift` file is the equivalent to the `Package.swift`.

:::note SwiftUI template
`tuist init --platform ios --template swiftui` will bootstrap a SwiftUI iOS project instead.
:::

The definition file, also known as manifest, has the following structure:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    organizationName: "MyOrg",
    targets: [
        Target(
            name: "MyApp",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.MyApp",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            resources: ["Resources/**"],
            headers: .headers(
                public: ["Sources/public/A/**", "Sources/public/B/**"],
                private: "Sources/private/**",
                project: ["Sources/project/A/**", "Sources/project/B/**"]
            ),
            dependencies: [
                /* Target dependencies can be defined here */
                /* .framework(path: "framework") */
            ]
        ),
        Target(
            name: "MyAppTests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.MyAppTests",
            infoPlist: "Info.plist",
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "MyApp")
            ]
        )
    ]
)
```

Since we are defining an Xcode project, most of the properties might be familiar to you. There are some that are available which are not used from the manifest that you've got generated. You can [check out](../manifests/project.md) the project reference to see all the public models that are available in the `ProjectDescription` framework.

### Editing your project

To edit your project you can open the relevant Tuist manifests using the command

```bash
tuist edit
```

The generated project will contain the `Project.swift` file and any other required manifest.

### Generating project

We have the manifest and the project files, but something missing, the Xcode project. If we don't have an Xcode project, we can't use Xcode, because that's the format that Xcode expects. Fortunately, Tuist comes with a command to generate projects and workspaces from your manifest files. If we run the following command in the terminal:

```bash
tuist generate
```

We'll get a `MyApp.xcodeproj`and `MyApp.xcworkspace` files. As we'll see in the dependencies section, the workspace is necessary to add other projects `MyApp` project is depending on.  
If you open `MyApp.xcworkspace` and try to run the `MyApp` scheme, it should build the app and run it on the simulator 📱 successfully 🎉.

### Add a badge to your project's README

[![Tuist badge](https://img.shields.io/badge/Powered%20by-Tuist-blue)](https://tuist.io)

Last but not least, you might want to include a badge in your project's README to indicate that the project is defined using Tuist. Simply copy and paste the following Markdown snippet below the title:

```md
[![Tuist badge](https://img.shields.io/badge/Powered%20by-Tuist-blue)](https://tuist.io)
```
