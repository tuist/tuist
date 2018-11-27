<img src="assets/tuist.png" width="200" align="center"/>

[![code style: prettier](https://img.shields.io/badge/code_style-prettier-ff69b4.svg?style=flat-square)](https://github.com/prettier/prettier)
[![CircleCI](https://circleci.com/gh/tuist/tuist.svg?style=svg)](https://circleci.com/gh/tuist/tuist)
[![codecov](https://codecov.io/gh/tuist/tuist/branch/master/graph/badge.svg)](https://codecov.io/gh/tuist/tuist)
[![Slack](http://slack.tuist.io/badge.svg)](http://slack.tuist.io)
[![Say Thanks!](https://img.shields.io/badge/Say%20Thanks-!-1EAEDB.svg)](https://saythanks.io/to/pepibumur)
<img src="https://opencollective.com/tuistapp/tiers/backer/badge.svg?label=backer&color=brightgreen" />
<img src="https://opencollective.com/tuistapp/tiers/sponsor/badge.svg?label=sponsor&color=brightgreen" />

## What's Tuist 🕺

Tuist is a command line tool that helps you **generate**, **maintain** and **interact** with Xcode projects.

It's open source and written in Swift.

### Defining your projects 💼

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

### Interacting with your projects 🙇‍♀️

Tuist leverages project generation to provide a **simple and convenient set of commands, standard across all the projects**. The commands infer most of the necessary information from your projects, requiring you to pass only the arguments that are strictly necessary.

Having a standard command line interface makes it easier to jump between projects since there’s an interaction language everyone in the team is familiar with.

- **👩‍💻 Init:** Bootstraps a new project. You can specify the platform and the type of project and it’ll generate all the necessary artifacts _(Info.plist, AppDelegate, Project.swift, Playgrounds…)_.
- **💫 Generate:** Generates the Xcode workspace and projects to work on a particular project.
- **📦 Build:** _(Not available yet)_ Builds the project in the current directory. It supports all the arguments that xcodebuild supports.
- **✅ Test:** _(Not available yet)_ Test the project in the current directory. It supports all the arguments that xcodebuild supports.
- **📱 Run:** _(Not available yet)_ Runs the project. If the project needs a device to run on, it’ll prompt you to select one.
- **🚀 Release:** _(Not available yet)_ Builds and publishes your project on iTunes Connect.

The list of actions will likely grow as we get feedback from you.

## Install ⬇️

**Running script:**

```bash
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/tuist/install/master/install)"
```

## Bootstrap your first project 🌀

```bash
tuist init --platform ios --product application
tuist generate # Generates Xcode project
```

[Check out](https://tuist.io/guides/1-getting-started) the project "Getting Started" guide to learn more about Tuist and all its features.

## Setup for development 👩‍💻

1.  Git clone: `git@github.com:tuist/tuist.git`
2.  Generate Xcode project with `swift package generate-xcodeproj`.
3.  Open `tuist.xcodeproj`.
4.  Have fun 🤖

## Shield

If your project uses Tuist, you can add the following badge to your project README:

[![Tuist Badge](https://img.shields.io/badge/powered%20by-Tuist-green.svg?longCache=true)](https://github.com/tuist)

```md
[![Tuist Badge](https://img.shields.io/badge/powered%20by-Tuist-green.svg?longCache=true)](https://github.com/tuist)
```

## Backers

[Become a backer](https://opencollective.com/tuistapp#backer) and show your support to our open source project.

[![Tuist Backer](https://opencollective.com/tuistapp/backer/0/avatar)](https://opencollective.com/tuistapp/backer/0/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/1/avatar)](https://opencollective.com/tuistapp/backer/1/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/2/avatar)](https://opencollective.com/tuistapp/backer/2/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/3/avatar)](https://opencollective.com/tuistapp/backer/3/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/4/avatar)](https://opencollective.com/tuistapp/backer/4/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/5/avatar)](https://opencollective.com/tuistapp/backer/5/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/6/avatar)](https://opencollective.com/tuistapp/backer/6/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/7/avatar)](https://opencollective.com/tuistapp/backer/7/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/8/avatar)](https://opencollective.com/tuistapp/backer/8/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/9/avatar)](https://opencollective.com/tuistapp/backer/9/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/10/avatar)](https://opencollective.comtuistapps/backer/10/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/11/avatar)](https://opencollective.com/tuistapp/backer/11/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/12/avatar)](https://opencollective.com/tuistapp/backer/12/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/13/avatar)](https://opencollective.com/tuistapp/backer/13/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/14/avatar)](https://opencollective.com/tuistapp/backer/14/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/15/avatar)](https://opencollective.com/tuistapp/backer/15/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/16/avatar)](https://opencollective.com/tuistapp/backer/16/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/17/avatar)](https://opencollective.com/tuistapp/backer/17/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/18/avatar)](https://opencollective.com/tuistapp/backer/18/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/19/avatar)](https://opencollective.com/tuistapp/backer/19/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/20/avatar)](https://opencollective.com/tuistapp/backer/20/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/21/avatar)](https://opencollective.com/tuistapp/backer/21/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/22/avatar)](https://opencollective.com/tuistapp/backer/22/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/23/avatar)](https://opencollective.com/tuistapp/backer/23/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/24/avatar)](https://opencollective.com/tuistapp/backer/24/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/25/avatar)](https://opencollective.com/tuistapp/backer/25/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/26/avatar)](https://opencollective.com/tuistapp/backer/26/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/27/avatar)](https://opencollective.com/tuistapp/backer/27/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/28/avatar)](https://opencollective.com/tuistapp/backer/28/website)
[![Tuist Backer](https://opencollective.com/tuistapp/backer/29/avatar)](https://opencollective.com/tuistapp/backer/29/website)

## Sponsors

Does your company use Tuist?  Ask your manager or marketing team if your company would be interested in supporting our project.  Support will allow the maintainers to dedicate more time for maintenance and new features for everyone.  Also, your company's logo will show [on GitHub](https://github.com/tuist/tuist#readme) and on [our site](https://tuist.io) - who doesn't want a little extra exposure?  [Here's the info](https://opencollective.com/tuistapp)

[![Tuist Backer](https://opencollective.com/tuistapp/sponsor/0/avatar)](https://opencollective.com/tuistapp/sponsor/0/website)
[![Tuist Backer](https://opencollective.com/tuistapp/sponsor/1/avatar)](https://opencollective.com/tuistapp/sponsor/1/website)
[![Tuist Backer](https://opencollective.com/tuistapp/sponsor/2/avatar)](https://opencollective.com/tuistapp/sponsor/2/website)
[![Tuist Backer](https://opencollective.com/tuistapp/sponsor/3/avatar)](https://opencollective.com/tuistapp/sponsor/3/website)
[![Tuist Backer](https://opencollective.com/tuistapp/sponsor/4/avatar)](https://opencollective.com/tuistapp/sponsor/4/website)
[![Tuist Backer](https://opencollective.com/tuistapp/sponsor/5/avatar)](https://opencollective.com/tuistapp/sponsor/5/website)
[![Tuist Backer](https://opencollective.com/tuistapp/sponsor/6/avatar)](https://opencollective.com/tuistapp/sponsor/6/website)
[![Tuist Backer](https://opencollective.com/tuistapp/sponsor/7/avatar)](https://opencollective.com/tuistapp/sponsor/7/website)
[![Tuist Backer](https://opencollective.com/tuistapp/sponsor/8/avatar)](https://opencollective.com/tuistapp/sponsor/8/website)
[![Tuist Backer](https://opencollective.com/tuistapp/sponsor/9/avatar)](https://opencollective.com/tuistapp/sponsor/9/website)
[![Tuist Backer](https://opencollective.com/tuistapp/sponsor/10/avatar)](https://opencollective.comtuistapps/sponsor/10/website)
[![Tuist Backer](https://opencollective.com/tuistapp/sponsor/11/avatar)](https://opencollective.com/tuistapp/sponsor/11/website)
[![Tuist Backer](https://opencollective.com/tuistapp/sponsor/12/avatar)](https://opencollective.com/tuistapp/sponsor/12/website)
[![Tuist Backer](https://opencollective.com/tuistapp/sponsor/13/avatar)](https://opencollective.com/tuistapp/sponsor/13/website)
[![Tuist Backer](https://opencollective.com/tuistapp/sponsor/14/avatar)](https://opencollective.com/tuistapp/sponsor/14/website)
[![Tuist Backer](https://opencollective.com/tuistapp/sponsor/15/avatar)](https://opencollective.com/tuistapp/sponsor/15/website)
[![Tuist Backer](https://opencollective.com/tuistapp/sponsor/16/avatar)](https://opencollective.com/tuistapp/sponsor/16/website)
[![Tuist Backer](https://opencollective.com/tuistapp/sponsor/17/avatar)](https://opencollective.com/tuistapp/sponsor/17/website)
[![Tuist Backer](https://opencollective.com/tuistapp/sponsor/18/avatar)](https://opencollective.com/tuistapp/sponsor/18/website)
[![Tuist Backer](https://opencollective.com/tuistapp/sponsor/19/avatar)](https://opencollective.com/tuistapp/sponsor/19/website)

## Open source

Tuist is a proud supporter of the [Software Freedom Conservacy](https://sfconservancy.org/)

<a href="https://sfconservancy.org/supporter/"><img src="https://sfconservancy.org/img/supporter-badge.png" width="194" height="90" alt="Become a Conservancy Supporter!" border="0"/></a>
