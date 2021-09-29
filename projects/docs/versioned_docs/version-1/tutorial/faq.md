---
title: Frequently asked questions
slug: '/tutorial/faq'
description: Frequently Asked Questions
---

### Why should I use Tuist over other project generators?

There are some key differences that make Tuist a better option to scale up projects:

- **Workspaces:** Tuist support defining workspaces made by projects that can have dependencies between them. Those dependencies are defined in a plain language and easy language that Tuist translates into build settings and build phases.
- **Conceptual compression:** Tuist abstract Xcode intricacies to provide an easy interface to define projects. We believe projects should be easy to maintain regardless of their size.
- **Linting:** We know how precious your time is and for that reason Tuist prevents you from having to compile the app until the build system throws an error due to an invalid configuration. To do so we validate your projects and warn you of potential sources of errors.
- **Swift:** Projects are defined using Swift. That allows using Xcode as an editor and benefit from its autocompletion and the documentation. Moreover the definition of projects can be extracted into files that are shared across the project. For instance, you can define a function `func makeFrameworkProject(name: String) -> Project` that acts as a factory of projects.

Moreover, project generation is not Tuist's goal; it's a mean to help developers maintain their projects easily and provide them with a standard set of utilities to make them productive.

### How does Tuist compare to the Swift Package Manager?

Although there are similarities between both tool, the Swift Package Manager (SPM)'s main focus is on dependencies. With Tuist, instead of defining packages that SPM integrates into your projects, you define your projects using concepts with whom you are already familiar: _projects, workspaces, targets, and schemes._ If your project needs to define remote dependencies, Tuist supports defining [CocoaPods](https://cocoapods.org), [Carthage](https://github.com/carthage/carthage), and Swift packages.

### What if the tool is deprecated at some point?

There's nothing to worry about because if that happens you can just add the Xcode projects and workspaces to the git repository and problem solved. One of Tuist's designs principles is staying as close as possible to Xcode and industry standards. Generated projects have no dependency nor reference to Tuist whatsoever.

### Can I generate the manifest files from my Xcode projects?

While we can generate Xcode projects from your manifest files, doing it the other way around is not possible. It's possible to implement such feature in Tuist, but since we wouldn't be able to do it reliably considering how Xcode projects can be, we opted for not doing it. Moreover, going through the process of defining the manifests helps you spot issues in your current projects that otherwise would go unnoticed.

### Should I gitignore my projects?

This is really up to you. If you add the `.xcodeproj` and `.xcworkspace` files to your `.gitignore` file you'll save tons of painful git conflicts. Our recommendation is that you first migrate the project to Tuist, and once everything is up and running, educate the developers in your team on running `tuist generate` when they plan to work on a project. Once they build the habit, you should be able to `.gitignore` those projects with no impact at all.

### What happens when I switch a branch?

When you switch a branch where files have been added or removed, the Xcode project should be re-generated. Unfortunately, it is a manual action. It is recommended to set up a git [post-checkout](https://www.git-scm.com/docs/githooks#_post_checkout) hook. To do so, create a `post-checkout` script in `.git/hooks` folder in your repository:

```bash
#!/bin/sh

tuist generate
```

Remember to set a `post-checkout` script as executable
