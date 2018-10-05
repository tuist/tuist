# Changelog

Please, check out guidelines: https://keepachangelog.com/en/1.0.0/

## Next version

### Added

- Support for actions https://github.com/tuist/tuist/pull/136 by @pepibumur.

## 0.6.0

### Added

- Check that the local Swift version is compatible with the version that will be installed https://github.com/tuist/tuist/pull/134 by @pepibumur.

### Changed

- Bump xcodeproj to 6.0.0 https://github.com/tuist/tuist/pull/133 by @pepibumur.

### Removed

- Remove `tuistenv` from the repository https://github.com/tuist/tuist/pull/135 by @pepibumur.

## 0.5.0

### Added

- Support for JSON and Yaml manifests https://github.com/tuist/tuist/pull/110 by @pepibumur.
- Generate `.gitignore` file when running init command https://github.com/tuist/tuist/pull/118 by @pepibumur.
- Git ignore Xcode and macOS files that shouldn't be included on a git repository https://github.com/tuist/tuist/pull/124 by @pepibumur.
- Focus command https://github.com/tuist/tuist/pull/129 by @pepibumur.

### Fixed

- Snake-cased build settings keys https://github.com/tuist/tuist/pull/107 by @pepibumur.

## 0.4.0

### Added

- Throw an error if a library target contains resources https://github.com/tuist/tuist/pull/98 by @pepibumur.
- Playgrounds support https://github.com/tuist/tuist/pull/103 by @pepibumur.
- Faster installation using bundled releases https://github.com/tuist/tuist/pull/104 by @pepibumur.

### Changed

- Don't fail if a Carthage framework doesn't exist. Print a warning instead https://github.com/tuist/tuist/pull/96 by @pepibuymur
- Missing file errors are printed together https://github.com/tuist/tuist/pull/98 by @pepibumur.

## 0.3.0

### Added

- Homebrew formula https://github.com/tuist/tuist/commit/0ab1c6e109134337d4a5e074d77bd305520a935d by @pepibumur.

## Changed

- Replaced ssh links with the https version of them https://github.com/tuist/tuist/pull/91 by @pepibumur.

## Fixed

- `FRAMEWORK_SEARCH_PATHS` build setting not being set for precompiled frameworks dependencies https://github.com/tuist/tuist/pull/87 by @pepibumur.

## 0.2.0

### Added

- Install command https://github.com/tuist/tuist/pull/83 by @pepibumur.
- `--help-env` command to tuistenv by @pepibumur.

### Fixed

- Fix missing target dependencies by @pepibumur.

### Removed

- Internal deprecation warnings by @pepibumur.

## 0.1.0

### Added

- Local command prints all the local versions if no argument is given https://github.com/tuist/tuist/pull/79 by @pepibumur.
- Platform, product, path and name arguments to the init command https://github.com/tuist/tuist/pull/64 by @pepibumur.
- Lint that `Info.plist` and `.entitlements` files are not copied into the target products https://github.com/tuist/tuist/pull/65 by @pepibumur
- Lint that there's only one resources build phase https://github.com/tuist/tuist/pull/65 by @pepibumur.
- Command runner https://github.com/tuist/tuist/pull/81/ by @pepibumur.

### Added

- Sources, resources, headers and coreDataModels property to the `Target` model https://github.com/tuist/tuist/pull/67 by @pepibumur.

### Changed

- `JSON` and `JSONConvertible` replaced with Swift's `Codable` conformance.

### Removed

- The scheme attribute from the `Project` model https://github.com/tuist/tuist/pull/67 by @pepibumur.
- Build phases and build files https://github.com/tuist/tuist/pull/67 by @pepibumur.
