# Changelog

All notable changes to this project will be documented in this file.
## What's Changed in 4.64.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use XcodeGraph for XcodeKit SDK support by [@navtoj](https://github.com/navtoj) in [#8029](https://github.com/tuist/tuist/pull/8029)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.64.1...4.64.2

## What's Changed in 4.64.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* relative path for local package by [@mikhailmulyar](https://github.com/mikhailmulyar) in [#8059](https://github.com/tuist/tuist/pull/8059)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.64.0...4.64.1

## What's Changed in 4.64.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* improve passthrough argument documentation with usage examples by [@pepicrft](https://github.com/pepicrft) in [#8047](https://github.com/tuist/tuist/pull/8047)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.63.3...4.64.0

## What's Changed in 4.63.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* include pagination data when listing the bundles as a json by [@pepicrft](https://github.com/pepicrft) in [#8041](https://github.com/tuist/tuist/pull/8041)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.63.2...4.63.3

## What's Changed in 4.63.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* `bundle show` failing due to wrong data passed by the cli by [@pepicrft](https://github.com/pepicrft) in [#8037](https://github.com/tuist/tuist/pull/8037)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.63.1...4.63.2

## What's Changed in 4.63.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* `tuist run` fails to run a scheme even though it has runnable targets by [@pepicrft](https://github.com/pepicrft) in [#7989](https://github.com/tuist/tuist/pull/7989)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.63.0...4.63.1

## What's Changed in 4.63.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add commands to list and read bundles by [@pepicrft](https://github.com/pepicrft) in [#7893](https://github.com/tuist/tuist/pull/7893)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.62.0...4.63.0

## What's Changed in 4.62.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for buildable folders by [@pepicrft](https://github.com/pepicrft) in [#7984](https://github.com/tuist/tuist/pull/7984)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.61.2...4.62.0

## What's Changed in 4.61.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* platform conditions not applied for binary dependencies in external packages by [@pepicrft](https://github.com/pepicrft) in [#7991](https://github.com/tuist/tuist/pull/7991)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.61.1...4.61.2

## What's Changed in 4.61.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* generation regression by [@pepicrft](https://github.com/pepicrft) in [#8011](https://github.com/tuist/tuist/pull/8011)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.61.0...4.61.1

## What's Changed in 4.61.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for keeping the sources of the targets replaced by binaries by [@pepicrft](https://github.com/pepicrft) in [#8000](https://github.com/tuist/tuist/pull/8000)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.60.0...4.61.0

## What's Changed in 4.60.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* support hashing transitive `.xcconfig` files by [@mikhailmulyar](https://github.com/mikhailmulyar) in [#7961](https://github.com/tuist/tuist/pull/7961)
### 🐛 Bug Fixes

* use Xcode default for which architectures are built by [@fortmarek](https://github.com/fortmarek) in [#8007](https://github.com/tuist/tuist/pull/8007)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.59.2...4.60.0

## What's Changed in 4.59.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* unexpected behaviours when renaming resources in cached targets by [@mikhailmulyar](https://github.com/mikhailmulyar) in [#7988](https://github.com/tuist/tuist/pull/7988)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.59.1...4.59.2

## What's Changed in 4.59.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* prevent metal files from being processed as resources. by [@DenTelezhkin](https://github.com/DenTelezhkin) in [#7976](https://github.com/tuist/tuist/pull/7976)

## New Contributors
* [@DenTelezhkin](https://github.com/DenTelezhkin) made their first contribution in [#7976](https://github.com/tuist/tuist/pull/7976)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.59.0...4.59.1

## What's Changed in 4.59.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* cache binaries by default for arm64 only, add --architectures option to specify architectures by [@fortmarek](https://github.com/fortmarek) in [#7977](https://github.com/tuist/tuist/pull/7977)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.58.1...4.59.0

## What's Changed in 4.58.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* include project settings hash in target hash by [@mikhailmulyar](https://github.com/mikhailmulyar) in [#7962](https://github.com/tuist/tuist/pull/7962)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.58.0...4.58.1

## What's Changed in 4.58.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* print the full sandbox command when a system command fails by [@hiltonc](https://github.com/hiltonc) in [#7972](https://github.com/tuist/tuist/pull/7972)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.57.1...4.58.0

## What's Changed in 4.57.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* treat the new .icon asset as an opaque directory by [@fortmarek](https://github.com/fortmarek) in [#7965](https://github.com/tuist/tuist/pull/7965)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.57.0...4.57.1

## What's Changed in 4.57.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for running macOS app via `tuist run` by [@pepicrft](https://github.com/pepicrft) in [#7956](https://github.com/tuist/tuist/pull/7956)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.56.1...4.57.0

## What's Changed in 4.56.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* auto-generated *-Workspace scheme not getting generated by [@pepicrft](https://github.com/pepicrft) in [#7932](https://github.com/tuist/tuist/pull/7932)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.56.0...4.56.1

## What's Changed in 4.56.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Ignore internal server errors when interating with the cache by [@pepicrft](https://github.com/pepicrft) in [#7924](https://github.com/tuist/tuist/pull/7924)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.55.9...4.56.0

## What's Changed in 4.55.9<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* do not link cached frameworks with linking status .none by [@fortmarek](https://github.com/fortmarek) in [#7918](https://github.com/tuist/tuist/pull/7918)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.55.8...4.55.9

## What's Changed in 4.55.8<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* 'tuist version' shows the optional string by [@pepicrft](https://github.com/pepicrft)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.55.7...4.55.8

## What's Changed in 4.55.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix cli not launching because ProjectAutomation's dynamic framework can't be found by [@pepicrft](https://github.com/pepicrft)
* token refresh race condition by [@pepicrft](https://github.com/pepicrft) in [#7907](https://github.com/tuist/tuist/pull/7907)

## New Contributors
* [@ns-vasilev](https://github.com/ns-vasilev) made their first contribution in [#7660](https://github.com/tuist/tuist/pull/7660)

**Full Changelog**: https://github.com/tuist/tuist/compare/4.55.5...4.55.7

<!-- generated by git-cliff -->
