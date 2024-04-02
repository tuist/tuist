**STRUCT**

# `ExecutionAction`

```swift
public struct ExecutionAction: Equatable, Codable
```

An action that can be executed as part of another action for pre or post execution.

## Properties
### `title`

```swift
public var title: String
```

### `scriptText`

```swift
public var scriptText: String
```

### `target`

```swift
public var target: TargetReference?
```

### `shellPath`

```swift
public var shellPath: String?
```

The path to the shell which shall execute this script. if it is nil, Xcode will use default value.

## Methods
### `executionAction(title:scriptText:target:shellPath:)`

```swift
public static func executionAction(
    title: String = "Run Script",
    scriptText: String,
    target: TargetReference? = nil,
    shellPath: String? = nil
) -> Self
```
