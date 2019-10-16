---
layout: post
title: Tuist 0.16.0
date: 2019-06-21
categories: [tuist, release, swift]
excerpt: This blog post announces Tuist 0.16.0 features, improvements and bug fixes!
author: ollieatkinson
---

Hi, Ollie here 👋🏼! Happy Friday!

I'm happy to announce the release of Tuist 0.16.0; I'm going to talk through the changes we have made this release and some of the upcoming work we have planned to support some of the newer features announced at this year's WWDC.

## Adding support for linking system libraries and frameworks 🏛

Liking against system libraries and frameworks explicitly is sometimes necessary. This is a common use-case when using 3rd-Party frameworks such as Firebase.

We've added support for a new dependency type `sdk`. 

```swift
Target(
    name: "App",
    platform: .iOS,
    product: .app,
    bundleId: "io.tuist.App",
    infoPlist: "Info.plist",
    sources: [ "Sources/**" ],
    dependencies: [
        .sdk(name: "CloudKit.framework", status: .required),
        .sdk(name: "StoreKit.framework", status: .optional),
        .sdk(name: "libc++.tbd"),
    ]
)
```

Thanks to @steprescott and @kwridan 🚀

https://docs.tuist.io/usage-3-dependencies#system-libraries-and-frameworks-dependencies

## Add input & output paths for target action 🎯

If you use tools which need the ability to configure a pre-build or post-build script with input and output files, we now have added support for both. Thanks to @Rag0n for this one.

```swift
.pre(
    path: "my_custom_script.sh", 
    name: "My Custom Script Phase", 
    inputFileListPaths: [ "Data/Cars.raw.json", "Data/Drivers.raw.json" ], 
    outputFileListPaths: [ "Data/Cars.swift", "Data/Drivers.swift" ]
)
```

https://docs.tuist.io/usage-2-manifest#target-action

## Generate Tuist projects with _no_ build settings 🧬

If you have a custom setup and don't want Tuist to provide any default build settings then you are now able to specify `.none` for `settings` on `Project` or `Target`.

```swift
import ProjectDescription

let project = Project(
    name: "MyFramework",
    settings: Settings(
        debug: .init(xcconfig: "Configuration/Debug.xcconfig"), 
        release: .init(xcconfig: "Configuration/Release.xcconfig"), 
        defaultSettings: .none
    ),
    targets: [
        Target(
            name: "MyFramework",
            platform: .iOS,
            product: .framework,
            bundleId: "io.tuist.MyFramework",
            infoPlist: "Sources/Info.plist",
            sources: [ 
                "Sources/**" 
            ],
            dependencies: [
                .framework(path: "../Framework2/prebuilt/Framework2.framework"),
            ]
        ),
    ]
)
```

https://docs.tuist.io/usage-2-manifest#settings

This will ensure tuist does not generate a project with _any_ build settings. Be warned if you do this you will need to ensure you provide some build settings otherwise it might not build inside Xcode.

## Bug Fixes 🐞

We've been really busy squishing bugs and improving the overall stability and experience when using Tuist. We think fixing bugs you find are very important to us and the future of Tuist - so if you find any bugs please [raise an issue](https://github.com/tuist/tuist/issues/new/choose).

### Code sign frameworks on when embedding ✍🏼

Frameworks were not correctly being codesigned when embedded. This caused a bug when trying to build to device "App installation failed. No code signature found". I was able to figure out where the problem was and include it in this release. Thanks to @Rag0n for rasising the issue.

https://github.com/tuist/tuist/pull/398

### Stability for generated projects 🏗

We've been working really hard to stabalise the generated Xcode projects which is really good news if you check them in as you will not see changes you didn't intend to make. It also meant that Xcode could not live-reload the project correctly.

Both @kwridan and @marciniwanicki have introduced fixes into this release! 💪🏼

https://github.com/tuist/tuist/pull/410
https://github.com/tuist/tuist/pull/415
https://github.com/tuist/tuist/pull/408

### Installing custom tuist builds from source 👷🏼‍♂️

`tuist local` was failing to install due to a small bug in the installer still referencing an old compiler flag, luckily I was able to track down the issue and fix it. So if you like living on the edge and using the `master` branch then it's all back up and working 👍🏼

https://github.com/tuist/tuist/pull/402

### And much much more, [checkout the changelog](https://github.com/tuist/tuist/blob/master/CHANGELOG.md) for the full list of additions, fixes and improvements 

## Next up 🕵🏼‍♂️

- We have started work on adding support for SwiftPM (https://github.com/tuist/tuist/pull/394). 
- Tuist will soon be able to control the generation of the Info.plist for your project/manifest (https://github.com/tuist/tuist/pull/380).
- You will soon be able to visualise your dependencies (https://github.com/tuist/tuist/pull/382).
- Join the discussion about how we could support the new `.xcframework` type (https://github.com/tuist/tuist/issues/401)
- We're talking about multi-platform targets (https://github.com/tuist/tuist/issues/397)

Thanks, see you next time!
