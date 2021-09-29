---
title: Set up environment
slug: '/commands/up'
description: 'Learn how developers in your team can use the up command to set up their environments with the tools that are necessary for the projects to run'
---

### Context

Xcode projects often have dependencies with system tools like [SwiftLint](https://github.com/realm/SwiftLint), [Carthage](https://github.com/Carthage/Carthage), or [Sourcery](https://github.com/krzysztofzablocki/Sourcery). Those are dependencies that need to be installed/pulled and properly configured in the developer environment for the project to run.

Most projects include a list of steps in the `README` file for developers to follow:

```markup
1. Clone the repository.
2. Install Carthage if it's not already installed.
3. Install `brew install swiftlint`.
4. Run `carthage bootstrap`.
5. Open the project.
```

It’s a tedious process that can break without you noticing it. Moreover, each project usually has its own set of non-standard steps, which makes inconvenient jumping from one project to another.

The good news is that Tuist offers a command, **tuist up** that helps you define your project dependencies and then takes care of the configuration process for you.

### Command

To define your project dependencies, we need to create a new `Setup.swift` manifest file:

```swift
import ProjectDescription

let setup = Setup(
    require: [
        .precondition(...)
    ],
    run: [
        .homebrew(packages: []),
        .carthage(platforms: [])
    ]
)
```

First, we pre-flight all the rules in the `require` block, and fail the tuist operation if the requirements are not met.

We then turn the markdown steps that we saw before into up commands in the setup manifest. When you run `tuist up`, Tuist translates those declarations into actual commands that are executed in your system.

Moreover, it assesses whether those dependencies are already met in the environment, and if they are, it skips them. For instance, if the Carthage dependencies exist and are up to date, it doesn’t run the Carthage bootstrap command.

```bash
tuist up
```

### Available require commands

#### Environment Exists

```swift
.variableExists(
    name: "See if the environment contains this variable.",
    variable: "GITHUB_TOKEN"
)
```

This checks for the existence of the variable, and throws an exception if it is not present.

- **Name:** Name of the command
- **Variable:** A string containing the name of an environment variable.

#### Environment Variable Equals

```swift
.variableHasValue(
    name: "See if the variable is equal to the desired value.",
    variable: "USER",
    value: "elvis"
)
```

This runs the command(s) listed in `isMet`, and throws an exception containing the `advice` if the precondition is not met.

- **Name:** Name of the command
- **Advice:** A string describing recommended actions to take if the precondition is not met.
- **Met:** Command to run in the system to verify whether the precondition is met. A non-0 exit code will fail the `tuist up` command.

#### Precondition

```swift
.precondition(
    name: "GITHUB_TOKEN",
    advice: "“GITHUB_TOKEN” environment variable must be set.",
    isMet: ["scripts/validations/github_token.py"]
)
```

This runs the command(s) listed in `isMet`, and throws an exception containing the `advice` if the precondition is not met.

- **Name:** Name of the command
- **Advice:** A string describing recommended actions to take if the precondition is not met.
- **Met:** Command to run in the system to verify whether the precondition is met. A non-0 exit code will fail the `tuist up` command.

### Available run commands

Tuist offers the following set of commands.

#### Homebrew packages

```swift
.homebrew(packages: [“swiftlint”])
```

It installs the given [Homebrew](https://brew.sh) packages if they don’t exist in the system.

#### Homebrew tap

```swift
.homebrewTap(repositories: ["peripheryapp/periphery"])
```

Configures Homebrew tap repositories. It also installs Homebrew if it's not available in the system.

#### Homebrew cask

```swift
.homebrewCask(projects: ["periphery"])
```

Installs Homebrew cask projects. It also installs Homebrew if it's not available in the system.

#### Carthage dependencies

```swift
.carthage(platforms: [.macOS], useXCFrameworks: true, noUseBinaries: false)
```

It runs [Carthage](https://github.com/carthage) dependencies for those dependencies that don’t exist or that are outdated.

- **Platforms:** The platforms Carthage dependencies should be updated for. If the argument is not passed, the frameworks will be updated for all the platforms.
- **UseXCFrameworks:** Indicates whether Carthage produces XCFrameworks or regular frameworks. The default value is `false`.
- **NoUseBinaries** Indicates whether Carthage rebuilds the dependency from source instead of using downloaded binaries when possible. The default value is `false`.

#### Mint packages

```swift
.mint()
```

It installs all the packages in a [Mintfile](https://github.com/yonaskolb/Mint) if they don’t exist in the system.

#### Rome

```swift
.rome(platforms: [.iOS], cachePrefix: "Swift_5_1")
```

It installs all the dependencies in a [Romefile](https://github.com/tmspzz/Rome) if they don’t exist in the local Carthage folder.

- **Platforms:** Platforms to run against
- **CachePrefix:** The CachePrefix

#### Custom

```swift
.custom(name: "Name", meet: ["./install.sh"], isMet: ["test", "mytool"])
```

Besides the built-in commands, you can define yours using the custom option. It takes the following arguments:

- **Name:** Name of the command
- **Meet:** Command to run in the system to configure the environment.
- **Met:** Command to run in the system to verify whether the environment is already configured. A 0 exit code means that the environment is already configured.

:::tip Contribute new commands
If you have ideas of other built-in commands that Tuist could offer, don’t hesitate to [open an issue](https://github.com/tuist/tuist/issues/new) with your ideas.
:::
