---
layout: post
title: 'Introducing Tuist'
date: 2018-09-05
categories: [introduction, tuist]
excerpt: Tuist was oficially released. Read more on this blog post about what motivated us to build Tuist and how it can help you scale your Xcode projects.
author: pepibumur
---

I started working on an Xcode project parser in Swift over a year ago. The goal was implementing a tool that would help large teams scale their Xcode projects. At that time I was doing much research on modularizing Xcode projects. It helped to overcome common issues such as compilation times, which **had a very negative impact on developer's productivity and motivation**. You can read more about it [here](https://github.com/pepibumur/microfeatures-guidelines).

Modularization turned out to be an excellent step, but not enough. There was another set of challenges with which that Xcode and the existing tooling didn’t help. Complex Xcode projects, inconsistent settings that led to unexpected compilation errors, or non-standardized and unreliable automation DSLs are some examples of challenges that teams face when their organizations and projects grow.

Companies like [Facebook](https://facebook.com), [Airbnb](https://medium.com/airbnb-engineering/building-mixed-language-ios-project-with-buck-8a903b0e3e56), [Uber](https://eng.uber.com/ios-monorepo/), or [Pinterest](https://www.youtube.com/watch?v=wewAVF-DVhs) invest a fair amount of resources into addressing those challenges, for example, replacing the Xcode build system. However, not all the companies can afford it, and those have to battle the issues mentioned above on a daily basis. As you can imagine, that's one of the last things an app developer wants to be doing as part of their job.

When I looked at the spectrum of tooling I found out that there were options on both extremes, but nothing in the middle for those medium-sized companies to adopt. One one side, there was Xcode, `xcodebuild`, and [Fastlane](https://github.com/fastlane), and on the other hand, alternative build systems such as [Buck](https://github.com/facebook/buck), or [Bazel](https://bazel.build).

I felt there was a definite need for a tool, which had user-experience oriented focus, and that helped medium-size companies overcome the scaling struggles. I'm happy to share with you a very early version of that tool, Tuist. In this blog post I'll talk about the goal of Tuist, how we plan to achieve it, and hopefully, convince you to give it a try and contribute to the project.

## 🙉 What makes scaling difficult?

Before we dive into what Tuist does and how I think it's important to understand why Tuist in the first place. I briefly mentioned in the introduction that the growth of a project comes with some challenges which I'd like to extend in this section. In my experience, the points below are a typical pattern in medium-size companies:

- **Configuring the project right:** Configuring a multi-target project is cumbersome unless we use CocoaPods to define the project, which does all that work for us. As opposed to Android, where Gradle infers most of the build settings for you, Xcode expects us to do it right. That's not easy, especially if it's a large project with transitive dependencies. When we create a new project, it compiles and everything works, but as we start adding targets, dependencies, build settings, it's our responsibility to make sure the project configuration is in a healthy state. The validation of our settings usually happens at compilation time, and sometimes when we are sending the app to the store.

- **Non-actionable errors** When something unexpected happens, we may get an error that doesn't tell us much about what happened. _What caused this?_ _What does this mean?_ _What do I need to do to fix this?_ Sometimes, the solution is reverting our changes on git and trying again.

- **Non-standard DSLs:** How do I build target `Core`? Should I execute `fastlane build_core`, or is it `fastlane core_build`? Fastlane is powerful, and gives us tons of flexibility, but that comes at a cost: inconsistencies and complexity. On one side, each project defines their set of lanes, which are maintained by the team responsible for the project. Unless the collaboration and communication is is good across teams, each `Fastfile` in the project will be different from the others, even though they usually expose a similar set of actions. Furthermore, those `Fastfiles` are rarely tested, which leads to unreliable automation logic that breaks at any time without us noticing it. Have you ever experienced your continuous integration pipelines green for a week, and then failing when you try to release the app to the store?

- **Reusing configuration:** In apps made of multiple projects or targets, it's common that those targets have a similar structure. While Xcode allows reusing build settings across them by using `.xcconfig` files, that's the only thing you can reuse. _What if we'd like to have the same linking frameworks section because all the targets link the same dependencies?_ _What if we'd like to have similar schemes for those targets?_ Well, that's not possible in Xcode projects. In my experience, those kinds of projects end up with a lot of duplicated information. _Why would we reuse code but not or projects configuration?_

## 🧠 How does it work?

**In a nutshell, Tuist leverages projects generation to address those challenges.** Instead of having Xcode projects and workspaces, developers define the projects in manifest files, which Tuist uses to generate the projects and workspaces and provide you with a reliable, easy to use and standard actions.

A manifest file is a `Project.swift` file, which looks like this:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        Target(
            name: "MyApp",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.MyApp",
            infoPlist: "Info.plist",
            sources: "Sources/**",
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
            infoPlist: "Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "MyApp")
            ]
        )
    ]
)
```

If you have used the [Swift Package Manager](https://swift.org/package-manager/) before, this approach might sound familiar to you. One of the benefits of defining the project in a Swift file instead of formats like YAML or JSON is that you can leverage Xcode to validate the syntax and get code auto-completion.

Generating the project allows **understanding your project** and **hiding implementation details and complexities**. Some project elements are intentionally not available in the manifest. Instead, we provide a more straightforward interface, and we deal with the complexity.

Take for instance linking dependencies. You might already know that all transitive dynamic dependencies need to be embedded into the apps. If you forget about any transitive dependencies, you end up the simulator linker complaining about frameworks not found. With Tuist, that's not a problem. You tell us what depends on what, and we set up the right build settings and build phases.

Getting your input through manifest files allows, not only generating a valid project but providing a **set of commands that reliably work with those projects**. As opposed to Fastlane, where you should write lanes that take the right arguments, Tuist knows the structure of the project and can infer most of those things for you. The goal is that developers should be able to land on a folder, where there's a project defined, and interact with it, without having to guess which commands are available and which arguments need to be passed. Pretty much like:

```bash
tuist generate
tuist build
tuist test
tuist run
```

If the arguments can be inferred, they will be inferred. If an input is invalid, we'll fail early instead of delegating that to the build system. Tuist is designed to fail soon and clearly. We want you to know when things go wrong, why so, and what you can do about them.

**Xcode is a great tool, and we'd love you to continue to use it, but without the hassle of having to maintain a project and all the automation around it.**

## 🖌 Design principles

I read that GitHub came up with [some design principles](https://ben.balter.com/2015/08/12/the-zen-of-github/) which they shared across all the teams to make sure that they were all aligned when building features for the platform. I liked the idea and drafted a list for Tuist. This is what I came up with:

- **Convention over configuration:** Build things to be convenient, not configurable. Configurability gives users the power to use the tool as they want, but also to screw things up without you being able to recover from it.

- **Design for failure:** Quoting Murphy: _"If things can go wrong, they will"_. Don't assume the happy path is the only valid path. Any scenario is handled, including errors, letting developers know about it at any time.

- **Make feedback actionable:** If things go wrong try to recover from it. In case you can't, let developers know what to do to get it working. There's a significant difference between `Couldn't find the simulator`, and `Couldn't find the simulator because simctl was not found in the system. Make sure the Xcode installation is configured by running 'xcode-select -p'`

- **Simple is better than complex:** People don't use things if they are too complex. Developers don't want to touch a piece of code that has grown into a huge mess. Keep things simple.

- **Implementation details bring little value to users:** Users don't want to know how you are doing things internally, they want you to do what they asked you for. Don't expose implementation details, like errors that you are thrown internally, because they don't care about that.

- **If it can't be reliable, you'd better not build it:** If a feature doesn't work as expected, users will have a negative perception of the tool. If you plan to build something, which can't be reliable, don't build it. Instead, do some groundwork to make it reliable or find another approach to address the same problem.

It's is a malleable list which will change and grow as the project evolves. You can check out the [full list](https://github.com/tuist/contributors/blob/main/Zen.md) on the [contributors' repository](https://github.com/tuist/contributors)

> We implemented an endpoint, [api.tuist.io/zen](http://api.tuist.io/zen), to return the project design principles.

## 🚀 What's coming

- 📃 **Documentation:** Unfortunately, We haven't devoted much time to have a decent documentation for the project. That makes onboarding hard. We'll work on documenting the public interfaces and the CLI.
- 🚀 **Build, test, run actions:** We'll work on providing a standard interface with the most common actions developers do when they interact with the projects. Once developers learn the interface, they'll be able to jump from one project to another seamlessly.
- 🔀 **Static transitive dependencies:** Although Tuist supports dynamic transitive dependencies, it doesn't support static ones. We want to add support for that, allowing developers to specify whether they'd like to generate their dependencies to be static or dynamic.
- 🔑 **Certificate management:** A common source of frustration when building apps with Xcode is when you try to run the app on a device, or archive it for release, and you get a signing issue. We want to address that by setting up the environment and project with the right certificates, provisioning profiles and build settings.
- 🛒 **Releasing:** Once the app is ready for release, we'd like you to be able to archive and send the app to the store directly from Tuist with a single command that does all the heavy-lifting for you.

You can check out [the project issues](https://github.com/tuist/tuist/issues) that contains some other smaller improvements and features that are also coming to the project.

## 📱 Start using it

Would you like to give Tuist a try? You can check out the [Get started](https://docs.tuist.io/tutorial/get-started/) guide that explains how to install the tool and how to bootstrap your first project.

## 📒 Resources

- [The vision of the project](https://tuist.io/vision/)
- [Design principles](https://github.com/tuist/contributors/blob/main/Zen.md)
- [Contributing](https://github.com/tuist/contributors/blob/main/Contributing.md)

## ❤️ I need you

Tuist strives to build a healthy and supportive community that pushes the project forward. I'll keep pushing it because I'm self-motivated, but I'd love to do it with developers like you.

**We need feedback, ideas, bugs, code, and whatever you can imagine to make Tuist better**. I've built the project to be accessible and inclusive to make sure everyone has a voice and can participate in shaping Tuist. I planted the seed, but this tree 🌲 needs passionate gardeners.

Don't be afraid of getting involved with the project. If you have never done it before, [drop me a line](mailto:pedro@ppinera.es), and I'll be pleased to get you onboard. If you are a developer for Apple platforms, you'll feel like at home working on this project because it's written in plain Swift, a programming language you might already be familiar with.

<br/><br/>

I'm thrilled about this project taking off; nevertheless, there's a possibility of this project not being used a lot since there's already trust in the community for Fastlane, Cocoapods, or the official Swift Package Manager. I'll do my best though, but without worrying too much. Overall, I'd like to learn how to build a user-friendly and reliable command line tool that addresses real problems developers have.

Having said all that, I can't wait to see how you use Tuist and all the ideas that come out of it.

Happy Xcoding! ❤️👩‍💻
