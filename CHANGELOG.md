# Changelog

Please, check out guidelines: https://keepachangelog.com/en/1.0.0/

## Next version

### Changed

- Rename manifest group to `Manifest` https://github.com/tuist/tuist/pull/227 by @pepibumur.
- Rename manifest target to `Project-Manifest` https://github.com/tuist/tuist/pull/227 by @pepibumur.
- Replace swiftlint with swiftformat https://github.com/tuist/tuist/pull/239 by @pepibumur.
- Bump xcodeproj version to 6.6.0 https://github.com/tuist/tuist/pull/248 by @pepibumur.
- Fix an issue with Xcode not being able to reload the projects when they are open https://github.com/tuist/tuist/pull/247

### Added

- Integration tests for `generate` command https://github.com/tuist/tuist/pull/208 by @marciniwanicki & @kwridan
- Frequently asked questions to the documentation https://github.com/tuist/tuist/pull/223/ by @pepibumur.
- Generate a scheme with all the project targets https://github.com/tuist/tuist/pull/226 by @pepibumur
- Documentation for contributors https://github.com/tuist/tuist/pull/229 by @pepibumur
- Support for Static Frameworks https://github.com/tuist/tuist/pull/194 @ollieatkinson

### Removed

- Up attribute from the `Project` model https://github.com/tuist/tuist/pull/228 by @pepibumur.
- Support for YAML and JSON formats as Project specifications https://github.com/tuist/tuist/pull/230 by @ollieatkinson

### Fixed

- Changed default value of SWIFT_VERSION to 4.2 @ollieatkinson
- Added fixture tests for ios app with static libraries @ollieatkinson
- Bundle id linting failing when the bundle id contains variables https://github.com/tuist/tuist/pull/252 by @pepibumur
- Include linked library and embed in any top level executable bundle https://github.com/tuist/tuist/pull/259 by @ollieatkinson

## 0.11.0

### Added

- **Breaking** Up can now be specified via `Setup.swift` https://github.com/tuist/tuist/issues/203 by @marciniwanicki & @kwridan
- Schemes generation https://github.com/tuist/tuist/pull/188 by @pepibumur.
- Environment variables per target https://github.com/tuist/tuist/pull/189 by @pepibumur.
- Danger warn that reminds contributors to update the docuementation https://github.com/tuist/tuist/pull/214 by @pepibumur
- Rubocop https://github.com/tuist/tuist/pull/216 by @pepibumur.
- Fail init command if the directory is not empty https://github.com/tuist/tuist/pull/218 by @pepibumur.
- Verify that the bundle identifier has only valid characters https://github.com/tuist/tuist/pull/219 by @pepibumur.
- Merge documentation from the documentation repository https://github.com/tuist/tuist/pull/222 by @pepibumur.
- Danger https://github.com/tuist/tuist/pull/186 by @pepibumur.

### Fixed

- Swiftlint style issues https://github.com/tuist/tuist/pull/213 by @pepibumur.
- Use environment tuist instead of the absolute path in the embed frameworks build phase https://github.com/tuist/tuist/pull/185 by @pepibumur.

### Deprecated

- JSON and YAML manifests https://github.com/tuist/tuist/pull/190 by @pepibumur.

## 0.10.2

### Fixed

- Processes not stopping after receiving an interruption signal https://github.com/tuist/tuist/pull/180 by @pepibumur.

## 0.10.1

### Changed

- Replace ReactiveTask with SwiftShell https://github.com/tuist/tuist/pull/179 by @pepibumur.

### Fixed

- Carthage up command not running when the `Cartfile.resolved` file doesn't exist https://github.com/tuist/tuist/pull/179 by @pepibumur.

## 0.10.0

### Fixed

- Don't generate the Playgrounds group if there are no playgrounds https://github.com/tuist/tuist/pull/177 by @pepibumur.

### Added

- Tuist up command https://github.com/tuist/tuist/pull/158 by @pepibumur.
- Support `.cpp` and `.c` source files https://github.com/tuist/tuist/pull/178 by @pepibumur.

## 0.9.0

### Added

- Acceptance tests https://github.com/tuist/tuist/pull/166 by @pepibumur.

### Fixed

- Files and groups sort order https://github.com/tuist/tuist/pull/164 by @pepibumur.

### Added

- Generate both, the `Debug` and `Release` configurations https://github.com/tuist/tuist/pull/165 by @pepibumur.

## 0.8.0

### Added

- Swift 4.2.1 compatibility by @pepibumur.

### Removed

- Module loader https://github.com/tuist/tuist/pull/150/files by @pepibumur.

### Added

- Geration of projects and workspaces in the `~/.tuist/DerivedProjects` directory https://github.com/tuist/tuist/pull/146 by pepibumur.

## 0.7.0

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
