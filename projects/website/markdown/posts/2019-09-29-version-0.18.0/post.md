---
layout: post
title: Welcome Swift Packages to the dependencies family in Tuist 0.18.0
date: 2019-06-21
categories: [tuist, release, swift]
excerpt: Making the definition of dependencies very convenient was one of our aims when we embarked on building Tuist and today, we are extending that convenience to external dependencies that are distributed as Swift Packages. Targets can now define packages as dependencies and Tuist will take care of the rest. Moreover, this version ships with improvements in the API of dynamic Info.plist files.
author: fortmarek
---

Hey everyone 👋

This is my first release and I am really excited to tell you what's new in this new 0.18.0 version of Tuist that brings Xcode 11 and Swift Package Manager support along with other great improvements.

Let's begin and let me show you what's changed!

## New InfoPlist.extendingDefault case 📝

Tuist already supported passing the content of the target's Info.plist to the manifest. However, the whole content needed to be included in the dictionary, providing no benefit to the user compared to having the content in an `Info.plist` file.

So, if you want to leverage the base values that Tuist provides for your `Target` and only extend it with a few optional arguments, now you can!

To use this feature just define your dictionary in `.extendingDefault([:])` as in example:

```swift
Target(name: "App",
       platform: .iOS,
       product: .app,
       bundleId: "io.tuist.App",
       // Defining custom values for `Info.plist`
       infoPlist: .extendingDefault(with: [
           "CFBundleShortVersionString": "3.2.1"
        ]),
       sources: "Sources/**")
```

## Multiline settings ⚙️

We have made a small change in how we handle `Settings` because Xcode could sometimes create unepexcted diff from the version created by `tuist`.

To fix this, defining the `base` parameter has been changed from `[String: String]` to `[String: SettingValue]`, so we can handle the order of arguments leveraging `ExpressibleByStringLiteral` protocol.

The `Settings` should now be declared like this:

```swift
// Explicitly define the type of value for `settings`
let settings: [String: SettingValue] = ["WARNING_CFLAGS": "VALUE"]
let targetSettings = Settings(
  base: settings,
  configurations: [],
  defaultSettings: .recommended
)
```

You can find more info [here](https://github.com/tuist/tuist/pull/464#issuecomment-529673717).

## Swift Package Manager Support 📦

At this year's WWDC, we finally got SPM's support in Xcode, so that's something that we needed to support, too, alongside Carthage and Cocoapods. And finally, you can easily define SPM dependencies easily in your `Project.swift` manifest! We have tried to make a declaration of a package dependency as similar as we could to how they are defined in SPM's manifest `Package.swift`.

SPM provides remote packages (either from git remote repositories like Github or remote repository from your file system) and local which are best suited when you first want to incorporate the package in your project and build it alongside it before possibly finalizing and moving it to a project of its own.

So, below is an example of how you could add a remote and a local package to a `Target` of your choosing:

```swift
Target(name: "App",
       platform: .iOS,
       product: .app,
       bundleId: "io.tuist.App",
       sources: ["Sources/**"],
       dependencies: [
            .package(url: "https://github.com/ReactiveX/RxSwift", productName: "RxSwift", .upToNextMajor(from: "5.0.0")),
            .package(url: "https://github.com/tuist/XcodeProj", productName: "xcodeproj", from: "6.7.0"),
            .package(url: "https://github.com/tuist/shell", productName: "shell", "2.1.2"..<"2.2.0"),
            .package(path: "RelativePath/ToYourPackage", productName: "PackageLibrary"),
       ]),
```

If you are familiar with `Package.swift`, there should be almost no learning curve! Now there are no more obstacles to adding a package to your project 🥳

Also note that this will add `.package.resolved` file to your root directory to enable your team to use the same version for every package without commiting your workspace. `tuist` handles this file for you, so you don't have to worry about it.

## Other improvements ⭐️

### Xcode 11 support 🛠

Now, you can comfortably contribute to Tuist with Xcode 11! This release is the first one that has been built with a new Xcode, so you can finally delete the old one.

### Codesign output 🔑

To have better understanding of what's happening when running codesigning, we now include the output of this command to the command line.

## Bug fixes 🐛

- Transitively link static dependency's dynamic dependencies correctly
- Prevent embedding static frameworks
- Output losing its format when tuist is run through tuistenv
- Product name linting failing when it contains variables
- Build phases not generated in the right position

## Changelog

You can check out the complete changelog [here](https://github.com/tuist/tuist/blob/main/CHANGELOG.md).

### Personal note

I want to thank all the people working on Tuist - working on SPM support has been a great deal of fun thanks to the community that has evolved around the project. So, if there is something that you want to improve in Tuist, definitely consider creating a PR, you won't regret it!

Also do not be afraid to ask for additional guidance in our [Slack channel](https://slack.tuist.io), I am sure someone will help you out.

Anyway, thanks for reading and see you at the next release!
