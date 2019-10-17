---
layout: post
title: "Announcing Tuist 0.10 and its new 'up' command"
date: 2018-12-03
categories: [tuist, release, swift]
excerpt: Learn more about the newest version of Tuist which comes with a powerful and useful feature, a new 'tuist up' command.
author: pepibumur
---

I'm pleased to tell you more about the new release of Tuist, 0.10.0, which we have just [released](https://github.com/tuist/tuist/releases/tag/0.10.0). If you work with Xcode-based projects, you might have realized that most of them require you to run a few commands in your system to set it up before start working on the project. Those commands usually install project dependencies, tools like [Homebrew](https://brew.sh), [Carthage](https://github.com/carthage/carthage), [Swiftlint](https://github.com/realm/SwiftLint)... The commands are usually documented in the project `README` file, and in some cases, automated into a a sort of bootstrap script.

There are several drawbacks with that so common approach:

- ✅ Those scripts are rarely tested, which means that they can break without you noticing it. It's usually your team next hire the one that stumbles upon the issue and has to fix it.
- 📚If you have several projects, you end up with duplicated bootstrap logic all over the place.
- 📦 Moreover, if you jump between projects, you'll find different conventions on how to configure the environment depending on the project.

If you are already using Tuist or plan to use it, we'll make it easier for you. The new version of Tuist comes with a new command `tuist up` which allows projects define how the environment should be configure in order for the project to work. _Handy, isn't it?_ Let me give you an example.

Let's say that your project depends on swiftlint being available in the system, which can be installed with Homebrew. Traditionally, you'd find something like this in the project `README`:

```md
1. Clone the repository.
2. Install Homebrew if you don't have it installed.
3. Install swiftlint with `brew install swiftlint`.
4. A Bunch of other steps.
```

With Tuist we simplify and standardize the process. All you need to know is that there's a command, `tuist up` that ensures your environment is properly configured to work on the project:

```bash
tuist init
tuist up
tuist generate
```

In order for Tuist to know what needs to be configured in the environment, projects can now specify a list of up commands:

```swift
let project = Project(name: "Downloads",
                      up: [
                        .homebrew(packages: ["swiftlint"]),
                        .custom(name: "My Tool", meet: "./install-mytool.sh", isMet: "test mytool")
                      ])
```

There are some predefined commands, like the homebrew's that you can see in the example above, and you can also define custom ones, where you just need to define how the environment gets configured, and how to verify that the environment is properly configured. Although the list of predefined commands is limited, we plan to add more in the future after we validate the feature and get some ideas from you.

Besides adding up, which is an important milestone for Tuist, this version also comes with some minor improvements:

- The Playgrounds group [is no longer generated](https://github.com/tuist/tuist/pull/177) in the Xcode project when the project has no playgrounds.
- We [added support](https://github.com/tuist/tuist/pull/178) for `.cpp` and `.c` source files.

One of Tuist goals is to make convenient the inconvenient and establish good conventions and practices to let developers focus on building their apps. Up is a remarkable step towards that goal and we can't be more excited to have it out there for you to try it out in your projects. I'd like to give credits to my colleagues at [Shopify](https://shopify.com), who came up with the idea of the `up` command for one of our company-wide internal tools. They are a huge source of inspiration, not only for the `up` command but for how to design and build tools for developers.

As always, don't hesitate to share your thoughts, feedback, critics and anything that comes to your mind.

Until the next release 👋
