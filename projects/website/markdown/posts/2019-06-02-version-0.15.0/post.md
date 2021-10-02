---
layout: post
title: Dynamically generated Info.plist files with Tuist 0.15.0
date: 2019-06-02
categories: [tuist, release, swift]
excerpt: Tuist 0.15.0 extend the beauty of generation to Info.plist. From this version on you'll be able to define the build settings as part of your manfest and let Tuist infer the default values for you. Furthermore, we extended the API to support customizing the generation of default build settings in your projects and targets, added the generation time to the 'tuist generate' command, and added support for defining custom schemes.
author: pepibumur
---

Tuist 0.15.0 has [been been released](https://github.com/tuist/tuist/releases/tag/0.15.0); just in time for WWDC. On this blog post, I'd like to go through the major updates that come with this version.

If you are in San Jose during WWDC and would like to meet to chat about Tuist and Xcode at scale, let us know. Understanding how other projects use Xcode and structure their project is very valuable to improve the tool and abstract you from Xcode intricacies. I'll also be speaking at AltConf on Thursday so come and say hola 👋.

## Default settings ⚙️

[Pull request](https://github.com/tuist/tuist/pull/373)

Tuist used to generate the projects and targets with some default build settings. Although that worked for most of the projects, some projects wanted to have more control over that. The new version of Tuist supports passing a new attribute to the `Settings` model, `defaultSettings`. It can take any of the following values:

- _.recommended:_ Recommended settings including warning flags to help you catch some of the bugs at the early stage of development.
- _.essential:_ A minimal set of settings to make the project compile without any additional settings for example `PRODUCT_NAME` or `TARGETED_DEVICE_FAMILY`.

This change is backwards-compatible by defaulting to `.recommended`. If you want Tuist not to generate any build settings, you can pass `nil` value.

## InfoPlist 📝

[Pull request](https://github.com/tuist/tuist/pull/378)

As you might already know, targets require an _Info.plist_ file to be set. The content of the _Info.plist_ files is almost identical with the exception of some attributes that are specific to the target, like the launch storyboard or the build and version numbers. Although the cost of maintenance of those files is not that high, we believe Tuist can do that work for the developer and take the opportunity to run some validations to prevent future compilation errors.

In that regard, in the new version of Tuist we've turned the `infoPlist` attribute of `Target` from `String` into its own model, `InfoPlist`. Although the change makes no difference for now, we are working on letting the developers pass some ownership of those files to Tuist. In the next version of Tuist developers will be able to define the Info.plist content by using the following values:

```swift
InfoPlist.dictionary(["CFBundleIdentifier", "io.tuist.MyApp"])

// Extends a base list of attributes
InfoPlist.base(extend: ["CFBundleIdentifier", "io.tuist.MyApp"])
```

## Generation time ⌚️

[Pull request](https://github.com/tuist/tuist/pull/335)

With developers introducing Tuist into their workflows, the generation of projects **must be fast.** If you would like to know how much it takes, the new version of Tuist prints the total generation time:

```bash
$ tuist generate

Generating workspace App.xcworkspace
Generating project App
✅ Success: Project generated.
Total time taken: 0.605s
```

## Schemes 📱

[Pull request](https://github.com/tuist/tuist/pull/336)

Until this version, developers were not able to customize the list of generated schemes. That has changed and now schemes are configurable. When schemes are not passed, Tuist generates a default scheme for each target that is part of the project. The example below shows how schemes are initialized and used from a project:

```swift
let scheme = Scheme(
    name: "MyScheme",
    shared: true,
    buildAction: BuildAction(targets: ["App"]),
    testAction: TestAction.targets(["AppTests"]),
    runAction: RunAction(executable: "App")
)

let project = Project(
    name: "App",
    schemes: [scheme]
)
```

## Compiler flags 🚩

[Pull request](https://github.com/tuist/tuist/pull/386)

Although it's not a commonly-used feature in Xcode, Tuist didn't support setting compiler flags to source files. With this new version, you can now pass flags alongside the source files:

```swift
let target = Target(sources: [.init("Sources/**/*.m", compilerFlags: "my flag")])
```

## Minor fixes and improvements 🧪

- We [fixed](https://github.com/tuist/tuist/pull/357) a bug that caused the generation of projects to output Xcode projects with different format.
- Code sign on copy is now [set to true](https://github.com/tuist/tuist/pull/333) by default for the frameworks in the "Embed Frameworks" build phase.
- We [fixed](https://github.com/tuist/tuist/pull/338) a bug that caused files being added as folders.
- We [fixed](https://github.com/tuist/tuist/pull/339) the template that we use to initialize projects so that it doesn't throw warnings.
- We [fixed](https://github.com/tuist/tuist/pull/363) an issue that caused localized resources to be duplicated in the project.
- We [fixed](https://github.com/tuist/tuist/pull/360) the lint check that raised warnings when targets linked static products.
- We [ensured](https://github.com/tuist/tuist/pull/374) that bundle dependencies are properly configured for Xcode to build them beforehand.
- We [added support](https://github.com/tuist/tuist/pull/348) for bundle dependencies that are part of other projects.
- We [added a check](https://github.com/tuist/tuist/pull/356) to make sure that only headers are being added to the generated headers build phase.

## What's next 🤔

At WWDC, Xcode support for Swift Package Manager was announced. We are excited to see Apple taking those steps and we'd like Tuist to embrace the change and integrate with it. We started working on [supporting](https://github.com/tuist/xcodeproj/pull/439) the changes to the Xcode project format with the goal of supporting defining packages as dependencies of your Tuist projects. This is how the integration might look:

```swift
let target = Target(dependencies: [.package("https://github.com/tuist/xcodeproj", .exact("1.2.3"))])
```

Stay tuned!
