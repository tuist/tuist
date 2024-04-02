**STRUCT**

# `ConfigurationName`

```swift
public struct ConfigurationName: ExpressibleByStringLiteral, Codable, Equatable
```

A configuration name.

It has build-in support for ``debug`` and ``release`` configurations.

You can extend with your own configurations using a extension:
```
import ProjectDescription
extension ConfigurationName {
  static var beta: ConfigurationName {
      ConfigurationName("Beta")
  }
}
```

## Properties
### `rawValue`

```swift
public var rawValue: String
```

The configuration name.

### `debug`

```swift
public static var debug: ConfigurationName
```

Returns a configuration named "Debug"

### `release`

```swift
public static var release: ConfigurationName
```

Returns a configuration named "Release"

## Methods
### `init(stringLiteral:)`

```swift
public init(stringLiteral value: StringLiteralType)
```

Creates a configuration name with its name.
- Parameter value: Configuration name.

#### Parameters

| Name | Description |
| ---- | ----------- |
| value | Configuration name. |

### `configuration(_:)`

```swift
public static func configuration(_ name: String) -> ConfigurationName
```

Returns a configuration name with its name.
- Parameter name: Configuration name.
- Returns: Initialized configuration name.

#### Parameters

| Name | Description |
| ---- | ----------- |
| name | Configuration name. |