**STRUCT**

# `RunAction`

```swift
public struct RunAction: Equatable, Codable
```

An action that runs the built products.

It's initialized with the .runAction static method.

## Properties
### `configuration`

```swift
public var configuration: ConfigurationName
```

Indicates the build configuration the product should run with.

### `attachDebugger`

```swift
public var attachDebugger: Bool
```

Whether a debugger should be attached to the run process or not.

### `customLLDBInitFile`

```swift
public var customLLDBInitFile: Path?
```

The path of custom lldbinit file.

### `preActions`

```swift
public var preActions: [ExecutionAction]
```

A list of actions that are executed before starting the run process.

### `postActions`

```swift
public var postActions: [ExecutionAction]
```

A list of actions that are executed after the run process.

### `executable`

```swift
public var executable: TargetReference?
```

The name of the executable or target to run.

### `arguments`

```swift
public var arguments: Arguments?
```

Command line arguments passed on launch and environment variables.

### `options`

```swift
public var options: RunActionOptions
```

List of options to set to the action.

### `diagnosticsOptions`

```swift
public var diagnosticsOptions: SchemeDiagnosticsOptions
```

List of diagnostics options to set to the action.

### `expandVariableFromTarget`

```swift
public var expandVariableFromTarget: TargetReference?
```

A target that will be used to expand the variables defined inside Environment Variables definition (e.g. $SOURCE_ROOT)

### `launchStyle`

```swift
public var launchStyle: LaunchStyle
```

The launch style of the action

## Methods
### `runAction(configuration:attachDebugger:customLLDBInitFile:preActions:postActions:executable:arguments:options:diagnosticsOptions:expandVariableFromTarget:launchStyle:)`

```swift
public static func runAction(
    configuration: ConfigurationName = .debug,
    attachDebugger: Bool = true,
    customLLDBInitFile: Path? = nil,
    preActions: [ExecutionAction] = [],
    postActions: [ExecutionAction] = [],
    executable: TargetReference? = nil,
    arguments: Arguments? = nil,
    options: RunActionOptions = .options(),
    diagnosticsOptions: SchemeDiagnosticsOptions = .options(),
    expandVariableFromTarget: TargetReference? = nil,
    launchStyle: LaunchStyle = .automatically
) -> RunAction
```

Returns a run action.
- Parameters:
  - configuration: Indicates the build configuration the product should run with.
  - attachDebugger: Whether a debugger should be attached to the run process or not.
  - preActions: A list of actions that are executed before starting the run process.
  - postActions: A list of actions that are executed after the run process.
  - executable: The name of the executable or target to run.
  - arguments: Command line arguments passed on launch and environment variables.
  - options: List of options to set to the action.
  - diagnosticsOptions: List of diagnostics options to set to the action.
  - expandVariableFromTarget: A target that will be used to expand the variables defined inside Environment Variables
definition (e.g. $SOURCE_ROOT). When nil, it does not expand any variables.
  - launchStyle: The launch style of the action
- Returns: Run action.

#### Parameters

| Name | Description |
| ---- | ----------- |
| configuration | Indicates the build configuration the product should run with. |
| attachDebugger | Whether a debugger should be attached to the run process or not. |
| preActions | A list of actions that are executed before starting the run process. |
| postActions | A list of actions that are executed after the run process. |
| executable | The name of the executable or target to run. |
| arguments | Command line arguments passed on launch and environment variables. |
| options | List of options to set to the action. |
| diagnosticsOptions | List of diagnostics options to set to the action. |
| expandVariableFromTarget | A target that will be used to expand the variables defined inside Environment Variables definition (e.g. $SOURCE_ROOT). When nil, it does not expand any variables. |
| launchStyle | The launch style of the action |