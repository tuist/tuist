**STRUCT**

# `LaunchArgument`

```swift
public struct LaunchArgument: Equatable, Codable
```

A launch argument, passed when running a scheme.

## Properties
### `name`

```swift
public var name: String
```

Name of argument

### `isEnabled`

```swift
public var isEnabled: Bool
```

If enabled then argument is marked as active

## Methods
### `launchArgument(name:isEnabled:)`

```swift
public static func launchArgument(name: String, isEnabled: Bool) -> Self
```

Create new launch argument
- Parameters:
    - name: Name of argument
    - isEnabled: If enabled then argument is marked as active

#### Parameters

| Name | Description |
| ---- | ----------- |
| name | Name of argument |
| isEnabled | If enabled then argument is marked as active |