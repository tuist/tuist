---
title: Releasing Tuist 3.0
category: "product"
tags: ['Tuist', '3.0', 'Xcode', 'Swift', "Project generation", 'Cloud']
excerpt: Highlighting updates from the 3.0 release and first Tuist Cloud preview.
author: fortmarek
type: release
---

October of last year, we have published the last major version 2.0. Since then we have made great progress, especially with **plugins, Tuist Cloud, and Dependencies.swift**. We have also taken the opportunity to refine our API to be simpler to use - which meant making some breaking changes. We have detailed them all [here](https://github.com/tuist/tuist/releases/tag/3.0.0), along with migration steps and motivation for _why_ we have done them.

Below, I'd like to get deeper into the new features and improvements and briefly touch on the future direction of the project.

## Plugins

[Plugins](https://docs.old.tuist.io/plugins/using-plugins/) allow us to make Tuist an extensible platform. This approach is beneficial to both the users and tuist maintainers. For users, it means they can build **plugins that suit their concrete problem**. The problem might not be general enough for it to be a part of tuist itself or you want to codify your own conventions on top of what tuist offers. Plugins also make tuist easier to maintain because we can provide certain convenience features outside the main repository. The project also becomes leaner and keeps the users in charge of decisions that are outside of tuist's purview.

Plugins have been in tuist for some time now but it is now possible to use **third-party dependencies in plugin [tasks](https://docs.old.tuist.io/plugins/creating-plugins/#tasks)**. This unlocks a lot of possibilities. And when users define a task in their `Config.swift`, it's integrated right inside the tuist CLI. For example, we have created a [new tuist plugin](https://github.com/tuist/tuist-plugin-lint) for linting source code where we have integrated the SwiftLint package to actually do the linting. When you integrate the plugin in your project, you can just run `tuist lint` and it will trigger that plugin 🤯  How _cool_ is that?

But there's more. `tuist lint` also needs to know which files it should lint. For such a use-case, you can now use a completely new framework called [ProjectAutomation](https://docs.old.tuist.io/guides/task/#projectautomation). This framework gives **tasks access to the graph** and a plugin like `tuist lint` can now query the list of sources:

```swift
import ProjectAutomation
let allSources = Tuist.XcodeGraph().projects.values.flatMap(\.targets).map(\.sources)
```

Having an access to the graph is extremely powerful and can be used for _so many_ things - and we can't wait to learn what you will build.

## Dependencies.swift

We have all had our share of pain of using the SPM integration in Xcode. And more importantly, you can only integrate the SPM targets as sources - so when you inevitably clean your project, you need to _rebuild_ all of the dependencies again. That's why a lot of users stick to using Carthage. You always integrate the targets as frameworks, never having to worry about building that code multiple times. Additionally, your Xcode projects is snappier because it only links binaries. The drawback of Carthage has always been that you as a developer have to do a lot of manual setup. And when the time comes and you have to debug your dependency, you need to go back to SPM or Cocoapods.

With [`Dependencies.swift`](https://docs.old.tuist.io/manifests/dependencies/), you declare your dependencies easily inside a dedicated Swift file instead of relying on Xcode UI. Your dependencies are resolved via a simple command `tuist fetch`. And then when you generate your project, tuist prebuilds all the dependencies, so you get a lean Xcode project which you can clean without worrying about ever having to rebuild your dependencies. And if you still want to debug a dependency, simply specify it in your `tuist generate` call.

Now, `Dependencies.swift` has been around for a while but we **declare it now as production-ready**. That does not mean the work stops. We will continue working on bug fixes and improving this feature but we are quite confident that we cover most of the use-cases out there.

## Cloud

Users love caching - for both their own targets and maybe even more so for external ones from `Dependencies.swift`. As projects scale, compiling projects takes noticeably more time than when you started. But when you modularise your projects and integrate most of the targets as binaries, the project will be as joyful to work with as when you started. But wouldn't it be great if you could share what you have built across your team? Or even better, if the CI could build all the targets on each PR? Then you would always have to **build just the part of the codebase you are working on**. This is exactly what remote caching and tuist cloud aims to do - and we believe this will unlock such productivity that you can never achieve with using only what Apple provides (and you might never will).

**Tuist Cloud is now in an alpha version and ready to be used by first testers**. You can follow the steps [here](https://docs.old.tuist.io/cloud/get-started) to get yourself started. We appreciate any feedback - but also keep in mind the feature is still early in development. The feature is currently for free but consider donating [here](https://opencollective.com/tuistapp) to support the development and help us pay the bills for keeping Tuist Cloud up and running.

We have also recently started using Tuist Cloud for tuist itself - which was unlocked by our earlier work of defining tuist with tuist. This will enable us to catch any issues early in the process.

## Looking ahead

With tuist plugins being well-positioned now to cover lots of features that previously would have had to be built in tuist directly (such as the aforementioned `lint` command), we will focus on what makes tuist _special_ - that is generating a project and caching. If a feature can be built without being directly involved in the generation or caching process, it should probably be a plugin.

I expect we might see a lot of opportunities for improvement with Tuist Cloud - some features will be on the website only, some might need additional cooperation with tuist CLI. For example, I think we could provide statistics about build times and how they evolve over time. Since we already have `tuist build` command, it's only a matter of sending the right data to the server. But since Tuist Cloud is still nascent, new features will be decided based on the feedback we receive.

Tuist is in a better position than ever to provide the best developer experience for developing on Apple platforms - and so the future is bright. I can't wait to see what we can build together next.
