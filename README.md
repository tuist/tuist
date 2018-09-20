<p align="center">
  <img src="https://github.com/tuist/tuist/raw/master/assets/logo.png" width="250" align="center"/>
  <br/><br/>
</p>

[![code style: prettier](https://img.shields.io/badge/code_style-prettier-ff69b4.svg?style=flat-square)](https://github.com/prettier/prettier)
[![CircleCI](https://circleci.com/gh/tuist/tuist.svg?style=svg)](https://circleci.com/gh/tuist/tuist)
[![codecov](https://codecov.io/gh/tuist/tuist/branch/master/graph/badge.svg)](https://codecov.io/gh/tuist/tuist)
[![Slack](http://slack.tuist.io/badge.svg)](http://slack.tuist.io)

## What's Tuist

Tuist is a command line tool that helps you **generate**, **maintain** and **interact** with Xcode projects.

It's open source and written in Swift.

### Defining your projects

With Tuist, projects are defined in a `Project.swift`, also known as manifest. The manifest format abstracts you from the implementation details of Xcode projects. In your manifest you can define which targets your project has, which sources and resources belong to them, as well as the dependencies with targets in the same and other projects. The advantages of defining the projects in a manifest are:

- It can catch **misconfigurations and fail early.** For example, if a target has an invalid dependency, it’ll let you know before you start compiling the app.
- Since the manifest doesn’t include Xcode implementation details, the **likelihood of having git conflicts** is significantly lower.
- **It makes the configuration easier.** The decision on how the project looks is on you. Tuist processes it and manages the complexity for you. One example of that complexity is setting up dependencies between targets.

The example below shows how projects are defined with Tuist:

```swift
import ProjectDescription

let project = Project(name: "App",
                      targets: [
                        Target(name: "App",
                               platform: .iOS,
                               product: .app,
                               bundleId: "io.tuist.App",
                               infoPlist: "Info.plist",
                               sources: "Sources/**",
                               dependencies: [
                                    /* Target dependencies can be defined here */
                                    /* .framework(path: "framework") */
                                ]),
                        Target(name: "AppTests",
                               platform: .iOS,
                               product: .unitTests,
                               bundleId: "io.tuist.AppTests",
                               infoPlist: "Tests.plist",
                               sources: "Tests/**",
                               dependencies: [
                                    .target(name: "App")
                               ])
                      ])
```

Although we encourage defining the manifests in Swift, Tuist also supports JSON and Yaml formats.

### Interacting with your projects

Tuist leverages project generation to provide a **simple and convenient set of commands, standard across all the projects**. The commands infer most of the necessary information from your projects, requiring you to pass only the arguments that are strictly necessary.

Having a standard command line interface makes it easier to jump between projects since there’s an interaction language everyone in the team is familiar with.

<p align="center">
  <img src="https://github.com/tuist/tuist/raw/master/assets/commands.png" width="350" align="center"/>
  <br/><br/>
</p>

- **Init:** Bootstraps a new project. You can specify the platform and the type of project and it’ll generate all the necessary artifacts _(Info.plist, AppDelegate, Project.swift, Playgrounds…)_.
- **Generate:** Generates the Xcode workspace and projects to work on a particular project.
- **Build:** _(Not available yet)_ Builds the project in the current directory. It supports all the arguments that xcodebuild supports.
- **Test:** _(Not available yet)_ Test the project in the current directory. It supports all the arguments that xcodebuild supports.
- **Run:** _(Not available yet)_ Runs the project. If the project needs a device to run on, it’ll prompt you to select one.
- **Release:** _(Not available yet)_ Builds and publishes your project on iTunes Connect.

The list of actions will likely grow as we get feedback from you.

## Install

**Running script:**

```bash
eval "$(curl -sL https://raw.githubusercontent.com/tuist/tuist/master/script/install)"
```

## Bootstrap your first project

```bash
tuist init --platform ios --product application
tuist generate # Generates Xcode project
```

[Check out](https://tuist.io/guides/1-getting-started) the project "Getting Started" guide to learn more about Tuist and all its features.

## Setup for development

1.  Git clone: `git@github.com:tuist/tuist.git`
2.  Generate Xcode project with `swift package generate-xcodeproj`.
3.  Open `tuist.xcodeproj`.
4.  Have fun 🤖

## Roadmap 📚

The roadmap of Tuist is as open as the source code. Check out our public [Trello board](https://trello.com/b/DN6HvDzW/tuist) to know more about what's coming.

## Shield

If your project uses Tuist, you can add the following badge to your project README:

[![Tuist Badge](https://img.shields.io/badge/powered%20by-Tuist-green.svg?longCache=true)](https://github.com/tuist)

```md
[![Tuist Badge](https://img.shields.io/badge/powered%20by-Tuist-green.svg?longCache=true)](https://github.com/tuist)
```

## Donations

Tuist is a non-profit project run entirely by unpaid volunteers. We need your funds to pay for software, hardware and hosting around continuous integration and future improvements to the project. Every donation will be spent on making Tuist better for our users.

Please consider a regular donation through Patreon:

[![Donate with Patreon](https://img.shields.io/badge/patreon-donate-green.svg)](https://www.patreon.com/tuist)

## Open source

Tuist is a proud supporter of the [Software Freedom Conservacy](https://sfconservancy.org/)

<a href="https://sfconservancy.org/supporter/"><img src="https://sfconservancy.org/img/supporter-badge.png" width="194" height="90" alt="Become a Conservancy Supporter!" border="0"/></a>
