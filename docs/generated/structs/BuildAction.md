**STRUCT**

# `BuildAction`

**Contents**

- [Properties](#properties)
  - `targets`
  - `preActions`
  - `postActions`
  - `runPostActionsOnFailure`
- [Methods](#methods)
  - `buildAction(targets:preActions:postActions:runPostActionsOnFailure:)`

```swift
public struct BuildAction: Equatable, Codable
```

An action that builds products.

It's initialized with the `.buildAction` static method.

## Properties
### `targets`

```swift
public var targets: [TargetReference]
```

A list of targets to build, which are defined in the project.

### `preActions`

```swift
public var preActions: [ExecutionAction]
```

A list of actions that are executed before starting the build process.

### `postActions`

```swift
public var postActions: [ExecutionAction]
```

A list of actions that are executed after the build process.

### `runPostActionsOnFailure`

```swift
public var runPostActionsOnFailure: Bool
```

Whether the post actions should be run in the case of a failure

## Methods
### `buildAction(targets:preActions:postActions:runPostActionsOnFailure:)`

```swift
public static func buildAction(
    targets: [TargetReference],
    preActions: [ExecutionAction] = [],
    postActions: [ExecutionAction] = [],
    runPostActionsOnFailure: Bool = false
) -> BuildAction
```

Returns a build action.
- Parameters:
  - targets: A list of targets to build, which are defined in the project.
  - preActions: A list of actions that are executed before starting the build process.
  - postActions: A list of actions that are executed after the build process.
  - runPostActionsOnFailure: Whether the post actions should be run in the case of a failure
- Returns: Initialized build action.

#### Parameters

| Name | Description |
| ---- | ----------- |
| targets | A list of targets to build, which are defined in the project. |
| preActions | A list of actions that are executed before starting the build process. |
| postActions | A list of actions that are executed after the build process. |
| runPostActionsOnFailure | Whether the post actions should be run in the case of a failure |