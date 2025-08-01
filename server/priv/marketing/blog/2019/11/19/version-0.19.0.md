---
title: Define your watchOS apps and extensions easily with Tuist 0.19.0
category: "product"
tags: [tuist, release, swift, 0.19.0]
excerpt: Until today, defining watchOS apps and extensions in Tuist was not possible. The good news is that from Tuist 0.19.0 that's no longer true because it extends its beautifully simplified abstractions to watchOS. On top of that, we also shipped support for enabling test coverage in the schemes, and defining the deployment targets in targets. We also took the opportunity to iron out some bugs that had been reported by users.
author: pepicrft
---

Hola Xcoders 👋!

Last week we cut a new version of Tuist, 0.19.0, and this time it's my turn to share what we bundled in that release for you. Let's dive right in.

## Support for watchOS apps

Since this version of Tuist you can [now define your apps for watchOS](https://github.com/tuist/tuist/pull/623/files). As we've done with other Xcode's intricacines, Tuist takes care of setting up the build phases and build settings for you. The snippet below contains an example of a project that has a watch app and its companion extension.

```swift
import ProjectDescription

let project = Project(name: "App",
                      targets: [
                        Target(name: "WatchApp",
                               platform: .watchOS,
                               product: .watch2App,
                               bundleId: "io.tuist.App.watchkitapp",
                               infoPlist: "Support/WatchApp-Info.plist",
                               resources: "WatchApp/**",
                               dependencies: [
                                    .target(name: "WatchAppExtension")
                               ]),
                      Target(name: "WatchAppExtension",
                               platform: .watchOS,
                               product: .watch2Extension,
                               bundleId: "io.tuist.App.watchkitapp.watchkitextension",
                               infoPlist: "Support/WatchAppExtension-Info.plist",
                               sources: ["WatchAppExtension/**"],
                               resources: ["WatchAppExtension/**/*.xcassets"],
                               dependencies: [])
                      ])
```

Although there are some improvements [pending to be implemented](https://github.com/tuist/tuist/issues/628), the feature is ready for users to start using it in their projects.

## Support for sticker extension & app

In the vein of adding support for more product types, this version of Tuist also includes [support for sticker extensions and apps](https://github.com/tuist/tuist/pull/489). You can find [an example here](https://github.com/Rag0n/tuist/blob/201d39e5e37b7cbd634d702e91e76791919efe95/fixtures/ios_app_with_extensions/Project.swift) of an app with a stickers extension and app.

## Support for enabling test coverage in schemes

Before this version of Tuist, it was not possible to enable test coverage in schemes. Thanks to [Abbas](https://github.com/abbasmousavi)'s work, it's now possible and there's an API for that. If you would like to enable it in your custom schemes, you just need to pass the `codeCoverageTargets` attribute when initializing a `TestAction`:

```swift
let test = TestAction.targets(["MyAppTests"], codeCoverageTargets: true)
```

You can check the documentation of the `TestAction` model [here](https://docs.old.tuist.io/usage-projectswift#test-action).

## Defining the deployment target

Thanks to [Daniel](https://github.com/mollyIV)'s contribution, developers will be able to specify the deployment target right in the definition of the target. Tuist will generate the right build settings for the targeted device and minimum runtime version. The snippet below includes an example of an app's target definition that uses the new `deploymentTarget` attribute:

```swift
let target = Target(name: "App",
                    platform: .iOS,
                    product: .app,
                    bundleId: "io.tuist.App",
                    deploymentTarget: .iOS(targetVersion: "13.1", devices: [.iphone, .ipad]),
                    infoPlist: "Info.plist",
                    sources: "Sources/**")
```

## Other improvements

This version of Tuist also includes some minor improvements to some existing features:

- [**Made it fail when there are duplicated dependencies**](https://github.com/tuist/tuist/pull/629): We now detect if there are duplicated dependencies and fail early.
- [**Aligned packages API to SPM's**](https://github.com/tuist/tuist/pull/578): We refined the API for packages to be more alinged to the Swift Package Manager's.
- [**Added support for multiple Tuist directories**](https://github.com/tuist/tuist/pull/630): We added support for having multiple `Tuist` directories, which comes handy for large workspaces.
- [**Fixed false potivies detecting circular dependencies**](https://github.com/tuist/tuist/pull/546): We revisited the logic that detects circular dependencies because it was throwing some false positives.
- [**Fixed issue with dependencies in hosted unit test targets**](https://github.com/tuist/tuist/pull/664): Fixed duplicated symbols issues that showed up as a result of including transitive dependencies unnecessarily.
- [**Added mising LD_RUNPATH_SEARCH_PATHS build setting to targets**](https://github.com/tuist/tuist/pull/661): Test targets were not getting the build setting set and that was causing test runs to fail.

## What's coming

We are working on adding support for [Project description helpers](https://ppinera.es/2019/10/10/manifest-helpers/) that will allow developers to extract reusable pieces of their manifests into a separate framework that their manifest files can import. Moreover, we'll make the API of `ProjectDescription` ABI stable to prevent future Swift versions from breaking Tuist local installations. We also started working on a web service for Tuist users, Galaxy, that will provide Tuist users with insights and caching.

Stay tuned because you have not yet seen everything Tuist has to offer you!
