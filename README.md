<p align="center">
  <img src="https://github.com/tuist/tuist/raw/master/assets/logo.png" width="250" align="center"/>
  <br/><br/>
</p>

[![code style: prettier](https://img.shields.io/badge/code_style-prettier-ff69b4.svg?style=flat-square)](https://github.com/prettier/prettier)
[![CircleCI](https://circleci.com/gh/tuist/tuist.svg?style=svg)](https://circleci.com/gh/tuist/tuist)
[![codecov](https://codecov.io/gh/tuist/tuist/branch/master/graph/badge.svg)](https://codecov.io/gh/tuist/tuist)

## Features

- 🥘 100% written in Swift.
- 🐦 Type-safe Swift manifests editable with Xcode.
- ↗️ Local dependencies support.
- ⚠️ Misconfiguration catching.
- 📦 Precompiled binaries _(Frameworks & Libraries support)_.
- 🔄 Circular dependency detection.

## Install

<!--
**Using Homebrew:**

```bash
brew tap tuist/tuist https://github.com/tuist/tuist
brew install tuist
``` -->

**Running script:**

```bash
eval "$(curl -sL https://raw.githubusercontent.com/tuist/tuist/master/script/install)"
```

## Bootstrap your first project

````
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
````

## Donations

Tuist is a non-profit project run entirely by unpaid volunteers. We need your funds to pay for software, hardware and hosting around continuous integration and future improvements to the project. Every donation will be spent on making Tuist better for our users.

Please consider a regular donation through Patreon:

[![Donate with Patreon](https://img.shields.io/badge/patreon-donate-green.svg)](https://www.patreon.com/tuist)

## Open source

Tuist is a proud supporter of the [Software Freedom Conservacy](https://sfconservancy.org/)

<a href="https://sfconservancy.org/supporter/"><img src="https://sfconservancy.org/img/supporter-badge.png" width="194" height="90" alt="Become a Conservancy Supporter!" border="0"/></a>
