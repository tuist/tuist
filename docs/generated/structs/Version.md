**STRUCT**

# `Version`

**Contents**

- [Properties](#properties)
  - `major`
  - `minor`
  - `patch`
  - `prereleaseIdentifiers`
  - `buildMetadataIdentifiers`
- [Methods](#methods)
  - `init(_:_:_:prereleaseIdentifiers:buildMetadataIdentifiers:)`

```swift
public struct Version: Hashable, Codable
```

A struct representing a semver version.
This is taken from SPMUtility and copied here so we do not create a direct dependency for ProjectDescription. Used for
specifying version number requirements inside of Project.swift

## Properties
### `major`

```swift
public var major: Int
```

The major version.

### `minor`

```swift
public var minor: Int
```

The minor version.

### `patch`

```swift
public var patch: Int
```

The patch version.

### `prereleaseIdentifiers`

```swift
public var prereleaseIdentifiers: [String]
```

The pre-release identifier.

### `buildMetadataIdentifiers`

```swift
public var buildMetadataIdentifiers: [String]
```

The build metadata.

## Methods
### `init(_:_:_:prereleaseIdentifiers:buildMetadataIdentifiers:)`

```swift
public init(
    _ major: Int,
    _ minor: Int,
    _ patch: Int,
    prereleaseIdentifiers: [String] = [],
    buildMetadataIdentifiers: [String] = []
)
```

Create a version object.
