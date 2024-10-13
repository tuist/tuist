---
title: Create a project
description: Learn how to create your first project with Tuist.
---

# Create a project

Once you've installed Tuist, you can create a new project by running the following command:

```bash
mkdir MyApp
cd MyApp
tuist init --name MyApp
```

By default it creates a project that represents an **iOS application.** The project directory will contain a `Project.swift`, which describes the project, a `Tuist/Config.swift`, which contains project-scoped Tuist configuration, and a `MyApp/` directory, which contains the source code of the application.

To work on it in Xcode, you can generate an Xcode project by running:

```bash
tuist generate
```

Note that unlike Xcode projects, which you can open and edit directly, Tuist projects are generated from a manifest file. This means that you should not edit the generated Xcode project directly.

> [!TIP] A CONFLICT-FREE AND USER-FRIENDLY EXPERIENCE
> Xcode projects are prone to conflicts and expose a lot of intricacies to users. Tuist abstracts those away, specially in the area of managing the project's dependency graph.

## Build the app

Tuist provides commands for the most common tasks you'll need to perform on your project. To build the app, run:

```bash
tuist build
```

Under the hood, this command uses the platform's build system (e.g. `xcodebuild`), enriching it with Tuist's features. 

## Test the app

Similarly, you can run tests with:

```bash
tuist test
```

Like the `build` command, `test` uses the platform's test runner (e.g. `xcodebuild test`), but with the added benefits of Tuist's test features and optimizations.

> [!TIP] PASSING ARGUMENTS TO THE UNDERLYING BUILD SYSTEM
> Both `build` and `test` can take extra arguments after `--` which are forwarded to the underlying build system.