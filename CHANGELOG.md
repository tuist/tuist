# Changelog

Please, check out guidelines: https://keepachangelog.com/en/1.0.0/

## Next version

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
