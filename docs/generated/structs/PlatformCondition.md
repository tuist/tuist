**STRUCT**

# `PlatformCondition`

**Contents**

- [Properties](#properties)
  - `platformFilters`
- [Methods](#methods)
  - `when(_:)`

```swift
public struct PlatformCondition: Codable, Hashable, Equatable
```

A condition applied to an "entity" allowing it to only be used in certain circumstances

## Properties
### `platformFilters`

```swift
public let platformFilters: Set<PlatformFilter>
```

## Methods
### `when(_:)`

```swift
public static func when(_ platformFilters: Set<PlatformFilter>) -> PlatformCondition?
```

Creates a condition using the specified set of filters.
- Parameter platformFilters: filters to define which platforms this condition supports
- Returns: a `Condition` with the given set of filters or `nil` if empty.

#### Parameters

| Name | Description |
| ---- | ----------- |
| platformFilters | filters to define which platforms this condition supports |