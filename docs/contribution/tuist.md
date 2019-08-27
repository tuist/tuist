---
name: Tuist
menu: Contributors
---

import Message from "../components/message"

# Contributing to Tuist

Tuist is a command line interface [(CLI)](https://en.wikipedia.org/wiki/Command-line_interface),
written in [Swift](https://www.apple.com/de/swift/),
that help developers maintain and interact with their Xcode projects.
It also abstracts them from the complexities that Xcode exposes.

If you have experience building apps for Apple platforms,
like iOS,
adding code to Tuist shouldn't be much different.
You already know the most important elements,
[Foundation](https://developer.apple.com/documentation/foundation) and Swift. There are two differences compared to developing apps that are worth mentioning:

- **The interactions with CLIs happen through the terminal.**
  The user executes Tuist,
  which performs the desired task,
  and then returns successfully or with an error code.
  During the execution,
  the user can be notified by sending output information to the standard output and standard error.
  There're no gestures, or graphical interactions,
  just the user intent.
- **There's no runloop** that keeps the process alive waiting for input,
  like it happens in an iOS app when the app receives system or user events.
  CLIs run in its process and finishes when the work is done.
  Asynchronous work can be done using system APIs like `DispatchQueue`,
  but need to make sure the process is running while the asynchronous work is being executed.
  Otherwise,
  the process will terminate the asynchronous work.

If you don't have any experience with Swift,
we recommend [Apple's official book](https://docs.swift.org/swift-book/).
With it you'll also get familiar with the most used elements from the Foundation's API.

## Set up the project locally

To start working on the project, we can follow the steps below:

- Clone the repository by running: `git clone git@github.com:tuist/tuist.git`
- Generate Xcode project with `swift package generate-xcodeproj`.
- Open `tuist.xcodeproj` using Xcode.

<Message info title="Xcode" description="Xcode needs to be installed in your system. If not, you can install it from the macOS App Store. After the installation, open it once to accept some licenses and install some additional components."/>

## Project structure

The project is organized in several targets that are defined in the `Package.swift` manifest file:

- **TuistCore:** Contains support utilities and extensions that are share across the other targets.
- **ProjectManifest:** Contains the models that the developers can use to declare their projects in the `Project.swift` manifest file.
- **TuistGenerator:** It contains all the business logic to read the project definition and generate Xcode projects
- **TuistEnv:** It contains the commands and the logic to manage multiple Tuist versions in the environment.
- **TuistKit:** It contains the commands and Tuist's business logic.
- **tuist:** It's the actual CLI that exposes the commands defined in `TuistKit`.
- **tuistenv:** It's the CLI of `tuistenv`. It exposes the commands defined in `TuistEnvKit`.

<Message info title="Package.swift" description="The Package.swift file declares the structure of our project (a Swift package) and the Swift Package Manager uses it to generate the Xcode project and provide us with a set of commands to interact with it, like 'swift build'"/>
<Message info title="Tests" description="The targets have an associated target that contains the tests. They are named with the same name suffixed with 'Tests'"/>

## Testing

Tuist employs a diverse suite tests that help ensure it works as intended and prevents regressions as it continues to grow and evolve.

### Acceptance Tests

Acceptance tests run the built `tuist` command line against a wide range of [fixtures](/https://github.com/tuist/tuist/tree/master/fixtures) and verify its output and results. They are the slowest to run however provide the most coverage. The idea is to test a few complete scenarios for each major feature.

Those are written in [Cucumber](https://cucumber.io/docs) and Ruby and can be found in [features](/https://github.com/tuist/tuist/tree/master/features). Those are run when calling `bundle exec rake features`.

Example:

[generate.features](https://github.com/tuist/tuist/blob/master/features/generate.feature) has several scenarios that run `tuist generate` on a fixture, verify Xcode projects and workspaces are generated and finally verify the generated project build and test successfully.

### Unit Tests

Most of the internal components Tuist uses have unit tests to thoroughly test them. Here dependencies of components are mocked or stubbed appropriately to ensure tests are reliable, test only one component and are fast!

Those are written in Swift and follow the convention of `<ComponentName>Tests`. Those are run when calling `swift test` or from within Xcode.

**Example:**

[TargetLinterTests](https://github.com/tuist/tuist/blob/master/Tests/TuistGeneratorTests/Linter/TargetLinterTests.swift) verifies all the different scenarios the target linter component can flag issues for.

### Integration Tests

There's a small subset of tests that test several components together as a whole to cover hard to orchestrate scenarios within acceptance tests or unit tests. Those stub some but not all dependencies depending on the test case and are slower than unit tests.

Those are written in Swift and are contained within the `TuistIntegrationTests`. Those are run when calling `swift test` or from within Xcode.

**Example:**

[StableStructureIntegrationTests](https://github.com/tuist/tuist/blob/master/Tests/TuistIntegrationTests/Generator/StableStructureIntegrationTests.swift) dynamically generates projects with several dependencies and files in random orders and verifies the generated project is always the same even after several generation passes.
