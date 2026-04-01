**STRUCT**

# `TestableTarget`

**Contents**

- [Properties](#properties)
  - `target`
  - `isSkipped`
  - `isParallelizable`
  - `isRandomExecutionOrdering`
  - `simulatedLocation`
- [Methods](#methods)
  - `testableTarget(target:isSkipped:isParallelizable:isRandomExecutionOrdering:simulatedLocation:)`
  - `init(stringLiteral:)`

```swift
public struct TestableTarget: Equatable, Codable, ExpressibleByStringInterpolation, Sendable
```

## Properties
### `target`

```swift
public var target: TargetReference
```

### `isSkipped`

```swift
public var isSkipped: Bool
```

### `isParallelizable`

```swift
public var isParallelizable: Bool
```

### `isRandomExecutionOrdering`

```swift
public var isRandomExecutionOrdering: Bool
```

### `simulatedLocation`

```swift
public var simulatedLocation: SimulatedLocation?
```

## Methods
### `testableTarget(target:isSkipped:isParallelizable:isRandomExecutionOrdering:simulatedLocation:)`

```swift
public static func testableTarget(
    target: TargetReference,
    isSkipped: Bool = false,
    isParallelizable: Bool = false,
    isRandomExecutionOrdering: Bool = false,
    simulatedLocation: SimulatedLocation? = nil
) -> Self
```

Returns a testable target.

- Parameters:
  - target: The name or reference of target to test.
  - isSkipped: Whether to skip this test target. If true, the test target is disabled.
  - isParallelizable: Whether to run in parallel.
  - isRandomExecutionOrdering: Whether to test in random order.
  - simulatedLocation: The simulated GPS location to use when testing this target.
  Please note that the `.custom(gpxPath:)` case must refer to a valid GPX file in your project’s resources.

#### Parameters

| Name | Description |
| ---- | ----------- |
| target | The name or reference of target to test. |
| isSkipped | Whether to skip this test target. If true, the test target is disabled. |
| isParallelizable | Whether to run in parallel. |
| isRandomExecutionOrdering | Whether to test in random order. |
| simulatedLocation | The simulated GPS location to use when testing this target. Please note that the `.custom(gpxPath:)` case must refer to a valid GPX file in your project’s resources. |

### `init(stringLiteral:)`

```swift
public init(stringLiteral value: String)
```

#### Parameters

| Name | Description |
| ---- | ----------- |
| value | The value of the new instance. |