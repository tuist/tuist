**STRUCT**

# `Config.InstallOptions`

**Contents**

- [Properties](#properties)
  - `passthroughSwiftPackageManagerArguments`
- [Methods](#methods)
  - `options(passthroughSwiftPackageManagerArguments:)`

```swift
public struct InstallOptions: Codable, Equatable, Sendable
```

Options for install.

## Properties
### `passthroughSwiftPackageManagerArguments`

```swift
public var passthroughSwiftPackageManagerArguments: [String]
```

Arguments passed to the Swift Package Manager's `swift package` command when running `swift package resolve`.

## Methods
### `options(passthroughSwiftPackageManagerArguments:)`

```swift
public static func options(
    passthroughSwiftPackageManagerArguments: [String] = []
) -> Self
```
