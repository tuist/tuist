# Changelog

Please, check out guidelines: https://keepachangelog.com/en/1.0.0/

## Next

### Added

- New InfoPlist type, `.extendingDefault([:])` https://github.com/tuist/tuist/pull/448 by @pepibumur
- Forward the output of the `codesign` command to make debugging easier when the copy frameworks command fails https://github.com/tuist/tuist/pull/492 by @pepibumur.
- Support for multi-line settings (see [how to migrate](https://github.com/tuist/tuist/pull/464#issuecomment-529673717)) https://github.com/tuist/tuist/pull/464 by @marciniwanicki
- Support for SPM https://github.com/tuist/tuist/pull/394 by @pepibumur & @fortmarek & @kwridan & @ollieatkinson
- Xcode 11 Support by @ollieatkinson

### Fixed

- Transitively link static dependency's dynamic dependencies correctly https://github.com/tuist/tuist/pull/484 by @adamkhazi
- Prevent embedding static frameworks https://github.com/tuist/tuist/pull/490 by @kwridan
- Output losing its format when tuist is run through `tuistenv` https://github.com/tuist/tuist/pull/493 by @pepibumur
- Product name linting failing when it contains variables https://github.com/tuist/tuist/pull/494 by @dcvz
- Build phases not generated in the right position https://github.com/tuist/tuist/pull/506 by @pepibumur
- Remove \$(SRCROOT) from being included in `Info.plist` path https://github.com/tuist/tuist/pull/511 by @dcvz

## 0.17.0

### Added

- `tuist graph` command https://github.com/tuist/tuist/pull/427 by @pepibumur.
- Allow customisation of `productName` in the project Manifest https://github.com/tuist/tuist/pull/435 by @ollieatkinson
- Adding support for static products depending on dynamic frameworks https://github.com/tuist/tuist/pull/439 by @kwridan
- Support for executing Tuist by running `swift project ...` https://github.com/tuist/tuist/pull/447 by @pepibumur.
- New manifest model, `TuistConfig`, to easily configure Tuist's functionalities https://github.com/tuist/tuist/pull/446 by @pepibumur.
- Adding ability to re-generate individual projects https://github.com/tuist/tuist/pull/457 by @kwridan
- Support multiple header paths https://github.com/tuist/tuist/pull/459 by @adamkhazi
- Allow specifying multiple configurations within project manifests https://github.com/tuist/tuist/pull/451 by @kwridan
- Add linting for mismatching build configurations in a workspace https://github.com/tuist/tuist/pull/474 by @kwridan
- Support for CocoaPods dependencies https://github.com/tuist/tuist/pull/465 by @pepibumur
- Support custom .xcodeproj name at the model level https://github.com/tuist/tuist/pull/462 by @adamkhazi
- `TuistConfig.compatibleXcodeVersions` support https://github.com/tuist/tuist/pull/476 by @pepibumur.
- Expose the `.bundle` product type https://github.com/tuist/tuist/pull/479 by @kwridan

### Fixed

- Ensuring transitive SDK dependencies are added correctly https://github.com/tuist/tuist/pull/441 by @adamkhazi
- Ensuring the correct platform SDK dependencies path is set https://github.com/tuist/tuist/pull/419 by @kwridan
- Update manifest target name such that its product has a valid name https://github.com/tuist/tuist/pull/426 by @kwridan
- Do not create `Derived/InfoPlists` folder when no InfoPlist dictionary is specified https://github.com/tuist/tuist/pull/456 by @adamkhazi
- Set the correct lastKnownFileType for localized files https://github.com/tuist/tuist/pull/478 by @kwridan

### Changed

- Update XcodeProj to 7.0.0 https://github.com/tuist/tuist/pull/421 by @pepibumur.

## 0.16.0

### Added

- `DefaultSettings.none` to disable the generation of default build settings https://github.com/tuist/tuist/pull/395 by @pepibumur.
- Version information for tuistenv https://github.com/tuist/tuist/pull/399 by @ollieatkinson
- Add input & output paths for target action https://github.com/tuist/tuist/pull/353 by Rag0n
- Adding support for linking system libraries and frameworks https://github.com/tuist/tuist/pull/353 by @steprescott
- Support passing the `Info.plist` as a dictionary https://github.com/tuist/tuist/pull/380 by @pepibumur.

### Fixed

- Ensuring the correct default settings provider dependency is used https://github.com/tuist/tuist/pull/389 by @kwridan
- Fixing build settings repeated same value https://github.com/tuist/tuist/pull/391 by @platonsi
- Duplicated files in the sources build phase when different glob patterns match the same files https://github.com/tuist/tuist/pull/388 by @pepibumur.
- Support `.d` source files https://github.com/tuist/tuist/pull/396 by @pepibumur.
- Codesign frameworks when copying during the embed phase https://github.com/tuist/tuist/pull/398 by @ollieatkinson
- 'tuist local' failed when trying to install from source https://github.com/tuist/tuist/pull/402 by @ollieatkinson
- Omitting unzip logs during installation https://github.com/tuist/tuist/pull/404 by @kwridan
- Fix "The file couldn’t be saved." error https://github.com/tuist/tuist/pull/408 by @marciniwanicki
- Ensure generated projects are stable https://github.com/tuist/tuist/pull/410 by @kwridan
- Stop generating empty `PBXBuildFile` settings https://github.com/tuist/tuist/pull/415 by @marciniwanicki

## 0.15.0

### Changed

- Introduce the `InfoPlist` file https://github.com/tuist/tuist/pull/373 by @pepibumur.
- Add `defaultSettings` option to `Settings` definition to control default settings generation https://github.com/tuist/tuist/pull/378 by @marciniwanicki

### Added

- Adding generate command timer https://github.com/tuist/tuist/pull/335 by @kwridan
- Support Scheme manifest with pre/post action https://github.com/tuist/tuist/pull/336 by @dangthaison91
- Support local Scheme (not shared) flag https://github.com/tuist/tuist/pull/341 by @dangthaison91
- Support for compiler flags https://github.com/tuist/tuist/pull/386 by @pepibumur.

### Fixed

- Fixing unstable diff (products and embedded frameworks) https://github.com/tuist/tuist/pull/357 by @marciniwanicki
- Set Code Sign On Copy to true for Embed Frameworks https://github.com/tuist/tuist/pull/333 by @dangthaison91
- Fixing files getting mistaken for folders https://github.com/tuist/tuist/pull/338 by @kwridan
- Updating init template to avoid warnings https://github.com/tuist/tuist/pull/339 by @kwridan
- Fixing generation failures due to asset catalog & `**/*.png` glob patterns handling https://github.com/tuist/tuist/pull/346 by @kwridan
- Supporting bundle target dependencies that reside in different projects (in `TuistGenerator`) https://github.com/tuist/tuist/pull/348 by @kwridan
- Fixing header paths including folders and non-header files https://github.com/tuist/tuist/pull/356 by @kwridan
- Fix duplicate localized resource files https://github.com/tuist/tuist/pull/363 by @kwridan
- Update static dependency lint rule https://github.com/tuist/tuist/pull/360 by @kwridan
- Ensure resource bundles in other projects get built https://github.com/tuist/tuist/pull/374 by @kwridan

## 0.14.0

### Changed

### Added

- Adding support for project additional files https://github.com/tuist/tuist/pull/314 by @kwridan
- Adding support for resource folder references https://github.com/tuist/tuist/pull/318 by @kwridan
- **Breaking** Swift 5 support https://github.com/tuist/tuist/pull/317 by @pepibumur.

### Fixed

- Ensuring target product names are consistent with Xcode https://github.com/tuist/tuist/pull/323 by @kwridan
- Ensuring generate works on additional disk volumes https://github.com/tuist/tuist/pull/327 by @kwridan
- Headers build phase should be put on top of Compile build phase https://github.com/tuist/tuist/pull/332 by @dangthaison91

## 0.13.0

### Added

- Add Homebrew tap up https://github.com/tuist/tuist/pull/281 by @pepibumur
- Create a Setup.swift file when running the init command https://github.com/tuist/tuist/pull/283 by @pepibumur
- Update `tuistenv` when running `tuist update` https://github.com/tuist/tuist/pull/288 by @pepibumur.
- Allow linking of static products into dynamic frameworks https://github.com/tuist/tuist/pull/299 by @ollieatkinson
- Workspace improvements https://github.com/tuist/tuist/pull/298 by @ollieatkinson & @kwridan.

### Removed

- **Breaking** Removed "-Project" shared scheme from being generated https://github.com/tuist/tuist/pull/303 by @ollieatkinson

### Fixed

- Fix duplicated embedded frameworks https://github.com/tuist/tuist/pull/280 by @pepibumur
- Fix manifest target linker errors https://github.com/tuist/tuist/pull/287 by @kwridan
- Build settings not being generated properly https://github.com/tuist/tuist/pull/282 by @pepibumur
- Fix `instance method nearly matches optional requirements` warning in generated `AppDelegate.swift` in iOS projects https://github.com/tuist/tuist/pull/291 by @BalestraPatrick
- Fix Header & Framework search paths override project or xcconfig settings https://github.com/tuist/tuist/pull/301 by @ollieatkinson
- Unit tests bundle for an app target compile & run https://github.com/tuist/tuist/pull/300 by @ollieatkinson
- `LIBRARY_SEARCH_PATHS` and `SWIFT_INCLUDE_PATHS` are now set https://github.com/tuist/tuist/pull/308 by @kwridan
- Fix Generation fails in the event an empty .xcworkspace directory exists https://github.com/tuist/tuist/pull/312 by @ollieatkinson

## 0.12.0

### Changed

- Rename manifest group to `Manifest` https://github.com/tuist/tuist/pull/227 by @pepibumur.
- Rename manifest target to `Project-Manifest` https://github.com/tuist/tuist/pull/227 by @pepibumur.
- Replace swiftlint with swiftformat https://github.com/tuist/tuist/pull/239 by @pepibumur.
- Bump xcodeproj version to 6.6.0 https://github.com/tuist/tuist/pull/248 by @pepibumur.
- Fix an issue with Xcode not being able to reload the projects when they are open https://github.com/tuist/tuist/pull/247
- Support array for `sources` and `resources` paths https://github.com/tuist/tuist/pull/201 by @dangthaison91

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
