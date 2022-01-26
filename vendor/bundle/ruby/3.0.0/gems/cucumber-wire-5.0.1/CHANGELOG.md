# CHANGE LOG

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](http://semver.org).

This document is formatted according to the principles of [Keep A CHANGELOG](http://keepachangelog.com).

Please visit [cucumber/CONTRIBUTING.md](https://github.com/cucumber/cucumber/blob/master/CONTRIBUTING.md) for more info on how to contribute to Cucumber.

---

## [In GIT](https://github.com/cucumber/cucumber-ruby-wire/compare/v5.0.1...main)

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Dependencies

## [5.0.1](https://github.com/cucumber/cucumber-ruby-wire/compare/v5.0.0...v5.0.1)

### Dependencies

- Updated `cucumber-core` ~> 9.0.1

## [5.0.0](https://github.com/cucumber/cucumber-ruby-wire/compare/v4.0.1...v5.0.0)

### Changed

- Update from cucumber-expressions 10 to 12 introduces significant underlying changes
  in how step definitions are matched. This should be backward compatible but there
  is a risk of regressions.

### Dependencies

- Updated dependencies (look at the diff for details)

## [4.0.1](https://github.com/cucumber/cucumber-ruby-wire/compare/v4.0.0...v4.0.1)

### Dependencies

- Updated dependencies (look at the diff for details)

## [4.0.0](https://github.com/cucumber/cucumber-ruby-wire/compare/v3.1.0...v4.0.0)

- Release failed

## [3.1.0](https://github.com/cucumber/cucumber-ruby-wire/compare/v3.0.0...v3.1.0)

### Changed

- Updated gems:
  - `cucumber-core` ~> 7.1.0
  - `cucumber-messages` ~> 12.2.0

## [3.0.0](https://github.com/cucumber/cucumber-ruby-wire/compare/v2.0.1...v3.0.0)

### Changed

- Use `cucumber-ruby-core` 7.0.0

- Updated monorepo libraries:
  - cucumber-cucumber-expressions ~> 10
  - cucumber-messages ~> 12

## [2.0.1](https://github.com/cucumber/cucumber-ruby-wire/compare/v2.0.0...v2.0.1)

### Removed

- Replace use of `MultiJSON` to use native JSON gem

## [2.0.0](https://github.com/cucumber/cucumber-ruby-wire/compare/v1.2.0...v2.0.0)

### Changed

- Use `cucumber-ruby-core` 6.0.0

## [1.2.0](https://github.com/cucumber/cucumber-ruby-wire/compare/v1.1.0...v1.2.0)

### Removed

- Multiline arguments do not need `Location` anymore

### Added

- Use `Cucumber:Messages::IdGenerator::UUID` to provide ids for `Hooks`

## [1.1.0](https://github.com/cucumber/cucumber-ruby-wire/compare/v1.0.0...v1.1.0)

### Changed

- Update to cucumber-expressions 8.0.2
- Update to cucumber 4.0.0

## [1.0.0](https://github.com/cucumber/cucumber-ruby-wire/compare/v0.0.1...v1.0.0)

### Added

- Added this CHANGELOG.md file per [cucumber/cucumber #251](https://github.com/cucumber/cucumber/issues/251) ([#13](https://github.com/cucumber/cucumber-ruby-wire/pull/13) [jaysonesmith](https://github.com/jaysonesmith))

### Changed

- Changes to work with a modern Cucumber-Ruby ([#14](https://github.com/cucumber/cucumber-ruby-wire/pull/14) [brasmusson](https://github.com/brasmusson))
- Adapt to the move of Location to Cucumber::Core::Test ([#14](https://github.com/cucumber/cucumber-ruby-wire/pull/14) [brasmusson](https://github.com/brasmusson))

<!-- Contributors -->

[brasmusson]: https://github.com/brasmusson
[jaysonesmith]: https://github.com/jaysonesmith
[junaruga]: https://github.com/junaruga
[mattwynne]: https://github.com/mattwynne
[olleolleolle]: https://github.com/olleolleolle
