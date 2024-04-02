**STRUCT**

# `EnvironmentVariable`

```swift
public struct EnvironmentVariable: Equatable, Codable, Hashable, ExpressibleByStringLiteral
```

It represents an environment variable that is passed when running a scheme's action

## Properties
### `value`

```swift
public var value: String
```

The value of the environment variable

### `isEnabled`

```swift
public var isEnabled: Bool
```

Whether the variable is enabled or not

## Methods
### `environmentVariable(value:isEnabled:)`

```swift
public static func environmentVariable(value: String, isEnabled: Bool) -> Self
```

### `init(stringLiteral:)`

```swift
public init(stringLiteral value: String)
```

#### Parameters

| Name | Description |
| ---- | ----------- |
| value | The value of the new instance. |