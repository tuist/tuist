**STRUCT**

# `TestAction`

```swift
public struct TestAction: Equatable, Codable
```

An action that tests the built products.

You can create a test action with either a set of test targets or test plans using the `.targets` or `.testPlans` static
methods respectively.

## Properties
### `testPlans`

```swift
public var testPlans: [Path]?
```

List of test plans. The first in the list will be the default plan.

### `targets`

```swift
public var targets: [TestableTarget]
```

A list of testable targets, that are targets which are defined in the project with testable information.

### `arguments`

```swift
public var arguments: Arguments?
```

Command line arguments passed on launch and environment variables.

### `configuration`

```swift
public var configuration: ConfigurationName
```

Build configuration to run the test with.

### `attachDebugger`

```swift
public var attachDebugger: Bool
```

Whether a debugger should be attached to the test process or not.

### `expandVariableFromTarget`

```swift
public var expandVariableFromTarget: TargetReference?
```

A target that will be used to expand the variables defined inside Environment Variables definition (e.g. $SOURCE_ROOT)

### `preActions`

```swift
public var preActions: [ExecutionAction]
```

A list of actions that are executed before starting the tests-run process.

### `postActions`

```swift
public var postActions: [ExecutionAction]
```

A list of actions that are executed after the tests-run process.

### `options`

```swift
public var options: TestActionOptions
```

List of options to set to the action.

### `diagnosticsOptions`

```swift
public var diagnosticsOptions: SchemeDiagnosticsOptions
```

List of diagnostics options to set to the action.

### `skippedTests`

```swift
public var skippedTests: [String]?
```

List of testIdentifiers to skip to the test

## Methods
### `targets(_:arguments:configuration:attachDebugger:expandVariableFromTarget:preActions:postActions:options:diagnosticsOptions:skippedTests:)`

```swift
public static func targets(
    _ targets: [TestableTarget],
    arguments: Arguments? = nil,
    configuration: ConfigurationName = .debug,
    attachDebugger: Bool = true,
    expandVariableFromTarget: TargetReference? = nil,
    preActions: [ExecutionAction] = [],
    postActions: [ExecutionAction] = [],
    options: TestActionOptions = .options(),
    diagnosticsOptions: SchemeDiagnosticsOptions = .options(),
    skippedTests: [String] = []
) -> Self
```

Returns a test action from a list of targets to be tested.
- Parameters:
  - targets: List of targets to be tested.
  - arguments: Arguments passed when running the tests.
  - configuration: Configuration to be used.
  - attachDebugger: A boolean controlling whether a debugger is attached to the process running the tests.
  - expandVariableFromTarget: A target that will be used to expand the variables defined inside Environment Variables
definition. When nil, it does not expand any variables.
  - preActions: Actions to execute before running the tests.
  - postActions: Actions to execute after running the tests.
  - options: Test options.
  - diagnosticsOptions: Diagnostics options.
- Returns: An initialized test action.

#### Parameters

| Name | Description |
| ---- | ----------- |
| targets | List of targets to be tested. |
| arguments | Arguments passed when running the tests. |
| configuration | Configuration to be used. |
| attachDebugger | A boolean controlling whether a debugger is attached to the process running the tests. |
| expandVariableFromTarget | A target that will be used to expand the variables defined inside Environment Variables definition. When nil, it does not expand any variables. |
| preActions | Actions to execute before running the tests. |
| postActions | Actions to execute after running the tests. |
| options | Test options. |
| diagnosticsOptions | Diagnostics options. |

### `testPlans(_:configuration:attachDebugger:preActions:postActions:)`

```swift
public static func testPlans(
    _ testPlans: [Path],
    configuration: ConfigurationName = .debug,
    attachDebugger: Bool = true,
    preActions: [ExecutionAction] = [],
    postActions: [ExecutionAction] = []
) -> Self
```

Returns a test action from a list of test plans.
- Parameters:
  - testPlans: List of test plans to run.
  - configuration: Configuration to be used.
  - attachDebugger: A boolean controlling whether a debugger is attached to the process running the tests.
  - preActions: Actions to execute before running the tests.
  - postActions: Actions to execute after running the tests.
- Returns: A test action.

#### Parameters

| Name | Description |
| ---- | ----------- |
| testPlans | List of test plans to run. |
| configuration | Configuration to be used. |
| attachDebugger | A boolean controlling whether a debugger is attached to the process running the tests. |
| preActions | Actions to execute before running the tests. |
| postActions | Actions to execute after running the tests. |