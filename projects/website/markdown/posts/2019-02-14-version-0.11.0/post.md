---
layout: post
title: Tuist 0.11.0 has been released
date: 2019-02-14
categories: [tuist, release, swift]
excerpt: Tuist 0.11.0 is out and it includes features like "tuist up" that help users configure their environment before working with the projects, or support for generating target schemes. This version also adds support for defining environment variables for targets, as well as some minor improvements and fixes.
author: pepibumur
---

Today I'd like to announce a new version of Tuist, 0.11.0. It's been a while without releasing Tuist versions but we are getting back to speed and getting great contributions from the community _(more on this later)_. Although Tuist 0.11.0 was not baked with major features, it comes with a handful list of improvements and fixes, some of which I'd like to briefly touch on this announcement blog post.

## Setup.swift

In the previous version we introduced a new API for projects to define the tasks that'd need to be executed to configure the local environment for the project. In the effort of making Tuist's core more reusable for external projects _(you can read more about it [here](https://github.com/tuist/tuist/issues/192)_, [Kassem](https://github.com/kwridan) and [Marcin](https://github.com/marciniwanicki) extracted the definition of those tasks into another manifest file, `Setup.swift`. From now this version, the tasks will be defined in that file following the following syntax:

```swift

let setup = Setup([
  .homebrew(packages: ["swiftlint"])
])
```

**We made an exception here and introduced a breaking change in a minor release because this release wasn't a significant milestone for the project to justify a major release.**

## Generation of target schemes

Before this change, Tuist did not generate any schemes for the project targets. The ones listed in the project were generated automatically by Xcode. From this version, Tuist generates an scheme per target. Those schemes are not configurable yet, but is something that we might evaluate and potentially support. You can check out [this](https://github.com/tuist/tuist/issues/199) and [this proposal](https://github.com/tuist/tuist/issues/195) to follow the discussion.

## Target environment variables

Targets support a new attribute, `environment`. When passed, Tuist sets those environment variables in the scheme asociated to the target:

```swift
let target = Target(environment: ["foo": "bar"])
```

## Minor bug fixes

- **Verify bundle identifiers:** Have you tried to use emojis 🥘 in a bundle identifier? You might have probably noticed that Xcode is not happy about it, nor we are. Before Xcode spits out an error we implemented a validation that fails the command if we detect invalid characters in your bundle identifier.
- **Init in non-empty directories:** Before this fix, trying to initialize a project in a directory that already contains other files might have resulted in an error. We've changed that so that the command hesitates to run if there are files in the directory.

## Deprecations

A few versions back, we added support for manifests defined in a JSON and Yaml. Unfortunately, we've decided not to give support for them anymore. Those formats have been marked as deprecated. You can continue using them but we encourage you to use default Swift format before the next version comes out.

## What's coming?

Brace yourself because the next version of Tuist will will be an important milestone for the project:

- **Proper support for static libraries:** If you work on an Xcode project with several frameworks and libraries you might have noticed how painful and cumbersome it is to maintain such a setup. Did you ever tried to move from dynamic to static or the other way around? Not easy right? The good news is that [Oliver](https://github.com/ollieatkinson) felt the pain as well and devised Tuist's support for transitive static dependencies. It'll even allow you to use assets with static libraries. You can follow up the work [here](https://github.com/tuist/tuist/pull/210).
- **Reusable core libraries:** [Kassem](https://github.com/kwridan) and [Marcin](https://github.com/marciniwanicki) would like to leverage and extend the powerful core of Tuist and are currently working on making all the logic for generating projects reusable and flexible. You'll be able to import Tuist's generation library and use it as you want.
- **Build command:** One of the goals that I had in mind when I undertook to build Tuist was providing a set of commands that are common when working on Xcode projects. One of those commands is build. I imagined myself entering a directory with an Xcode project and being able to type `tuist build` with no flags at all. Well, that's becoming real and it'll likely be in the next version of Tuist. Furthermore, I'm building a [xcodebuild parser](https://github.com/tuist/tuist/pull/196) that among others, it'll allow formatting the output from `xcodebuild` like the so popular [xcpretty](https://github.com/xcpretty/xcpretty).

As always, you can easily update the version by just running the following command:

```bash
tuist update
```

Happy xcoding 📝!
