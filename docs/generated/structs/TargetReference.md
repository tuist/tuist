**STRUCT**

# `TargetReference`

```swift
public struct TargetReference: Hashable, Codable, ExpressibleByStringInterpolation
```

A target reference for a specified project.

The project is specified through the path and should contain the target name.

## Properties
### `projectPath`

```swift
public var projectPath: Path?
```

Path to the target's project directory.

### `targetName`

```swift
public var targetName: String
```

Name of the target.

## Methods
### `init(stringLiteral:)`

```swift
public init(stringLiteral value: String)
```

#### Parameters

| Name | Description |
| ---- | ----------- |
| value | The value of the new instance. |

### `project(path:target:)`

```swift
public static func project(path: Path, target: String) -> TargetReference
```

### `target(_:)`

```swift
public static func target(_ name: String) -> TargetReference
```
