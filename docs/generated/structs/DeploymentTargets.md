**STRUCT**

# `DeploymentTargets`

**Contents**

- [Properties](#properties)
  - `iOS`
  - `macOS`
  - `watchOS`
  - `tvOS`
  - `visionOS`
- [Methods](#methods)
  - `multiplatform(iOS:macOS:watchOS:tvOS:visionOS:)`
  - `iOS(_:)`
  - `macOS(_:)`
  - `watchOS(_:)`
  - `tvOS(_:)`
  - `visionOS(_:)`

```swift
public struct DeploymentTargets: Hashable, Codable
```

A struct representing the minimum deployment versions for each platform.

## Properties
### `iOS`

```swift
public var iOS: String?
```

Minimum deployment version for iOS

### `macOS`

```swift
public var macOS: String?
```

Minimum deployment version for macOS

### `watchOS`

```swift
public var watchOS: String?
```

Minimum deployment version for watchOS

### `tvOS`

```swift
public var tvOS: String?
```

Minimum deployment version for tvOS

### `visionOS`

```swift
public var visionOS: String?
```

Minimum deployment version for visionOS

## Methods
### `multiplatform(iOS:macOS:watchOS:tvOS:visionOS:)`

```swift
public static func multiplatform(
    iOS: String? = nil,
    macOS: String? = nil,
    watchOS: String? = nil,
    tvOS: String? = nil,
    visionOS: String? = nil
) -> Self
```

Multiplatform deployment target

### `iOS(_:)`

```swift
public static func iOS(_ version: String) -> DeploymentTargets
```

Convenience method for `iOS` only minimum version

### `macOS(_:)`

```swift
public static func macOS(_ version: String) -> DeploymentTargets
```

Convenience method for `macOS` only minimum version

### `watchOS(_:)`

```swift
public static func watchOS(_ version: String) -> DeploymentTargets
```

Convenience method for `watchOS` only minimum version

### `tvOS(_:)`

```swift
public static func tvOS(_ version: String) -> DeploymentTargets
```

Convenience method for `tvOS` only minimum version

### `visionOS(_:)`

```swift
public static func visionOS(_ version: String) -> DeploymentTargets
```

Convenience method for `visionOS` only minimum version
