---
title: Migrate from .xcodeproj
description: Assess the impact of Tuist and Tuist Cloud in your projects by using it with an existing Swift Package.
next: 
    text: "Directory structure"
    link: /guide/project/directory-structure
---

# Migrate from .xcodeproj

Unless you [create a new project using Tuist](/guide/introduction/adopting-tuist/new-project), in which case you get everything configured automatically, you'll have to define your Xcode projects using Tuist's primitives. **How tedious this process is, depends on how complex your projects are.**

As you probably know, Xcode projects can become messy and complex over time: *groups that don't match the directory structure, files that are shared across targets, or file references that point to nonexisting files (to mention some).* All that accumulated complexity makes it hard for us to provide a command that reliably migrates project.

Moreover, **manual migration is an excellent exercise to clean up and simplify your projects.** Not only the developers in your project will be thankful for that, but Xcode, who will be faster processing and indexing them. Once you have fully adopted Tuist, it will make sure that projects are consistently defined and that they remain simple.

In the aim of easing that work, we are giving you some guidelines based on the feedback that we have received from the users.

> [!TIP] SCALING A MATURE IOS CODEBASE WITH TUIST
> You won't be the first one to migrate a mature iOS codebase to Tuist. You can read how [Asana](https://asana.com/inside-asana/scaling-a-mature-ios-codebase-with-tuist) migrated theirs and the impact that it had on their development workflows, or how [Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-76754fa874f7) evaluated Bazel, Tuist, and SPM and ultimately chose Tuist.

## Extract your build settings into `.xcconfig` files

The leaner the projects, the easier they are to migrate. To make them thinner, you can extract information like build settings that can be defined outside Xcode projects. You must prevent developers from defining settings using build settings.

You can use this snippet for that:

```bash
# Extract target build settings
tuist migration settings-to-xcconfig -p Project.xcodeproj -t MyApp -x MyApp.xcconfig

# Extract project build settings
tuist migration settings-to-xcconfig -p Project.xcodeproj -x MyAppProject.xcconfig
```

After extracting the build settings into .xcconfig files, we recommend adding a check in continuous integration to ensure that build settings are not set to the project:

```bash
tuist migration check-empty-settings -p Project.xcodeproj -t MyApp
```

## Migrate the most independent targets first

Those are usually simpler since they contain fewer dependencies than the rest. That makes them good candidates from which we can start the migration. Use this command to list the targets of a project, sorted by number of dependencies. We recommend starting from the top, with the target that has the lowest number of dependencies.

```bash
tuist migration list-targets -p Project.xcodeproj
```

## Remove broken references


Go through your target sources and resources build phases, and delete references to files that are missing. Although Xcode's build system ignores them, they might complicate the migration.

## Remove files that are not used by any target

There might be files that were once part of the project, but that they are no longer needed. Find and remove them. Otherwise, you might run into compilation issues because your glob patterns (e.g. `**/*.swift`) ended up matching them, and adding them as sources of your targets.

## Prevent modifications of Xcode projects after they've been migrated

After the migration of each project, add a script that fails CI if someone modifies the Xcode project directly, and lets developers know that they should change the manifest files instead.

You can use a tool like [xcdiff](https://github.com/bloomberg/xcdiff) for that.

## Use project description helpers

They allow defining your own abstractions for defining your projects, and most importantly, they allow reusing content across all your manifest files. One of the most common use cases is defining functions that act as factories of templated projects. After migrating all your projects, go through the Project.swift files to identify common patterns and extract them into helpers.

## Tools

Here's a list of community-developed tools that can aid you on the migration process:

- [xcdiff](https://github.com/bloomberg/xcdiff): A tool which helps you diff xcodeproj files.
- [Xcode Build Settings](https://developer.apple.com/documentation/xcode/build-settings-reference): A reference for all the build settings available and their meaning.
