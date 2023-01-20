---
title: tuist edit
slug: '/commands/edit'
description: 'Learn how to edit your manifest files using Xcode and get documentation, syntax highlighting and auto-completion, and validation by Xcode.'
---

One of the advantages of defining your projects in [Swift](https://swift.org/) is that we can leverage Xcode and the Swift compiler to safely edit the projects with syntax auto-completion and documentation.
Tuist provides a command, `tuist edit`, which generates and opens a temporary Xcode project that includes all the manifest files in the current directory, and the files the manifests depend on _(e.g. [project description helpers](guides/helpers.md))_.

### Command

Editing your projects is easy; position yourself in a directory where there's a project defined and run the following command:

```bash
tuist edit
```

It will open a temporary Xcode project with all the project manifests and the project description helpers, so you will be able to edit the whole project configuration. After making changes you can run the target from Xcode and it will call `tuist generate` for you.

The project is deleted automatically once you are done with editing. If you wish to generate and keep the project in the current directory, you can run the command passing the `--permanent` argument:

```bash
tuist edit --permanent
```

That will generate a `Manifest.xcodeproj` project that you can open manually.

:::note Manifest.xcodeproj and version control
The generated Xcode project has dependencies with the environment in which it runs and thus, we discourage including it in your [version control](https://en.wikipedia.org/wiki/Version_control) project.
:::
