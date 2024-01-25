# Command line interface (CLI)

This page contains an overview of the command line interface (CLI) of Tuist.

## Overview

`tuist` is the command line interface (CLI) that you use to interact with Tuist. It's a binary that you can install (<doc:installation>) in your system and use to generate, build, test, and more your Xcode projects. In the following sections, you'll learn about the different commands that you can use to interact with Tuist.
If you want to learn more about the commands, you can run `tuist help` to get a list of all the available commands and `tuist help <command>` to get more information about a specific command.

### Init

`tuist init` is the command that you use to initialise a new project from a template.

### Generate

`tuist generate` is the command that you use to generate an Xcode workspace from a project manifest. It's the most common command that you'll use when working with Tuist.

### Edit

`tuist edit` is the command that you use to edit manifests using Xcode. It generates an Xcode project with the manifest files and opens it in Xcode. The lifecycle of the Xcode project is tied to the lifecycle of the command execution. Once the command is aborted, the Xcode project is deleted. When you're done editing the manifest, you can run `tuist generate` to generate the Xcode project.

**We recommend editing the manifest files using Xcode** because it provides a better experience than editing them using a text editor. For instance, Xcode provides syntax highlighting, code completion, and more.


### Fetch

`tuist fetch` is the command that you use to fetch the Package dependencies (<doc:dependencies>) in the `Package.swift` file. It resolves the dependencies using the Swift Package Manager and generates the `Package.resolved` file. When your Xcode projects are generated, Tuist generates Xcode projects for the dependencies and links them to the Xcode projects of your project.

### Build

`tuist build` is the command that you use to build your project. It generates the Xcode project and builds it using the `xcodebuild` command line tool. It builds all the buildable targets in the project or the schemes that you pass as arguments to the command.

> Tip: Although you can generate the project and build it with `xcodebuild` or any automation tool that wraps it, we recommend using `tuist build` because it can leverage the graph information to build the project faster (<doc:binary-caching>).

### Test

`tuist test` is the command that you use to test your project. It generates the Xcode project and tests it using the `xcodebuild` command line tool. It tests all the testable targets in the project or the schemes that you pass as arguments to the command.

> Tip: `tuist test` leverages the graph information to speed up the test execution by skipping compilation steps (<doc:binary-caching>) and selectively running the tests impacted by the changes.

### Run

`tuist run` is the command that you use to run your project. It generates the Xcode project and runs it using the `xcodebuild` command line tool. It runs the runnable scheme passed as an argument to the command.

> Important: Only iOS apps are currently supported. We plan to support other product types and platforms.

### Cache

`tuist cache` contains a set of commands that you can use to interact with the cache. The most common command is `tuist cache warm` which warms up the cache with binary artifacts that Tuist uses to generate more optimized Xcode projects and provide faster builds and tests (<doc:binary-caching>).

### Dump

`tuist dump` outputs a manifest as a JSON. It's useful when you want to inspect through a serialised representation of the manifest.

### Scaffold

`tuist scaffold` is the command that you use to scaffold new files in your project from templates (<doc:extensions>). It's useful when you want to add new files to your project and you don't want to do it manually. 

### Migration

`tuist migration` contains a set of commands that you can use to migrate your Xcode project (<doc:migration-guidelines>) to a Tuist. For example, you can use `tuist migration settings-to-xcconfig` to extract build settings into `.xcconfig` files or `tuist migration check-empty-settings` to check a target or project for empty build settings.

### Graph

`tuist graph` is the command that you use to visualise the dependency graph of your project. You can output it in different formats such as `.dot`, `.png`, or `.svg` and use it to understand the dependencies between the targets in your project. 

### Clean

`tuist clean` contains a set of commands that you can use to clean artifacts stored globally in your system. For example, `tuist clean manifests` cleans the cache that Tuist users to speed up the compilation of the manifest files.

### Signing

`tuist signing` contains a set of commands that allows you to keep certificates and provisioning profiles encrypted in your repository (<doc:signing>). Tuist can decrypt them, install certificates in the Keychain, and configure the generated Xcode projects accordingly.

### Cloud

`tuist cloud` contains a set of commands that you can use to interact with the Tuist Cloud service (<doc:tuist-cloud>). You can authenticate and manage organizations and projects.

### Plugin

`tuist plugin` contains a set of commands to build, run, test, and archive plugins, which are Swift packages that extend Tuist's functionality (<doc:extensions>).