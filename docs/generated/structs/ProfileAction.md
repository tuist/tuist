**STRUCT**

# `ProfileAction`

```swift
public struct ProfileAction: Equatable, Codable
```

An action that profiles the built products.

It's initialized with the `.profileAction` static method

## Properties
### `configuration`

```swift
public var configuration: ConfigurationName
```

Indicates the build configuration the product should be profiled with.

### `preActions`

```swift
public var preActions: [ExecutionAction]
```

A list of actions that are executed before starting the profile process.

### `postActions`

```swift
public var postActions: [ExecutionAction]
```

A list of actions that are executed after the profile process.

### `executable`

```swift
public var executable: TargetReference?
```

The name of the executable or target to profile.

### `arguments`

```swift
public var arguments: Arguments?
```

Command line arguments passed on launch and environment variables.

## Methods
### `profileAction(configuration:preActions:postActions:executable:arguments:)`

```swift
public static func profileAction(
    configuration: ConfigurationName = .release,
    preActions: [ExecutionAction] = [],
    postActions: [ExecutionAction] = [],
    executable: TargetReference? = nil,
    arguments: Arguments? = nil
) -> ProfileAction
```

Returns a profile action.
- Parameters:
  - configuration: Indicates the build configuration the product should be profiled with.
  - preActions: A list of actions that are executed before starting the profile process.
  - postActions: A list of actions that are executed after the profile process.
  - executable: The name of the executable or target to profile.
  - arguments: Command line arguments passed on launch and environment variables.
- Returns: Initialized profile action.

#### Parameters

| Name | Description |
| ---- | ----------- |
| configuration | Indicates the build configuration the product should be profiled with. |
| preActions | A list of actions that are executed before starting the profile process. |
| postActions | A list of actions that are executed after the profile process. |
| executable | The name of the executable or target to profile. |
| arguments | Command line arguments passed on launch and environment variables. |