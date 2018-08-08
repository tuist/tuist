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

```
brew tap tuist/tuist git@github.com:tuist/tuist.git
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
