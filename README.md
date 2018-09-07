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

**Using Homebrew:**

```bash
brew tap tuist/tuist https://github.com/tuist/tuist
brew install tuist
```

**Running script:**

```bash
eval "$(curl -sL https://raw.githubusercontent.com/tuist/tuist/master/script/install)"
```

## Setup for development

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

## Open source

Tuist is a proud supporter of the [Software Freedom Conservacy](https://sfconservancy.org/)

<a href="https://sfconservancy.org/supporter/"><img src="https://sfconservancy.org/img/supporter-badge.png" width="194" height="90" alt="Become a Conservancy Supporter!" border="0"/></a>
