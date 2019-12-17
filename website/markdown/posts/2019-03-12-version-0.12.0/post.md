---
layout: post
title: Tuist 0.12.0 supports defining multiple sources and resources
date: 2019-03-12
categories: [tuist, release, swift]
excerpt: Following users's feedback, we have released a new version of Tuist, 0.12.0 that supports defining multiple sources and resources. Moreover, we added a new product type for those of you that would like to opt for static linking, and added generation of schemes with all the targets that are part of the project. This version also drops support for defining the manifests as a JSON file because Swift will pave our way to a better maintainability and reusability.
author: ollieatkinson
---

I’d first like to introduce myself to all of you reading, since you were probably all expecting Pedro!

I’m [ollieatkinson](https://github.com/ollieatkinson), I am from the United Kingdom and have recently become a core contributor for Tuist. I am very passionate about building great tools. I have also spent 8 years building iOS apps and know how frustrating it can be to manage Xcode projects. Contributing to Tuist was a natural fit for me, because it’s a tool I want myself.

I would also like to welcome [Kas](https://github.com/kwridan) and [Marcin](https://github.com/marciniwanicki) who have also joined the core team. They are doing some fantastic work improving the foundations of the tool. You can checkout some of their work looking at the [closed pull request list](https://github.com/tuist/tuist/pulls?q=is%3Apr+is%3Aclosed)

Tuist is very active at the moment - we have had a fantastic set of contributions.

I’d like to thank [dangthaison91](https://github.com/dangthaison91) for his contribution to allow for an array of resources and sources inside the project manifest and I’d like to say thanks to [steprescott](https://github.com/steprescott) for getting to grips with the tool and making some great first contributions ([Pull Request #269](https://github.com/tuist/tuist/pull/269) & [Pull Request #272](https://github.com/tuist/tuist/pull/272))!

## Getting the update

Updating to the latest version of Tuist is easy, just run update:

```sh
tuist update
```

I’ll review some of the changes which have been released, but for a full list please [head over to the GitHub release page](https://github.com/tuist/tuist/releases/tag/0.12.0).

## [Resources] and [Sources]

It really bugged us that it wasn’t possible to specify multiple different sources for code and resources. One of our use-cases was to store the xibs alongside the source code and the images/fonts inside of a different folder.

We really hope you like our change to support arrays for both `sources` and `resources`.

```swift
Target(name: "App",
       platform: .iOS,
       product: .app,
       bundleId: "io.tuist.App",
       infoPlist: "Info.plist",
       sources: ["Sources/**", "OtherSources/**"],
		 resources: ["Images/*.{pdf,png}", "Fonts/*.ttf"],
       dependencies: [
            .framework(path: "framework")
        ])
```

Don’t worry! We have ensured this change is backwards compatible so you don’t have to change anything if you don’t want to add more locations.

## ⚡️ Static Frameworks

We previously added support for static libraries, but we’ve now taken a step further and added support for static frameworks. Just choose the `.staticFramework` Product type.

```swift
Target(name: "MyAwesomeStaticFramework",
       platform: .iOS,
       product: .staticFramework,
       bundleId: "io.tuist.MyAwesomeStaticFramework",
       infoPlist: "Info.plist",
       sources: ["Sources/**", "OtherSources/**"])
```

Static frameworks are much like static libraries - they become part of the executable, and are statically linked to client apps. They offer a slight advantage as you are able to also bundle your header files inside of the framework.

According to Apple’s WWDC 2016 Session on [Optimizing App Startup Time](https://developer.apple.com/videos/play/wwdc2016/406/) , regardless of their size, having a large number of [dynamically linked libraries](https://developer.apple.com/library/content/documentation/DeveloperTools/Conceptual/DynamicLibraries/100-Articles/OverviewOfDynamicLibraries.html#//apple_ref/doc/uid/TP40001873-SW1) slows down app launch time dramatically.

So if you are building a large scale application and have issues with start up times, then going static is definitely something you should consider.

## Generate a scheme with all the project targets

We will now generate you an extra scheme for each project.

The scheme called xxx-Project _(**xxx**is the name of the project)_ contains all the targets within the project. Moreover, it defines test actions for all the targets that represent test bundles.

This change will make possible supporting the following commands:

```sh
tuist build all
tuist test all
```

N.b. the above does not exist _yet_ but if you’re interested in it, please let us know!

## Removed support for YAML and JSON Projects

We ❤️ Swift, and to ensure we continue to bring you amazing features we thought it was best to remove support for YAML and JSON specifications!

This is so that developers will have a consistent experience and get all the features they expect when writing code: syntax colouring, code completion (see picture), API documentation, and formatting tools.

![auto-complete](https://user-images.githubusercontent.com/1382565/54312754-98771a80-45cf-11e9-8d1e-ce3c909fdc53.png)

## What’s next?

We have a lot of great features being worked on at the moment. I’ll name a few:

- **Configurations** - If you work on an Xcode project with a fairly complex setup then you probably use custom configurations to organise your xcconfig files. This is something we have wanted to support in Tuist for a while. We are coming really close to finalising the feature - I’ve been working with the rest of the core team to come up with a solution, and [Marcin](https://github.com/marciniwanicki) has taken the lead with some really promising prototypes. You can follow the conversation on the pull request: [Pull Request #238](https://github.com/tuist/tuist/pull/238)
- **Workspace Configuration** - If you want to add extra files to your workspace, and you want your workspace to mirror your folder structure on disk then get ready! [It’s coming!](https://github.com/tuist/tuist/pull/262)
- **Improving support for bootstrapping projects with Storyboards** - Storyboards are a great way to get started when building a new project, there’s some great work to enable them by default and out of the box. All you will have to do is `tuist init`. [Checkout the pull request](https://github.com/tuist/tuist/pull/269)
- **Unified Resource Access** - We want support for specifying module resources, and introduces a consistent way of referring to them from the source code in the package. One of the fundamental principles behind Tuist is that modules should be as portable and client-agnostic as possible: in particular, packages should make as few assumptions as possible about the details of how they will be incorporated. For example, a package might in one case be built as a dynamic library or framework that is embedded into an application bundle, and might in another case be statically linked into the client executable. We will be starting to discuss this soon, so watch out on [Github](https://github.com/tuist/tuist/issues) or [head over to Slack](http://slack.tuist.io/).

Happy Xcoding 📝!
