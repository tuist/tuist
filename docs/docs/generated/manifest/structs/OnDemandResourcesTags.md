**STRUCT**

# `OnDemandResourcesTags`

**Contents**

- [Properties](#properties)
  - `initialInstall`
  - `prefetchOrder`
- [Methods](#methods)
  - `tags(initialInstall:prefetchOrder:)`

```swift
public struct OnDemandResourcesTags: Codable, Equatable, Sendable
```

On-demand resources tags associated with Initial Install and Prefetched Order categories

## Properties
### `initialInstall`

```swift
public let initialInstall: [String]?
```

Initial install tags associated with on demand resources

### `prefetchOrder`

```swift
public let prefetchOrder: [String]?
```

Prefetched tag order associated with on demand resources

## Methods
### `tags(initialInstall:prefetchOrder:)`

```swift
public static func tags(initialInstall: [String]?, prefetchOrder: [String]?) -> Self
```

Returns OnDemandResourcesTags.
- Parameter initialInstall: An array of strings that lists the tags assosiated with the Initial install tags category.
- Parameter prefetchOrder: An array of strings that lists the tags associated with the Prefetch tag order category.
- Returns: OnDemandResourcesTags.

#### Parameters

| Name | Description |
| ---- | ----------- |
| initialInstall | An array of strings that lists the tags assosiated with the Initial install tags category. |
| prefetchOrder | An array of strings that lists the tags associated with the Prefetch tag order category. |