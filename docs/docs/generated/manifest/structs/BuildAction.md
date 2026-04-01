**STRUCT**

# `BuildAction`

**Contents**

- [Properties](#properties)
  - `targets`
  - `preActions`
  - `postActions`
  - `runPostActionsOnFailure`
  - `findImplicitDependencies`
- [Methods](#methods)
  - `buildAction(targets:preActions:postActions:runPostActionsOnFailure:findImplicitDependencies:)`

```swift
public struct BuildAction: Equatable, Codable, Sendable
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

### `findImplicitDependencies`

```swift
public var findImplicitDependencies: Bool
```

Whether Xcode should be allowed to find dependencies implicitly. The default is `true`.

## Methods
### `buildAction(targets:preActions:postActions:runPostActionsOnFailure:findImplicitDependencies:)`

```swift
public static func buildAction(
    targets: [TargetReference],
    preActions: [ExecutionAction] = [],
    postActions: [ExecutionAction] = [],
    runPostActionsOnFailure: Bool = false,
    findImplicitDependencies: Bool = true
) -> BuildAction
```

Returns a build action.
- Parameters:
  - targets: A list of targets to build, which are defined in the project.
  - preActions: A list of actions that are executed before starting the build process.
  - postActions: A list of actions that are executed after the build process.
  - runPostActionsOnFailure: Whether the post actions should be run in the case of a failure
  - findImplicitDependencies: Whether Xcode should be allowed to find dependencies implicitly. The default is `true`.
- Returns: Initialized build action.

#### Parameters

| Name | Description |
| ---- | ----------- |
| targets | A list of targets to build, which are defined in the project. |
| preActions | A list of actions that are executed before starting the build process. |
| postActions | A list of actions that are executed after the build process. |
| runPostActionsOnFailure | Whether the post actions should be run in the case of a failure |
| findImplicitDependencies | Whether Xcode should be allowed to find dependencies implicitly. The default is `true`. |