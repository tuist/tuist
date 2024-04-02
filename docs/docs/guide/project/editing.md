---
title: Editing
description: Learn how to use Tuist's edit workflow to declare your project leveraging Xcode's build system and editor capabilities.
---

# Editing

Unlike traditional Xcode projects or Swift Packages,
where changes are done through Xcode's UI,
Tuist-managed projects are defined in Swift code contained in **manifest files**.
If you're familiar with Swift Packages and the `Package.swift` file,
the approach is very similar.

You could edit these files using any text editor,
but we recommend to use Tuist-provided workflow for that,
`tuist edit`.
The workflow creates an Xcode project that contains all manifest files and allows you to edit and compile them.
Thanks to using Xcode,
you get all the benefits of **code completion, syntax highlighting, and error checking**.

## Edit the project

To edit your project, you can run the following command in a Tuist project directory or a sub-directory:

```bash
tuist edit
```

The command creates an Xcode project in a global directory and opens it in Xcode.
The project includes a `Manifests` directory that you can build to ensure all your manifests are valid.

> [!INFO] GLOB-RESOLVED MANIFESTS
> `tuist edit` resolves the manifests to be included by using the glob `**/{Manifest}.swift` from the project's root directory (the one containing the `/Tuist` directory). Make sure the `/Tuist` directory contains a valid `Config.swift`

## Edit and generate workflow

As you might have noticed, the editing can't be done from the generated Xcode project.
That's by design to prevent the generated project from having a dependency on Tuist, 
ensuring you can move from Tuist in the future with little effort.

When iterating on a project, we recommend running `tuist edit` from a terminal session to get an Xcode project to edit the project, and use another terminal session to run `tuist generate`. 