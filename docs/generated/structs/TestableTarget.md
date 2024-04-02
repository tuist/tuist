**STRUCT**

# `TestableTarget`

**Contents**

- [Properties](#properties)
  - `target`
  - `isSkipped`
  - `isParallelizable`
  - `isRandomExecutionOrdering`
- [Methods](#methods)
  - `testableTarget(target:isSkipped:isParallelizable:isRandomExecutionOrdering:)`
  - `init(stringLiteral:)`

```swift
public struct TestableTarget: Equatable, Codable, ExpressibleByStringInterpolation
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

## Methods
### `testableTarget(target:isSkipped:isParallelizable:isRandomExecutionOrdering:)`

```swift
public static func testableTarget(
    target: TargetReference,
    isSkipped: Bool = false,
    isParallelizable: Bool = false,
    isRandomExecutionOrdering: Bool = false
) -> Self
```

### `init(stringLiteral:)`

```swift
public init(stringLiteral value: String)
```

#### Parameters

| Name | Description |
| ---- | ----------- |
| value | The value of the new instance. |