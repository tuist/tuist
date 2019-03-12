# Up

Xcode projects often have dependencies with system tools like [SwiftLint](https://github.com/realm/SwiftLint), [Carthage](https://github.com/Carthage/Carthage), or [Sourcery](https://github.com/krzysztofzablocki/Sourcery). Those are dependencies that need to be installed/pulled and properly configured in the developer environment for the project to run.

Most projects include a list of steps in the `README` file for developers to follow:

```markup
1. Clone the repository.
2. Install Carthage if it's not already installed.
3. Install `brew install swiftlint`.
4. Run `carthage update`.
5. Open the project.
```

It’s a tedious process that can break without you noticing it. Moreover, each project usually has its own set of non-standard steps, which makes inconvenient jumping from one project to another.

The good news is that Tuist offers a command, **tuist up** that helps you define your project dependencies and then takes care of the configuration process for you.

To define your project dependencies, we need to create a new `Setup.swift` manifest file:

```swift
import ProjectDescription

let setup = Setup([
    .homebrew(packages: ["swiftlint"]),
    .carthage(platforms: [.iOS])
  ])
```

We have turned the markdown steps that we saw before into up commands in the setup manifest. When you run `tuist up`, Tuist translates those declarations into actual commands that are executed in your system.

Moreover, it assesses whether those dependencies are already met in the environment, and if they are, it skips them. For instance, if the Carthage dependencies exist and are up to date, it doesn’t run the Carthage update command.

```bash
tuist up
```

### Available commands

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

#### Carthage dependencies

```swift
.carthage(platforms: [.macOS])
```

It runs [Carthage](https://github.com/carthage) dependencies for those dependencies that don’t exist or that are outdated.

#### Custom

```swift
.custom(name: “Name”, meet: [”./install.sh”], isMet: [“test, “mytool”])
```

Besides the built-in commands, you can define yours using the custom option. It takes the following arguments:

- **Name:** Name of the command
- **Meet:** Command to run in the system to configure the environment.
- **Met:** Command to run in the system to verify whether the environment is already configure. A 0 exit code means that the environment is already configured.

If you have ideas of other built-in commands that Tuist could offer, don’t hesitate to [open an issue](https://github.com/tuist/tuist/issues/new) with your ideas.
