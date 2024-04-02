**ENUM**

# `CompatibleXcodeVersions`

**Contents**

- [Cases](#cases)
  - `all`
  - `exact(_:)`
  - `upToNextMajor(_:)`
  - `upToNextMinor(_:)`
  - `list(_:)`
- [Methods](#methods)
  - `init(arrayLiteral:)`
  - `init(arrayLiteral:)`
  - `init(stringLiteral:)`

```swift
public enum CompatibleXcodeVersions: ExpressibleByArrayLiteral, ExpressibleByStringInterpolation, Codable, Equatable
```

Options of compatibles Xcode versions.

## Cases
### `all`

```swift
case all
```

The project supports all Xcode versions.

### `exact(_:)`

```swift
case exact(Version)
```

The project supports only a specific Xcode version.

### `upToNextMajor(_:)`

```swift
case upToNextMajor(Version)
```

The project supports all Xcode versions from the specified version up to but not including the next major version.

### `upToNextMinor(_:)`

```swift
case upToNextMinor(Version)
```

The project supports all Xcode versions from the specified version up to but not including the next minor version.

### `list(_:)`

```swift
case list([CompatibleXcodeVersions])
```

List of versions that are supported by the project.

## Methods
### `init(arrayLiteral:)`

```swift
public init(arrayLiteral elements: [CompatibleXcodeVersions])
```

### `init(arrayLiteral:)`

```swift
public init(arrayLiteral elements: CompatibleXcodeVersions...)
```

### `init(stringLiteral:)`

```swift
public init(stringLiteral value: String)
```

#### Parameters

| Name | Description |
| ---- | ----------- |
| value | The value of the new instance. |